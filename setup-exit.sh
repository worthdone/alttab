#!/bin/sh
set -eu

BACKEND_PORT=8443
PUBLIC_PORT=443
TLS_DOMAIN=""
PUBLIC_HOST=""
USER_SECRET=""
CONTAINER_NAME=telemt
IMAGE_NAME=telemt:local
CONFIG_DIR=/etc/telemt
CONFIG_FILE="${CONFIG_DIR}/config.toml"
TEMP_CONFIG=""

usage() {
    cat <<'EOF'
Usage: setup-exit.sh --tls-domain DOMAIN --public-host HOST [OPTIONS]

Options:
  --backend-port PORT  Exit host port published by Docker (default: 8443)
  --public-port PORT   Port advertised in Telegram links (default: 443)
  --secret HEX         Existing 32-character hexadecimal user secret
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

validate_host() {
    case "$2" in
        ''|*[!A-Za-z0-9.-]*) die "$1 must be an IPv4 address or DNS name" ;;
    esac
}

cleanup() {
    if [ -n "$TEMP_CONFIG" ] && [ -f "$TEMP_CONFIG" ]; then
        rm -f "$TEMP_CONFIG"
    fi
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --tls-domain)
            [ "$#" -ge 2 ] || die "--tls-domain requires a value"
            TLS_DOMAIN=$2
            shift 2
            ;;
        --public-host)
            [ "$#" -ge 2 ] || die "--public-host requires a value"
            PUBLIC_HOST=$2
            shift 2
            ;;
        --backend-port)
            [ "$#" -ge 2 ] || die "--backend-port requires a value"
            BACKEND_PORT=$2
            shift 2
            ;;
        --public-port)
            [ "$#" -ge 2 ] || die "--public-port requires a value"
            PUBLIC_PORT=$2
            shift 2
            ;;
        --secret)
            [ "$#" -ge 2 ] || die "--secret requires a value"
            USER_SECRET=$2
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
validate_host "--tls-domain" "$TLS_DOMAIN"
validate_host "--public-host" "$PUBLIC_HOST"
validate_port "--backend-port" "$BACKEND_PORT"
validate_port "--public-port" "$PUBLIC_PORT"

if [ -n "$USER_SECRET" ]; then
    case "$USER_SECRET" in
        *[!0-9A-Fa-f]*) die "--secret must contain only hexadecimal characters" ;;
    esac
    [ "${#USER_SECRET}" -eq 32 ] || die "--secret must contain exactly 32 hexadecimal characters"
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
[ -f "${SCRIPT_DIR}/Dockerfile" ] || die "Dockerfile was not found next to this script"
[ -f "${SCRIPT_DIR}/config.toml" ] || die "config.toml was not found next to this script"

if ! command -v docker >/dev/null 2>&1; then
    command -v apt-get >/dev/null 2>&1 || die "apt-get is required to install Docker"
    DEBIAN_FRONTEND=noninteractive apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io
fi

if ! docker info >/dev/null 2>&1 && command -v systemctl >/dev/null 2>&1; then
    systemctl enable --now docker
fi
docker info >/dev/null 2>&1 || die "the Docker daemon is not available"

case "$(uname -m)" in
    x86_64|amd64) TARGET_ARCH=amd64 ;;
    aarch64|arm64) TARGET_ARCH=arm64 ;;
    *) die "unsupported architecture: $(uname -m)" ;;
esac

install -d -m 0700 "$CONFIG_DIR"
if [ ! -f "$CONFIG_FILE" ]; then
    install -m 0600 "${SCRIPT_DIR}/config.toml" "$CONFIG_FILE"
fi

if [ -z "$USER_SECRET" ]; then
    USER_SECRET=$(sed -n 's/^hello = "\([0-9A-Fa-f][0-9A-Fa-f]*\)"$/\1/p' "$CONFIG_FILE" | tail -n 1)
    if [ "${#USER_SECRET}" -ne 32 ] || [ "$USER_SECRET" = "00000000000000000000000000000000" ]; then
        USER_SECRET=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
    fi
fi

TEMP_CONFIG=$(mktemp "${CONFIG_FILE}.XXXXXX")
trap cleanup EXIT HUP INT TERM
sed \
    -e "s|^[#[:space:]]*public_host[[:space:]]*=.*$|public_host = \"${PUBLIC_HOST}\"|" \
    -e "s|^[#[:space:]]*public_port[[:space:]]*=.*$|public_port = ${PUBLIC_PORT}|" \
    -e "s|^tls_domain[[:space:]]*=.*$|tls_domain = \"${TLS_DOMAIN}\"|" \
    -e "s|^hello[[:space:]]*=.*$|hello = \"${USER_SECRET}\"|" \
    "$CONFIG_FILE" > "$TEMP_CONFIG"
grep -Fqx "public_host = \"${PUBLIC_HOST}\"" "$TEMP_CONFIG" || die "public_host is missing from the generated config"
grep -Fqx "public_port = ${PUBLIC_PORT}" "$TEMP_CONFIG" || die "public_port is missing from the generated config"
grep -Fqx "tls_domain = \"${TLS_DOMAIN}\"" "$TEMP_CONFIG" || die "tls_domain is missing from the generated config"
grep -Fqx "hello = \"${USER_SECRET}\"" "$TEMP_CONFIG" || die "user secret is missing from the generated config"
install -m 0600 "$TEMP_CONFIG" "$CONFIG_FILE"
rm -f "$TEMP_CONFIG"
TEMP_CONFIG=""

docker build \
    -t "$IMAGE_NAME" \
    --build-arg "TARGETARCH=${TARGET_ARCH}" \
    --target minimal \
    "$SCRIPT_DIR"

if docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
    docker rm -f "$CONTAINER_NAME" >/dev/null
fi

docker run -d \
    --restart unless-stopped \
    --name "$CONTAINER_NAME" \
    -p "${BACKEND_PORT}:443" \
    -e RUST_LOG=info \
    -v "${CONFIG_FILE}:/app/config.toml:ro" \
    --cap-drop ALL \
    --cap-add NET_BIND_SERVICE \
    --ulimit nofile=65536:65536 \
    "$IMAGE_NAME" \
    /telemt /app/config.toml >/dev/null

printf 'Telemt is running on exit port %s.\n' "$BACKEND_PORT"
printf 'Connection links:\n'
docker logs "$CONTAINER_NAME" 2>&1 | grep 'tg://' || true
