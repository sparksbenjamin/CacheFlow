#!/usr/bin/env bash
# LanCache Pi-hole DNS installer
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/sparksbenjamin/CacheFlow/main/install.sh | sudo bash -s -- <LANCACHE_IP>

set -euo pipefail

REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/sparksbenjamin/CacheFlow/main}"
PIHOLE_CONF="${PIHOLE_CONF:-/etc/dnsmasq.d/05-lancache.conf}"

usage() {
    cat <<EOF

Usage: curl -fsSL ${REPO_RAW}/install.sh | sudo bash -s -- <LANCACHE_IP>
Example: curl -fsSL ${REPO_RAW}/install.sh | sudo bash -s -- 192.168.1.100

EOF
}

valid_ipv4() {
    local ip octet
    [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    IFS='.' read -r -a octets <<< "$1"
    for octet in "${octets[@]}"; do
        [[ "$octet" =~ ^[0-9]+$ ]] || return 1
        (( octet >= 0 && octet <= 255 )) || return 1
    done
}

if [[ $# -lt 1 ]]; then
    usage
    exit 1
fi

LANCACHE_IP="$1"

if ! valid_ipv4 "$LANCACHE_IP"; then
    echo "Error: '$LANCACHE_IP' is not a valid IPv4 address."
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
    echo "Error: please run with sudo."
    exit 1
fi

for cmd in curl pihole grep sed mktemp mv chmod; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: '$cmd' is not installed or not in PATH."
        exit 1
    fi
done

enable_extra_dnsmasq_dir() {
    if command -v pihole-FTL >/dev/null 2>&1; then
        current_setting="$(pihole-FTL --config misc.etc_dnsmasq_d 2>/dev/null || true)"
        if [[ "$current_setting" == "false" ]]; then
            echo "==> Enabling /etc/dnsmasq.d loading in Pi-hole FTL..."
            pihole-FTL --config misc.etc_dnsmasq_d true
        fi
    fi
}

tmp_file="$(mktemp)"
cleanup() {
    rm -f "$tmp_file"
}
trap cleanup EXIT

echo ""
echo "LanCache Pi-hole Installer"
echo "LanCache IP : $LANCACHE_IP"
echo "Output file : $PIHOLE_CONF"
echo ""

echo "==> Downloading pre-built conf from GitHub..."
curl -fsSL "${REPO_RAW}/lancache.conf" \
    | sed "s/LANCACHE_IP/${LANCACHE_IP}/g" \
    > "$tmp_file"

entries="$(grep -c '^address=' "$tmp_file" || true)"
if [[ "$entries" -eq 0 ]]; then
    echo "Error: downloaded config did not contain any dnsmasq address rules."
    exit 1
fi

if grep -q 'LANCACHE_IP' "$tmp_file"; then
    echo "Error: placeholder replacement failed."
    exit 1
fi

chmod 0644 "$tmp_file"
mv "$tmp_file" "$PIHOLE_CONF"
trap - EXIT

echo "==> Installed $entries DNS entries to $PIHOLE_CONF"
enable_extra_dnsmasq_dir
echo "==> Reloading Pi-hole DNS..."
pihole reloaddns

echo ""
echo "Done. LanCache DNS routing is active."
echo "Re-run the same command any time to refresh from the latest config."
echo ""
