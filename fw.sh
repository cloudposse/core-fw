#!/bin/bash
ACTION="$1"
ETCD_DISCOVERY_URL="$2"
DPORTS="${3:-4001,7001,8285,8472}"
CHAIN="${4:-CORE_FW}"
PATH="$PATH:/usr/sbin/"

function down() {
  iptables-save | grep -- " $CHAIN"|sed 's:-A:iptables -D:g' | bash
  iptables-save | grep -q "^:$CHAIN" && iptables -X "$CHAIN"
}

function fw() {
  args=($@)
  if [ "$1" = "-I" ] || [ "$1" = "-A" ]; then
    iptables -C ${args[@]:1} 2>/dev/null 
  elif [ "$1" = "-N" ]; then
    iptables-save | grep -q "^:$CHAIN"
  fi
  if [ $? -eq 0 ]; then
    # rule already exists
    echo "DUP: ${args[*]}" 
    return
  fi
  echo "NEW: ${args[*]}"
  cmd=(iptables ${args[*]})
  ${cmd[*]}
}

function up() {
  FLEET_IPS=$(curl -s $ETCD_DISCOVERY_URL | grep -o -E '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')
  fw -N $CHAIN || true
  fw -A $CHAIN -j DROP

  fw -I $CHAIN -i docker0 -j ACCEPT
  fw -I $CHAIN -i flannel0 -j ACCEPT
  fw -I $CHAIN -i lo -j ACCEPT

  for allow_ip in $FLEET_IPS; do
    fw -I $CHAIN -s "$allow_ip/32" -j ACCEPT
  done

  # Drop all incoming packets to $DPORTS
  fw -A INPUT -p tcp --match multiport --dport "$DPORTS" -j "$CHAIN"
  fw -A INPUT -p udp --match multiport --dport "$DPORTS" -j "$CHAIN"
}

if [ "$ACTION" = "up" ] || [ "$ACTION" = "down" ]; then
  $ACTION
else
  echo "Unsupported action: $ACTION"
  exit 1
fi


