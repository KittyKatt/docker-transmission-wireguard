#!/bin/bash

if [ $FIREWALL -eq 1 ]; then
  iptables -A INPUT -p tcp -i wg0 --dport "$1" -j ACCEPT
  iptables -A INPUT -p udp -i wg0 --dport "$1" -j ACCEPT
  echo "$(date): Allowing incoming traffic on port $1"
fi

WG_IP=$(ip addr show wg0 | awk '/inet/ {gsub(/\/32/, ""); print $2}' | tee /pia-shared/ip.dat)
PEER_PORT="${1}"

/scripts/start-services.sh "${PEER_PORT}" "${WG_IP}"