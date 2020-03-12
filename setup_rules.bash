#!/bin/bash

MODE=$1
CFG=$2

function mode {
  [ "$MODE" == "$1" ] || return 1
  echo "Mode: $1"
  VALID_MODE=1
}

function print_help {
  echo "Usage: leak-rules <COMMAND> <CONFIG>"
  echo "Commands: setup, clear, on, off"
}

function cfgerr {
  echo "cfg: $1 should be set"
  exit 2
}

if [ "$CFG" == "" ] || ! [ -e "$CFG" ]; then 
  print_help
  exit 1
fi

DEFAULT_DEVICE="tun+"
FINAL_RULE="DROP"
INSERT_TO="A"
CHAIN="ovpn_leak"

C_OUT="OUTPUT"
C_FWD="FORWARD"
C_PRE="PREROUTING"
C_PST="POSTROUTING"

EP_C=0

while read -r key; do
  if [ "$EP_END" != "1" ]; then 
    case "$key" in 
      "==")
        (( EP_C++ ))
        continue;;
      "==options==")
        EP_END=1
        continue;;
    esac

    read -r val
    case "$key" in
      'endpoint') ENDPOINT[$EP_C]="$val";;
      'network') NETWORK[$EP_C]="$val";;
      'gateway') GATEWAY[$EP_C]="$val";;
      'device') DEVICE[$EP_C]="$val";;
    esac
  else
    read -r val
    case "$key" in 
      'chain') CHAIN="$val";;
      'final_rule') FINAL_RULE="$val";;
      'insert_to') INSERT_TO="$val";;
      'output_chain') C_OUT="$val";;
      'forward_chain') C_FWD="$val";;
      'nat_prerouting_chain') C_PRE="$val";;
      'nat_postrouting_chain') C_PST="$val";;
    esac
  fi
done < <(jq -er '(.endpoints | .[] | (. | to_entries | .[] | .key, .value), "=="),
"==options==", (.options | to_entries | .[] | .key, .value)' "$CFG") || exit 2

[ "${#ENDPOINT[*]}" -ne "$EP_C" ] || cfgerr "endpoint"
[ "${#NETWORK[*]}" -ne "$EP_C" ] || cfgerr "network"
[ "${#GATEWAY[*]}" -ne "$EP_C" ] || cfgerr "gateway"

CHAIN_FWD="${CHAIN}_fwd"
CHAIN_PRE="${CHAIN}_nat_pre"
CHAIN_PST="${CHAIN}_nat_post"

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
    'add') iptables -t "$table" "$I_ARG" "$chain" $I_IDX $@;;
    'del') iptables -t "$table" -D "$chain" $@;;
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
  inject $1 filter $C_OUT -j $CHAIN
  inject $1 filter $C_FWD -j $CHAIN_FWD 2>/dev/null
  inject $1 nat $C_PRE -j $CHAIN_PRE 2>/dev/null
  inject $1 nat $C_PST -j $CHAIN_PST 2>/dev/null
}

if mode "on"; then
  toggle add
fi

if mode "off"; then 
  toggle del
fi

if mode "setup"; then
  new_chain filter $CHAIN || exit 3

  for i in $(seq 0 "$EP_C"); do
    E_DEV="${DEVICE[$i]}"; E_EP="${ENDPOINT[$i]}"
    E_GW="${GATEWAY[$i]}"; E_NET="${NETWORK[$i]}"
    [ "$E_DEV" != "" ] || E_DEV="$DEFAULT_DEVICE"

    iptables -A $CHAIN -d $E_NET ! -o $E_DEV -j DROP 2>/dev/null # todo option
    iptables -A $CHAIN -s $E_NET -o $E_DEV -j ACCEPT 2>/dev/null
    iptables -A $CHAIN -d $E_EP -j ACCEPT
  done

  iptables -A $CHAIN -d 127.0.0.0/8,192.168.0.0/16,172.16.0.0/12,10.0.0.0/8 -j ACCEPT
  iptables -A $CHAIN -m state --state RELATED,ESTABLISHED -j ACCEPT
  iptables -A $CHAIN -j $FINAL_RULE

  new_chain filter $CHAIN_FWD
  iptables -A $CHAIN_FWD -d $GATEWAY -j ACCEPT

  new_chain nat $CHAIN_PRE
  iptables -t nat -A $CHAIN_PRE -d $ENDPOINT -j DNAT --to-destination $GATEWAY

  new_chain nat $CHAIN_PST
  iptables -t nat -A $CHAIN_PST -d $GATEWAY -o $DEVICE -j MASQUERADE
fi

if mode "clean"; then
  toggle del
  del_chain filter $CHAIN
  del_chain filter  $CHAIN_FWD 2>/dev/null
  del_chain nat $CHAIN_PRE 2>/dev/null
  del_chain nat $CHAIN_PST 2>/dev/null
fi

if [ "$VALID_MODE" != "1" ]; then
  print_help
  exit 1
fi

