#!/bin/sh
set -eu

CONFIG_FILE=/etc/telemt/config.toml

usage() {
    cat <<'EOF'
Usage: generate-links.sh [--config FILE]

Generates tg:// and https://t.me EE-TLS links from a Telemt config created by
setup-exit.sh. The default config path is /etc/telemt/config.toml.
EOF
}

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

extract_string() {
    key=$1
    sed -n "s|^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"\([^\"]*\)\"[[:space:]]*$|\1|p" "$CONFIG_FILE" \
        | awk 'NR == 1 { value = $0 } END { if (NR != 1) exit 1; print value }'
}

extract_integer() {
    key=$1
    sed -n "s|^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\([0-9][0-9]*\)[[:space:]]*$|\1|p" "$CONFIG_FILE" \
        | awk 'NR == 1 { value = $0 } END { if (NR != 1) exit 1; print value }'
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --config)
            [ "$#" -ge 2 ] || die "--config requires a value"
            CONFIG_FILE=$2
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

[ -r "$CONFIG_FILE" ] || die "cannot read config: $CONFIG_FILE"

PUBLIC_HOST=$(extract_string public_host) || die "config must contain exactly one public_host"
PUBLIC_PORT=$(extract_integer public_port) || die "config must contain exactly one public_port"
TLS_DOMAIN=$(extract_string tls_domain) || die "config must contain exactly one tls_domain"
USER_SECRET=$(extract_string hello) || die "config must contain exactly one hello user secret"

case "$PUBLIC_HOST" in
    ''|*[!A-Za-z0-9.-]*) die "public_host must be an IPv4 address or DNS name" ;;
esac
case "$PUBLIC_PORT" in
    ''|*[!0-9]*) die "public_port must be a number from 1 to 65535" ;;
esac
[ "$PUBLIC_PORT" -ge 1 ] && [ "$PUBLIC_PORT" -le 65535 ] \
    || die "public_port must be from 1 to 65535"
case "$TLS_DOMAIN" in
    ''|*[!A-Za-z0-9.-]*) die "tls_domain must be a DNS name" ;;
esac
case "$USER_SECRET" in
    *[!0-9A-Fa-f]*) die "hello user secret must contain only hexadecimal characters" ;;
esac
[ "${#USER_SECRET}" -eq 32 ] || die "hello user secret must contain exactly 32 hexadecimal characters"

DOMAIN_HEX=$(printf '%s' "$TLS_DOMAIN" | od -An -tx1 | tr -d ' \n')
EE_SECRET="ee${USER_SECRET}${DOMAIN_HEX}"

printf 'tg://proxy?server=%s&port=%s&secret=%s\n' "$PUBLIC_HOST" "$PUBLIC_PORT" "$EE_SECRET"
printf 'https://t.me/proxy?server=%s&port=%s&secret=%s\n' "$PUBLIC_HOST" "$PUBLIC_PORT" "$EE_SECRET"
