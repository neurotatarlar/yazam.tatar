#!/usr/bin/env bash
set -euo pipefail

APP_USER=${APP_USER:-gec-tt-bot}
WG_INTERFACE=${WG_INTERFACE:-wg0}
VPN_TABLE=${VPN_TABLE:-51820}

if ! id -u "$APP_USER" >/dev/null 2>&1; then
  echo "User not found: $APP_USER" >&2
  exit 1
fi

APP_UID=$(id -u "$APP_USER")
TABLE_NAME=gec_tt_vpn
WAN_INTERFACE=${WAN_INTERFACE:-$(ip -4 route show default 2>/dev/null | awk 'NR==1 {print $5}')}
WG_ENDPOINT_PORT=${WG_ENDPOINT_PORT:-$(wg show "$WG_INTERFACE" endpoints 2>/dev/null | awk 'NR==1 && $2 != "(none)" {sub(/^.*:/, "", $2); print $2}')}
if [ -z "${WG_ENDPOINT_PORT:-}" ] && [ -f "/etc/wireguard/${WG_INTERFACE}.conf" ]; then
  WG_ENDPOINT_PORT=$(awk -F'[ =:]+' '/^Endpoint *=/ {print $NF; exit}' "/etc/wireguard/${WG_INTERFACE}.conf" 2>/dev/null || true)
fi
WG_ENDPOINT_RULE=""
if [ -n "${WAN_INTERFACE:-}" ] && [ -n "${WG_ENDPOINT_PORT:-}" ]; then
  WG_ENDPOINT_RULE="    meta skuid $APP_UID oifname \"$WAN_INTERFACE\" udp dport $WG_ENDPOINT_PORT accept"
fi

V4_RULES=(
  "10000:10.0.0.0/8"
  "10010:172.16.0.0/12"
  "10020:192.168.0.0/16"
  "10030:169.254.0.0/16"
  "10040:100.64.0.0/10"
  "10050:127.0.0.0/8"
)
V6_RULES=(
  "20000:fc00::/7"
  "20010:fe80::/10"
  "20020:::1/128"
)

add_v4_rules() {
  for entry in "${V4_RULES[@]}"; do
    pref="${entry%%:*}"
    cidr="${entry##*:}"
    ip -4 rule add pref "$pref" uidrange "$APP_UID-$APP_UID" to "$cidr" lookup main 2>/dev/null || true
  done
  ip -4 rule add pref 11000 uidrange "$APP_UID-$APP_UID" lookup "$VPN_TABLE" 2>/dev/null || true
  ip -4 route replace default dev "$WG_INTERFACE" table "$VPN_TABLE"
}

add_v6_rules() {
  for entry in "${V6_RULES[@]}"; do
    pref="${entry%%:*}"
    cidr="${entry##*:}"
    ip -6 rule add pref "$pref" uidrange "$APP_UID-$APP_UID" to "$cidr" lookup main 2>/dev/null || true
  done
  ip -6 rule add pref 21000 uidrange "$APP_UID-$APP_UID" lookup "$VPN_TABLE" 2>/dev/null || true
  ip -6 route replace default dev "$WG_INTERFACE" table "$VPN_TABLE" 2>/dev/null || true
}

remove_v4_rules() {
  for entry in "${V4_RULES[@]}"; do
    pref="${entry%%:*}"
    cidr="${entry##*:}"
    ip -4 rule del pref "$pref" uidrange "$APP_UID-$APP_UID" to "$cidr" lookup main 2>/dev/null || true
  done
  ip -4 rule del pref 11000 uidrange "$APP_UID-$APP_UID" lookup "$VPN_TABLE" 2>/dev/null || true
  ip -4 route flush table "$VPN_TABLE" 2>/dev/null || true
}

remove_v6_rules() {
  for entry in "${V6_RULES[@]}"; do
    pref="${entry%%:*}"
    cidr="${entry##*:}"
    ip -6 rule del pref "$pref" uidrange "$APP_UID-$APP_UID" to "$cidr" lookup main 2>/dev/null || true
  done
  ip -6 rule del pref 21000 uidrange "$APP_UID-$APP_UID" lookup "$VPN_TABLE" 2>/dev/null || true
  ip -6 route flush table "$VPN_TABLE" 2>/dev/null || true
}

apply_killswitch() {
  nft delete table inet "$TABLE_NAME" 2>/dev/null || true
  nft -f - <<EOF_NFT
table inet $TABLE_NAME {
  chain output {
    type filter hook output priority 0; policy accept;
    meta skuid $APP_UID oifname "lo" accept
    meta skuid $APP_UID oifname "$WG_INTERFACE" accept
$WG_ENDPOINT_RULE
    meta skuid $APP_UID ip daddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16, 100.64.0.0/10 } accept
    meta skuid $APP_UID ip6 daddr { fc00::/7, fe80::/10, ::1/128 } accept
    meta skuid $APP_UID counter drop
  }
}
EOF_NFT
}

remove_killswitch() {
  nft delete table inet "$TABLE_NAME" 2>/dev/null || true
}

action=${1:-}
if [ "$action" = "enable" ]; then
  add_v4_rules
  add_v6_rules
  apply_killswitch
  exit 0
fi

if [ "$action" = "disable" ]; then
  remove_killswitch
  remove_v6_rules
  remove_v4_rules
  exit 0
fi

echo "Usage: $0 enable|disable" >&2
exit 1
