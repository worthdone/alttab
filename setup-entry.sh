#!/bin/sh
set -eu

BACKEND_IP=""
BACKEND_PORT=8443
LISTEN_PORT=443
INGRESS_INTERFACE=""
FORWARD_CHAIN=ALTTAB_FORWARD
PREROUTING_CHAIN=ALTTAB_PREROUTING
POSTROUTING_CHAIN=ALTTAB_POSTROUTING

usage() {
    cat <<'EOF'
Usage: setup-entry.sh --backend-ip IPV4 [OPTIONS]

Options:
  --backend-port PORT  Telemt port on the exit host (default: 8443)
  --listen-port PORT   Client-facing entry host port (default: 443)
  --interface NAME     Limit forwarding to one ingress interface
  -h, --help           Show this help
EOF
}

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

validate_port() {
    case "$2" in
        ''|*[!0-9]*) die "$1 must be a number from 1 to 65535" ;;
    esac
    [ "$2" -ge 1 ] && [ "$2" -le 65535 ] || die "$1 must be from 1 to 65535"
}

validate_ipv4() {
    old_ifs=$IFS
    IFS=.
    set -- $1
    IFS=$old_ifs
    [ "$#" -eq 4 ] || return 1
    for octet in "$@"; do
        case "$octet" in
            ''|*[!0-9]*) return 1 ;;
            0) ;;
            0*) return 1 ;;
        esac
        [ "$octet" -le 255 ] || return 1
    done
}

ensure_chain() {
    table=$1
    chain=$2
    if ! iptables -w -t "$table" -n -L "$chain" >/dev/null 2>&1; then
        iptables -w -t "$table" -N "$chain"
    fi
    iptables -w -t "$table" -F "$chain"
}

ensure_jump() {
    table=$1
    chain=$2
    target=$3
    if ! iptables -w -t "$table" -C "$chain" -j "$target" >/dev/null 2>&1; then
        iptables -w -t "$table" -I "$chain" 1 -j "$target"
    fi
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --backend-ip)
            [ "$#" -ge 2 ] || die "--backend-ip requires a value"
            BACKEND_IP=$2
            shift 2
            ;;
        --backend-port)
            [ "$#" -ge 2 ] || die "--backend-port requires a value"
            BACKEND_PORT=$2
            shift 2
            ;;
        --listen-port)
            [ "$#" -ge 2 ] || die "--listen-port requires a value"
            LISTEN_PORT=$2
            shift 2
            ;;
        --interface)
            [ "$#" -ge 2 ] || die "--interface requires a value"
            INGRESS_INTERFACE=$2
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown argument: $1"
            ;;
    esac
done

[ "$(id -u)" -eq 0 ] || die "run this script as root"
validate_ipv4 "$BACKEND_IP" || die "--backend-ip must be a valid IPv4 address"
validate_port "--backend-port" "$BACKEND_PORT"
validate_port "--listen-port" "$LISTEN_PORT"
case "$INGRESS_INTERFACE" in
    *[!A-Za-z0-9_.:-]*) die "--interface contains unsupported characters" ;;
esac

command -v apt-get >/dev/null 2>&1 || die "this script requires Debian or Ubuntu with apt-get"
DEBIAN_FRONTEND=noninteractive apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent netfilter-persistent curl

printf '%s\n' 'net.ipv4.ip_forward = 1' > /etc/sysctl.d/99-ip-forward.conf
sysctl -w net.ipv4.ip_forward=1 >/dev/null

ensure_chain filter "$FORWARD_CHAIN"
ensure_chain nat "$PREROUTING_CHAIN"
ensure_chain nat "$POSTROUTING_CHAIN"
ensure_jump filter FORWARD "$FORWARD_CHAIN"
ensure_jump nat PREROUTING "$PREROUTING_CHAIN"
ensure_jump nat POSTROUTING "$POSTROUTING_CHAIN"

iptables -w -A "$FORWARD_CHAIN" \
    -p tcp -d "$BACKEND_IP" --dport "$BACKEND_PORT" \
    -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
iptables -w -A "$FORWARD_CHAIN" \
    -p tcp -s "$BACKEND_IP" --sport "$BACKEND_PORT" \
    -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

if [ -n "$INGRESS_INTERFACE" ]; then
    iptables -w -t nat -A "$PREROUTING_CHAIN" \
        -i "$INGRESS_INTERFACE" -p tcp --dport "$LISTEN_PORT" \
        -m addrtype --dst-type LOCAL \
        -j DNAT --to-destination "${BACKEND_IP}:${BACKEND_PORT}"
else
    iptables -w -t nat -A "$PREROUTING_CHAIN" \
        -p tcp --dport "$LISTEN_PORT" \
        -m addrtype --dst-type LOCAL \
        -j DNAT --to-destination "${BACKEND_IP}:${BACKEND_PORT}"
fi

iptables -w -t nat -A "$POSTROUTING_CHAIN" \
    -p tcp -d "$BACKEND_IP" --dport "$BACKEND_PORT" -j MASQUERADE

netfilter-persistent save

printf 'Forwarding TCP port %s to %s:%s.\n' "$LISTEN_PORT" "$BACKEND_IP" "$BACKEND_PORT"
PUBLIC_IP=$(curl -fsS4 --max-time 10 https://api.ipify.org 2>/dev/null || true)
if [ -n "$PUBLIC_IP" ]; then
    printf 'Entry public IPv4 address: %s\n' "$PUBLIC_IP"
fi
