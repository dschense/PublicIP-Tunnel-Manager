#!/bin/bash

source config.sh

if [[ "$tun_proto" == "gre" && $(cat "/sys/class/net/$tun_if/carrier" 2>/dev/null) == "1" ]]; then
  current_remote_ip=$(ip tunnel show | grep "$tun_if" | awk '/remote/ {split ($4,A," "); print A[1]}')
elif [[ "$tun_proto" == "wg" && $(cat "/sys/class/net/$tun_if/carrier" 2>/dev/null) == "1" ]]; then
  current_remote_ip=$(wg show "$tun_if" endpoints | grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}")
fi

if [[ "$dynamic_ip" == "true" ]]; then
  remote_ip=$(cat "$ip_data" 2>/dev/null)
else
  remote_ip="$ip_data"
fi

function joinBy() {
  local IFS="$1";
  shift;
  echo "$*";
}

function parameter() {
  if [[ "$1" == "update" ]]; then
    if [[ "$tun_proto" == "gre" ]]; then
      updateIp
    else
      echo "Not using p2p tunnel like GRE. Peer IP update not needed."
    fi
  elif [[ "$1" == "delete" ]]; then
    deleteIp
  elif [[ "$1" == "up" ]]; then
    up
  elif [[ "$1" == "down" ]]; then
    down
  elif [[ "$1" == "gen" ]]; then
    if [[ "$tun_proto" == "wg" ]]; then
      gen_wg_conf
    else
      echo "Not using Wireguard. Config generation not needed."
    fi
  elif [[ "$1" == "-f" ]]; then
    main
  else
    status
  fi
}

function main() {
  if [[ ! $(cat "/sys/class/net/$tun_if/carrier" 2>/dev/null) == "1" ]]; then
    up
  else
    echo "Tunnel running. Exiting."
    exit 0
  fi
}

function status() {
  echo "This is Dry-Run/status mode!"
  echo "Please check all values and run this script again with '-f' option"
  echo ""
  echo "Primary NIC: $nic"
  echo ""
  echo "Tunnel Protocol: $tun_proto"
  echo "Tunnel Interface: $tun_if"
  echo ""
  echo "Interface Status:"
  ip addr | grep "$tun_if"
  echo ""
  ifconfig "$tun_if"

  echo "Tunnel Network: $tun_local_addr"
  echo "Tunnel Endpoint: $tun_remote_addr"
  echo ""

  echo "Public IPs used for home:"
  for i in "${public_ip[@]}"; do
    echo "$i"
  done
  echo "---------------------"
  if [[ $ipv6 == "true" && ${#public_ip6[@]} -ge 0 ]]; then
    for i in "${public_ip6[@]}"; do
      echo "$i"
    done
  fi

  echo "Home WAN IP: $remote_ip (Dynamic IP: $dynamic_ip)"

  if [[ $(cat /sys/class/net/$tun_if/carrier 2>/dev/null) == "1" ]]; then
    echo "Current WAN IP: $current_remote_ip"
    echo ""
    if [[ "$current_remote_ip" == "$remote_ip" ]]; then
      echo "WAN IPs match, Tunnel endpoint is correct"
    else
      echo "WAN IPs do not match, check tunnel endpoint IP"
    fi
  fi
  if ping -c 1 "$tun_remote_addr" &>/dev/null; then
    echo "Tunnel endpoint is reachable via ping"
  else
    echo "Tunnel endpoint is unreachable via ping"
  fi
}

function up() {
  if [[ ! $(cat "/sys/class/net/$tun_if/carrier" 2>/dev/null) == "1" ]]; then
    if [[ "$tun_proto" == "gre" ]]; then
      gre_up
    elif [[ "$tun_proto" == "wg" ]]; then
      wg_up
    fi
  fi
}

function gre_up() {
  ip tunnel add "$tun_if" mode gre local "$local_ip" remote "$remote_ip" ttl 255
  if [[ $greipv6 == "true" ]]; then
    ip tunnel add "$tun_if" mode ip6gre local "$local_ip" remote "$remote_ip" ttl 255
  fi

  ip addr add "$tun_local_addr" dev "$tun_if"
  if [[ $ipv6 == "true" ]]; then
    ip -6 addr add "$tun_local_addr6" dev "$tun_if"
  fi
  ip link set dev "$tun_if" mtu "$tun_mtu"
  ip link set "$tun_if" up

  ip route add "$tun_remote_addr" dev "$tun_if"
  if [[ $ipv6 == "true" ]]; then
    ip -6 route add "$tun_remote_addr6" dev "$tun_if"
  fi

  deleteIp

  for i in "${public_ip[@]}"; do
    ip route add "$i" dev "$tun_if"
    ip neigh add proxy "$(echo "$i" | cut -d/ -f1)" dev "$nic"
  done
  if [[ $ipv6 == "true" && ${#public_ip6[@]} -ge 0 ]]; then
    for i in "${public_ip6[@]}"; do
      ip -6 route add "$i" dev "$tun_if"
      ip -6 neigh add proxy "$(echo "$i" | cut -d/ -f1)" dev "$nic"
    done
  fi
}

function gen_wg_conf() {
  local ipString="$tun_remote_addr"

  if [[ ! ${#public_ip[@]} -eq 0 ]]; then
    ipString="$ipString,$(joinBy , "${public_ip[@]}")"
  fi
  if [[ $ipv6 == "true" && ${#public_ip6[@]} -ge 0 ]]; then
    ipString="$ipString,$tun_remote_addr6,$(joinBy , "${public_ip6[@]}")"
    local ip6Address="Address = $tun_local_addr6"
  fi

  : >$config
  cat >"$config" <<EOF
# configuration created on $(hostname) on $(date)
[Interface]
Address = $tun_local_addr
$ip6Address
ListenPort = $listenPort
PrivateKey = $privateKey
SaveConfig = false
MTU = $tun_mtu
[Peer]
PublicKey = $publicKey
AllowedIPs = $ipString
EOF
}

function wg_up() {
  gen_wg_conf

  wg-quick up "$tun_if"

  deleteIp

  for i in "${public_ip[@]}"; do
    ip neigh add proxy "$(echo "$i" | cut -d/ -f1)" dev "$nic"
  done
  if [[ $ipv6 == "true" && ${#public_ip6[@]} -ge 0 ]]; then
    for i in "${public_ip6[@]}"; do
      ip -6 neigh add proxy "$(echo "$i" | cut -d/ -f1)" dev "$nic"
    done
  fi
}

function down() {
  if [[ "$tun_proto" == "gre" ]]; then
    gre_down
  elif [[ "$tun_proto" == "wg" ]]; then
    wg_down
  fi
}

function gre_down() {
  for i in "${public_ip[@]}"; do
    ip route del "$i" dev "$tun_if"
    ip neigh del proxy "$(echo "$i" | cut -d/ -f1)" dev "$nic"
  done

  ip route del "$tun_remote_addr" dev "$tun_if"

  ip link set "$tun_if" down
  ip addr del "$tun_local_addr" dev "$tun_if"

  ip tunnel del "$tun_if" mode gre local "$local_ip" remote "$remote_ip" ttl 255
}

function wg_down() {
  for i in "${public_ip[@]}"; do
    ip neigh del proxy "$(echo "$i" | cut -d/ -f1)" dev "$nic"
  done
  if [[ $ipv6 == "true" && ${#public_ip6[@]} -ge 0 ]]; then
    for i in "${public_ip6[@]}"; do
      ip -6 neigh del proxy "$(echo "$i" | cut -d/ -f1)" dev "$nic"
    done
  fi

  wg-quick down "$tun_if"
}

function deleteIp() {
  for i in "${public_ip[@]}"; do
    if ip addr show "$nic" | grep -q "$i"; then
      echo "Public IP found on physical interface"
      echo "Deleting $i..."
      ip addr del "$i" dev "$nic"
    fi
  done
  if [[ $ipv6 == "true" && ${#public_ip6[@]} -ge 0 ]]; then
    for i in "${public_ip6[@]}"; do
      if ip -6 addr show "$nic" | grep -q "$i"; then
        echo "Public IPv6 found on physical interface"
        echo "Deleting $i..."
        ip -6 addr del "$i" dev "$nic"
      echo "Deleting $i..."
      ip -6 addr del "$i" dev "$nic"
      fi
    done
  fi
}

# Main execution block
if [[ "$#" -gt 0 ]]; then
  parameter "$1"
else
  status
fi
