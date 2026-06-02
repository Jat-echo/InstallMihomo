#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

INSTALL_DIR="/opt/clash"
SERVICE_NAME="clash"
MIHOMO_VERSION="v1.19.2"
GITHUB_PROXY="https://gh-proxy.com/"
DEFAULT_CONFIG="${SCRIPT_DIR}/ClashMeta-UAH-20260602.yaml"
CONFIG_FILE="${DEFAULT_CONFIG}"
CONFIG_URL=""
SECRET=""
INSTALL_UI=1
SET_SHELL_PROXY=0
START_SERVICE=1

usage() {
  cat <<'EOF'
Usage:
  sudo bash install-mihomo.sh [options]

Options:
  --config FILE           Use a local Clash.Meta config file. Defaults to ./ClashMeta-UAH-20260602.yaml
  --config-url URL        Download config.yaml from a subscription/config URL instead of using --config
  --secret SECRET         Set Clash external-controller secret in /opt/clash/config.yaml
  --set-shell-proxy       Add http_proxy/https_proxy exports through /etc/profile.d/mihomo-proxy.sh
  --mihomo-version VER    Mihomo version to install. Defaults to v1.19.2
  --github-proxy URL      Prefix GitHub downloads with URL. Defaults to https://gh-proxy.com/
  --no-github-proxy       Download directly from GitHub
  --no-ui                 Skip MetaCubeXD dashboard installation
  --install-dir DIR       Install directory. Defaults to /opt/clash
  --service-name NAME     systemd service name. Defaults to clash
  --skip-start            Install files and service, but do not start/enable the service
  -h, --help              Show this help

Examples:
  sudo bash install-mihomo.sh --secret 'change-me'
  sudo bash install-mihomo.sh --config ./config.yaml --secret 'change-me'
  sudo bash install-mihomo.sh --config-url 'https://example.com/sub.yaml' --no-github-proxy
EOF
}

log() {
  printf '[mihomo-install] %s\n' "$*"
}

die() {
  printf '[mihomo-install] ERROR: %s\n' "$*" >&2
  exit 1
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "please run as root, for example: sudo bash install-mihomo.sh"
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config)
        [[ $# -ge 2 ]] || die "--config requires a file path"
        CONFIG_FILE="$2"
        CONFIG_URL=""
        shift 2
        ;;
      --config-url)
        [[ $# -ge 2 ]] || die "--config-url requires a URL"
        CONFIG_URL="$2"
        shift 2
        ;;
      --secret)
        [[ $# -ge 2 ]] || die "--secret requires a value"
        SECRET="$2"
        shift 2
        ;;
      --set-shell-proxy)
        SET_SHELL_PROXY=1
        shift
        ;;
      --mihomo-version)
        [[ $# -ge 2 ]] || die "--mihomo-version requires a version"
        MIHOMO_VERSION="$2"
        shift 2
        ;;
      --github-proxy)
        [[ $# -ge 2 ]] || die "--github-proxy requires a URL"
        GITHUB_PROXY="$2"
        shift 2
        ;;
      --no-github-proxy)
        GITHUB_PROXY=""
        shift
        ;;
      --no-ui)
        INSTALL_UI=0
        shift
        ;;
      --install-dir)
        [[ $# -ge 2 ]] || die "--install-dir requires a directory"
        INSTALL_DIR="$2"
        shift 2
        ;;
      --service-name)
        [[ $# -ge 2 ]] || die "--service-name requires a name"
        SERVICE_NAME="$2"
        shift 2
        ;;
      --skip-start)
        START_SERVICE=0
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "unknown option: $1"
        ;;
    esac
  done
}

normalize_proxy() {
  if [[ -n "${GITHUB_PROXY}" && "${GITHUB_PROXY}" != */ ]]; then
    GITHUB_PROXY="${GITHUB_PROXY}/"
  fi
}

proxied_url() {
  local url="$1"
  printf '%s%s' "${GITHUB_PROXY}" "${url}"
}

install_packages() {
  log "Installing required packages"
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates \
    curl \
    gzip \
    unzip \
    wget
}

detect_arch() {
  local machine
  machine="$(uname -m)"
  case "${machine}" in
    x86_64|amd64)
      printf 'amd64'
      ;;
    aarch64|arm64)
      printf 'arm64'
      ;;
    armv7l|armv7)
      printf 'armv7'
      ;;
    *)
      die "unsupported architecture: ${machine}"
      ;;
  esac
}

download_mihomo() {
  local arch asset url tmp_gz
  arch="$(detect_arch)"
  asset="mihomo-linux-${arch}-${MIHOMO_VERSION}.gz"
  url="https://github.com/MetaCubeX/Mihomo/releases/download/${MIHOMO_VERSION}/${asset}"
  tmp_gz="$(mktemp)"

  log "Downloading Mihomo ${MIHOMO_VERSION} for ${arch}"
  curl -fL --retry 3 --connect-timeout 20 -o "${tmp_gz}" "$(proxied_url "${url}")"
  gzip -dc "${tmp_gz}" > "${INSTALL_DIR}/mihomo"
  rm -f "${tmp_gz}"
  chmod 0755 "${INSTALL_DIR}/mihomo"
}

install_geoip() {
  local url
  url="https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.metadb"
  log "Downloading geoip.metadb"
  curl -fL --retry 3 --connect-timeout 20 -o "${INSTALL_DIR}/geoip.metadb" "$(proxied_url "${url}")"
}

yaml_single_quote() {
  local value="$1"
  value="$(printf '%s' "${value}" | sed "s/'/''/g")"
  printf "'%s'" "${value}"
}

set_yaml_top_level_key() {
  local key="$1"
  local value="$2"
  local file="$3"
  local tmp_file
  tmp_file="$(mktemp)"

  awk -v key="${key}" -v value="${value}" '
    BEGIN { found = 0 }
    $0 ~ "^" key ":" {
      print key ": " value
      found = 1
      next
    }
    { print }
    END {
      if (!found) {
        print ""
        print key ": " value
      }
    }
  ' "${file}" > "${tmp_file}"

  mv "${tmp_file}" "${file}"
}

install_config() {
  log "Installing config.yaml"

  if [[ -n "${CONFIG_URL}" ]]; then
    curl -fL --retry 3 --connect-timeout 20 -o "${INSTALL_DIR}/config.yaml" "${CONFIG_URL}"
  else
    [[ -f "${CONFIG_FILE}" ]] || die "config file not found: ${CONFIG_FILE}"
    cp "${CONFIG_FILE}" "${INSTALL_DIR}/config.yaml"
  fi

  set_yaml_top_level_key "external-controller" "0.0.0.0:9090" "${INSTALL_DIR}/config.yaml"
  set_yaml_top_level_key "external-ui" "ui" "${INSTALL_DIR}/config.yaml"

  if [[ -n "${SECRET}" ]]; then
    set_yaml_top_level_key "secret" "$(yaml_single_quote "${SECRET}")" "${INSTALL_DIR}/config.yaml"
  fi

  chmod 0644 "${INSTALL_DIR}/config.yaml"
}

install_dashboard() {
  local zip_file tmp_dir extracted_dir url
  [[ "${INSTALL_UI}" -eq 1 ]] || return 0

  url="https://github.com/MetaCubeX/metacubexd/archive/refs/heads/gh-pages.zip"
  zip_file="$(mktemp)"
  tmp_dir="$(mktemp -d)"

  log "Installing MetaCubeXD dashboard"
  curl -fL --retry 3 --connect-timeout 20 -o "${zip_file}" "$(proxied_url "${url}")"
  unzip -q "${zip_file}" -d "${tmp_dir}"
  extracted_dir="${tmp_dir}/metacubexd-gh-pages"

  [[ -d "${extracted_dir}" ]] || die "dashboard archive layout is unexpected"

  rm -rf "${INSTALL_DIR}/ui"
  mv "${extracted_dir}" "${INSTALL_DIR}/ui"
  rm -f "${zip_file}"
  rm -rf "${tmp_dir}"
}

install_systemd_service() {
  local service_file
  service_file="/etc/systemd/system/${SERVICE_NAME}.service"

  log "Writing systemd service: ${service_file}"
  cat > "${service_file}" <<EOF
[Unit]
Description=Mihomo Clash Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/mihomo -d ${INSTALL_DIR}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
}

install_shell_proxy() {
  local proxy_file
  [[ "${SET_SHELL_PROXY}" -eq 1 ]] || return 0

  proxy_file="/etc/profile.d/mihomo-proxy.sh"
  log "Writing shell proxy environment: ${proxy_file}"
  cat > "${proxy_file}" <<'EOF'
export http_proxy=http://127.0.0.1:7890
export https_proxy=http://127.0.0.1:7890
export HTTP_PROXY=http://127.0.0.1:7890
export HTTPS_PROXY=http://127.0.0.1:7890
EOF
  chmod 0644 "${proxy_file}"
}

start_service() {
  if [[ "${START_SERVICE}" -eq 1 ]]; then
    log "Enabling and starting ${SERVICE_NAME}.service"
    systemctl enable --now "${SERVICE_NAME}"
    systemctl restart "${SERVICE_NAME}"
    systemctl --no-pager --full status "${SERVICE_NAME}" || true
  else
    log "Skipped service start. Run: systemctl enable --now ${SERVICE_NAME}"
  fi
}

print_summary() {
  local ip
  ip="$(hostname -I 2>/dev/null | awk '{print $1}')"

  cat <<EOF

Mihomo installation finished.

Config:  ${INSTALL_DIR}/config.yaml
Binary:  ${INSTALL_DIR}/mihomo
Service: ${SERVICE_NAME}.service
Proxy:   http://127.0.0.1:7890

Useful commands:
  systemctl status ${SERVICE_NAME}
  journalctl -u ${SERVICE_NAME} -f
  curl -x http://127.0.0.1:7890 https://www.google.com

Dashboard:
  Local:  http://127.0.0.1:9090/ui
EOF

  if [[ -n "${ip}" ]]; then
    printf '  Remote: http://%s:9090/ui\n' "${ip}"
  fi

  if [[ -z "${SECRET}" ]]; then
    cat <<'EOF'

Notice:
  Dashboard secret was not changed because --secret was not provided.
  For remote access, rerun with --secret 'your-strong-password' or edit /opt/clash/config.yaml.
EOF
  fi
}

main() {
  parse_args "$@"
  normalize_proxy
  require_root

  mkdir -p "${INSTALL_DIR}"
  install_packages
  download_mihomo
  install_geoip
  install_config
  install_dashboard
  install_systemd_service
  install_shell_proxy
  start_service
  print_summary
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
