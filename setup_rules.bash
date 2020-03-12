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

function cfg {
  jq -er "$1" "$CFG"; jq_ret=$?
  if [ $jq_ret -ne 0 ]; then echo "cfg: $1" >&2; fi
  exit $jq_ret
}

if [ "$CFG" == "" ] || ! [ -e "$CFG" ]; then 
  print_help
  exit 1
fi

ENDPOINT=$(cfg '.endpoint') || exit 2
NETWORK=$(cfg '.network') || exit 2
GATEWAY=$(cfg '.gateway') || exit 2
DEVICE=$(cfg '.device') || exit 2
CHAIN=$(cfg '.chain') || exit 2

CHAIN_FWD="${CHAIN}_fwd"
CHAIN_PRE="${CHAIN}_nat_pre"
CHAIN_PST="${CHAIN}_nat_post"

function new_chain {
  iptables -t $1 -N $2 2>/dev/null
  iptables -t $1 -F $2
}

function del_chain {
  iptables -t $1 -F $2
  iptables -t $1 -X $2
}

function toggle {
  iptables $1 OUTPUT -j $CHAIN
  iptables $1 FORWARD -j $CHAIN_FWD
  iptables -t nat $1 PREROUTING -j $CHAIN_PRE
  iptables -t nat $1 POSTROUTING -j $CHAIN_PST
}

if mode "on"; then
  exit 137
fi

if mode "setup"; then
  new_chain filter $CHAIN || exit 3
  iptables -A $CHAIN -d $NETWORK ! -o $DEVICE -j DROP
  iptables -A $CHAIN -d $ENDPOINT -j ACCEPT
  iptables -A $CHAIN -d 127.0.0.0/8,192.168.0.0/16,172.16.0.0/12,10.0.0.0/8 -j ACCEPT
  iptables -A $CHAIN -m state --state RELATED,ESTABLISHED -j ACCEPT
  iptables -A $CHAIN -j DROP

  new_chain filter $CHAIN_FWD
  iptables -A $CHAIN_FWD -d $ENDPOINT -j ACCEPT

  new_chain nat $CHAIN_PRE
  iptables -t nat -A $CHAIN_PRE -d $ENDPOINT -j DNAT --to-destination $GATEWAY

  new_chain nat $CHAIN_PST
  iptables -t nat -A $CHAIN_PST -d $ENDPOINT -o $DEVICE -j MASQUERADE
fi

if mode "clean"; then
  del_chain filter $CHAIN
  del_chain filter  $CHAIN_FWD
  del_chain nat $CHAIN_PRE
  del_chain nat $CHAIN_PST
fi

if [ "$VALID_MODE" != "1" ]; then
  print_help
  exit 1
fi

