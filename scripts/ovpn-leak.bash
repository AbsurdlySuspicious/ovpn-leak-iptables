#!/bin/bash
# shellcheck disable=SC2086 source=config_example

function print_help {
  echo "Usage: ovpn-leak [-c <CONFIG>] <MODE>"
  echo "Modes: setup, clear, on, off"
}

while [ "$1" != "" ]; do
  case "$1" in
    '-h'|'--help')
      print_help
      exit 0 ;;
    '-c')
      [ "$CFG" == "" ] || { echo "Config should be specified only once"; exit 2; }
      [ "$2" != "" ] || { echo "Config should be specifed after -c"; exit 2; }
      CFG="$2"; shift 2 ;;
    -*)
      echo "Unknown arg: $1"
      exit 2 ;;
    *)
      [ "$MODE" == "" ] || { echo "Unknown arg: $1"; exit 2; }
      MODE="$1"
      shift ;;
  esac
done

if [ "$CFG" == "" ]; then
  CFG=$XDG_CONFIG_HOME
  [ "$CFG" != "" ] || { [ "$HOME" != "" ] && CFG="$HOME/.config"; } || exit 2
  CFG="$CFG/ovpn-leak/config"
  echo "Using default config: $CFG"
fi

if ! [ -f "$CFG" ]; then
  echo "Config $CFG doesn't exist"; exit 2
fi

if [ "$MODE" == "" ]; then
  echo "Mode should be specified"; exit 2
fi

function mode {
  [ "$MODE" == "$1" ] || return 1
  echo "Mode: $1"
  VALID_MODE=1
}

function cfgerr {
  echo "cfg: $1 should be set"
  exit 2
}

FINAL_RULE="DROP"
INSERT_TO="A"
CHAIN="ovpn_leak"
WHITELIST=""

CHAIN_OUTPUT="OUTPUT"
CHAIN_NAT_OUTPUT="OUTPUT"
CHAIN_NAT_POSTROUTING="POSTROUTING"

_ep=0
_has_strict=0

function ep_unset {
  ep_server=""; ep_network=""; ep_gateway="";
  ep_device="tun+"; ep_strict=0; ep_strict_icmp=1;
  ep_strict_udp=""; ep_strict_tcp="";
}

function ep_commit {
  [ "$ep_server" != "" ] || cfgerr "endpoint ($_ep)"
  [ "$ep_network" != "" ] || cfgerr "network ($_ep)"
  [ "$ep_strict" != "1" ] || [ "$ep_gateway" != "" ] || cfgerr "gateway ($_ep)"

  ENDPOINT[$_ep]=$ep_server
  NETWORK[$_ep]=$ep_network
  GATEWAY[$_ep]=$ep_gateway
  DEVICE[$_ep]=$ep_device

  if [ "$ep_strict" == 1 ]; then
    _has_strict=1
    STRICT_ICMP[$_ep]="$ep_strict_icmp"
    STRICT_TCP[$_ep]="$ep_strict_tcp"
    STRICT_UDP[$_ep]="$ep_strict_udp"
  fi

  ep_unset
  (( _ep++ ))
}

ep_unset
source "$CFG"

TCHAIN_NAT_OUT="${CHAIN}_nat_out"
TCHAIN_NAT_POST="${CHAIN}_nat_post"

case "$INSERT_TO" in 
  'A') I_ARG='-A';;
  ''|*[!0-9]*) echo "cfg: bad insert_to"; exit 2;;
  *) I_ARG='-I'; I_IDX="$INSERT_TO";;
esac

function inject {
  mode=$1; shift
  table=$1; shift
  chain=$1; shift

  case "$mode" in
    'add') iptables -t "$table" "$I_ARG" "$chain" $I_IDX "$@";;
    'del') iptables -t "$table" -D "$chain" "$@";;
  esac
}

function new_chain {
  iptables -t $1 -N $2 2>/dev/null
  iptables -t $1 -F $2
}

function del_chain {
  iptables -t $1 -F $2
  iptables -t $1 -X $2
}

function toggle {
  inject $1 filter $CHAIN_OUTPUT -j $CHAIN
  inject $1 nat $CHAIN_NAT_OUTPUT -j $TCHAIN_NAT_OUT 2>/dev/null
  inject $1 nat $CHAIN_NAT_POSTROUTING -j $TCHAIN_NAT_POST 2>/dev/null
}

function clean {
  toggle del 2>/dev/null
  del_chain filter $CHAIN
  del_chain nat $TCHAIN_NAT_OUT 2>/dev/null
  del_chain nat $TCHAIN_NAT_POST 2>/dev/null
}

if mode "on"; then
  toggle add
fi

if mode "off"; then 
  toggle del
fi

if mode "clear"; then
  clean
fi

if mode "setup"; then
  clean 2>/dev/null
  new_chain filter $CHAIN || exit 3

  if [ "$_has_strict" == 1 ]; then
    new_chain nat $TCHAIN_NAT_OUT
    new_chain nat $TCHAIN_NAT_POST
  fi

  for i in $(seq 0 "$(( _ep-1 ))"); do
    E_DEV="${DEVICE[$i]}"; E_EP="${ENDPOINT[$i]}"
    E_GW="${GATEWAY[$i]}"; E_NET="${NETWORK[$i]}"
    E_ST_ICMP="${STRICT_ICMP[$i]}";
    E_ST_UDP="${STRICT_UDP[$i]}";
    E_ST_TCP="${STRICT_TCP[$i]}";

    iptables -A $CHAIN -s $E_NET -o $E_DEV -j ACCEPT 2>/dev/null

    if [ "$E_ST_ICMP" == "" ]; then
      iptables -A $CHAIN -d $E_EP -j ACCEPT
    else
      if [ "$E_ST_ICMP" == 1 ]; then 
        iptables -A $CHAIN -d $E_EP -p icmp -j ACCEPT
        iptables -t nat -A $TCHAIN_NAT_OUT -d $E_EP -p icmp -j RETURN
      fi

      if [ "$E_ST_UDP" != "" ]; then 
        iptables -A $CHAIN -d $E_EP -p udp -m multiport --dports "$E_ST_UDP" -j ACCEPT
        iptables -t nat -A $TCHAIN_NAT_OUT -d $E_EP -p udp -m multiport --dports "$E_ST_UDP" -j RETURN
      fi

      if [ "$E_ST_TCP" != "" ]; then 
        iptables -A $CHAIN -d $E_EP -p tcp -m multiport --dports "$E_ST_TCP" -j ACCEPT
        iptables -t nat -A $TCHAIN_NAT_OUT -d $E_EP -p tcp -m multiport --dports "$E_ST_TCP" -j RETURN
      fi

      iptables -t nat -A $TCHAIN_NAT_OUT -d $E_EP -j DNAT --to-destination $E_GW
      iptables -t nat -A $TCHAIN_NAT_POST -d $E_GW -o $E_DEV -j MASQUERADE
    fi
  done

  if [ "$WHITELIST" != "" ]; then
    iptables -A $CHAIN -d "$WHITELIST" -j ACCEPT
  fi

  iptables -A $CHAIN -d 127.0.0.0/8,192.168.0.0/16,172.16.0.0/12,10.0.0.0/8 -j ACCEPT
  iptables -A $CHAIN -m state --state RELATED,ESTABLISHED -j ACCEPT
  iptables -A $CHAIN -j $FINAL_RULE

fi

if [ "$VALID_MODE" != 1 ]; then
  print_help
  exit 1
fi

