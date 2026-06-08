#!/usr/bin/env bash
set -Eeuo pipefail

INSTALL_DIR="/opt/clash"
SERVICE_NAME="clash"
MIHOMO_VERSION="v1.19.2"
YQ_VERSION="v4.45.1"
GITHUB_PROXY="https://gh-proxy.com/"
CLASH_USER_AGENT="clash-verge/v2.3.2"
YQ_BIN="/usr/local/bin/yq"
MIHOMO_BIN=""
SUBSCRIPTION_URL=""
CONFIG_FILE=""
SECRET=""
INSTALL_UI=1
SET_SHELL_PROXY=0
START_SERVICE=1
AUTO_UPDATE=1
UPDATE_INTERVAL=""

usage() {
  cat <<'EOF'
Usage:
  sudo bash install-mihomo.sh --sub 'https://example.com/sub' [options]

The script needs a subscription URL (recommended) or a local config file.
If neither --sub nor --config is given, it prompts for a subscription URL.

Options:
  --sub URL               Subscription URL. Downloaded with a Clash User-Agent so
                          the provider returns a full Clash.Meta config.
  --config-url URL        Alias for --sub
  --config FILE           Use a local Clash.Meta config file instead of a subscription
  --secret SECRET         Set Clash external-controller secret in config.yaml
  --user-agent UA         User-Agent used to fetch the subscription. Defaults to clash-verge/v2.3.2
  --no-auto-update        Do not install the daily subscription auto-update timer
  --update-interval VALUE systemd interval for auto-update (e.g. 12h, 6h). Defaults to daily
  --set-shell-proxy       Add http_proxy/https_proxy exports via /etc/profile.d/mihomo-proxy.sh
  --mihomo-version VER    Mihomo version to install. Defaults to v1.19.2
  --yq-version VER        yq version to install. Defaults to v4.45.1
  --github-proxy URL      Prefix GitHub downloads with URL. Defaults to https://gh-proxy.com/
  --no-github-proxy       Download directly from GitHub
  --no-ui                 Skip MetaCubeXD dashboard installation
  --install-dir DIR       Install directory. Defaults to /opt/clash
  --service-name NAME     systemd service name. Defaults to clash
  --skip-start            Install files and service, but do not start/enable services
  -h, --help              Show this help

Examples:
  sudo bash install-mihomo.sh --sub 'https://example.com/sub' --secret 'change-me'
  sudo bash install-mihomo.sh --sub 'https://example.com/sub' --update-interval 12h
  sudo bash install-mihomo.sh --config ./config.yaml --no-auto-update
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
      --sub|--config-url)
        [[ $# -ge 2 ]] || die "$1 requires a URL"
        SUBSCRIPTION_URL="$2"
        CONFIG_FILE=""
        shift 2
        ;;
      --config)
        [[ $# -ge 2 ]] || die "--config requires a file path"
        CONFIG_FILE="$2"
        SUBSCRIPTION_URL=""
        shift 2
        ;;
      --secret)
        [[ $# -ge 2 ]] || die "--secret requires a value"
        SECRET="$2"
        shift 2
        ;;
      --user-agent)
        [[ $# -ge 2 ]] || die "--user-agent requires a value"
        CLASH_USER_AGENT="$2"
        shift 2
        ;;
      --no-auto-update)
        AUTO_UPDATE=0
        shift
        ;;
      --update-interval)
        [[ $# -ge 2 ]] || die "--update-interval requires a value (e.g. 12h)"
        UPDATE_INTERVAL="$2"
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
      --yq-version)
        [[ $# -ge 2 ]] || die "--yq-version requires a version"
        YQ_VERSION="$2"
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

  MIHOMO_BIN="${INSTALL_DIR}/mihomo"
}

prompt_subscription() {
  # A subscription URL is the primary input. Fall back to a local --config file,
  # otherwise ask for the subscription URL interactively.
  [[ -n "${SUBSCRIPTION_URL}" || -n "${CONFIG_FILE}" ]] && return 0

  if [[ -t 0 ]]; then
    printf '[mihomo-install] Enter subscription URL: '
    read -r SUBSCRIPTION_URL
  fi

  [[ -n "${SUBSCRIPTION_URL}" ]] || \
    die "no config source. Provide --sub URL (subscription) or --config FILE"
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

install_yq() {
  local arch yq_arch asset url
  if command -v yq >/dev/null 2>&1 && yq --version 2>/dev/null | grep -qi 'mikefarah'; then
    YQ_BIN="$(command -v yq)"
    log "Using existing yq: ${YQ_BIN}"
    return 0
  fi

  arch="$(detect_arch)"
  case "${arch}" in
    armv7) yq_arch="arm" ;;
    *) yq_arch="${arch}" ;;
  esac
  asset="yq_linux_${yq_arch}"
  url="https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${asset}"

  log "Installing yq ${YQ_VERSION}"
  curl -fL --retry 3 --connect-timeout 20 -o "${YQ_BIN}" "$(proxied_url "${url}")"
  chmod 0755 "${YQ_BIN}"
}

download_mihomo() {
  local arch asset url tmp_gz
  arch="$(detect_arch)"
  asset="mihomo-linux-${arch}-${MIHOMO_VERSION}.gz"
  url="https://github.com/MetaCubeX/Mihomo/releases/download/${MIHOMO_VERSION}/${asset}"
  tmp_gz="$(mktemp)"

  log "Downloading Mihomo ${MIHOMO_VERSION} for ${arch}"
  curl -fL --retry 3 --connect-timeout 20 -o "${tmp_gz}" "$(proxied_url "${url}")"
  gzip -dc "${tmp_gz}" > "${MIHOMO_BIN}"
  rm -f "${tmp_gz}"
  chmod 0755 "${MIHOMO_BIN}"
}

install_geoip() {
  local url
  url="https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.metadb"
  log "Downloading geoip.metadb"
  curl -fL --retry 3 --connect-timeout 20 -o "${INSTALL_DIR}/geoip.metadb" "$(proxied_url "${url}")"
}

fetch_subscription() {
  # $1 = destination file. Sends a Clash User-Agent so the provider returns a
  # full Clash.Meta config instead of a raw node-share-link list.
  local dest="$1"
  curl -fL --retry 3 --connect-timeout 20 \
    -A "${CLASH_USER_AGENT}" \
    -o "${dest}" "${SUBSCRIPTION_URL}"
}

inject_runtime_keys() {
  # Force the controller/dashboard keys and optional secret. yq parses both JSON
  # and YAML subscription output and rewrites it as YAML.
  local file="$1"
  "${YQ_BIN}" -i '.["external-controller"] = "0.0.0.0:9090" | .["external-ui"] = "ui"' "${file}"
  if [[ -n "${SECRET}" ]]; then
    SECRET="${SECRET}" "${YQ_BIN}" -i '.secret = strenv(SECRET)' "${file}"
  fi
}

validate_config() {
  # Test a candidate config with mihomo before letting it replace a working one.
  local candidate="$1" vdir
  vdir="$(mktemp -d)"
  cp "${candidate}" "${vdir}/config.yaml"
  mkdir -p "${vdir}/ui"
  [[ -f "${INSTALL_DIR}/geoip.metadb" ]] && ln -s "${INSTALL_DIR}/geoip.metadb" "${vdir}/geoip.metadb"

  if ! "${MIHOMO_BIN}" -t -d "${vdir}"; then
    rm -rf "${vdir}"
    die "config failed validation (mihomo -t). Not installing it."
  fi
  rm -rf "${vdir}"
}

install_config() {
  local candidate
  candidate="$(mktemp)"

  if [[ -n "${SUBSCRIPTION_URL}" ]]; then
    log "Downloading config from subscription URL (User-Agent: ${CLASH_USER_AGENT})"
    fetch_subscription "${candidate}"
  else
    [[ -f "${CONFIG_FILE}" ]] || die "config file not found: ${CONFIG_FILE}"
    cp "${CONFIG_FILE}" "${candidate}"
  fi

  # Re-install safety: if no --secret was given but a previous install already
  # set one, keep it instead of silently leaving the dashboard unprotected.
  if [[ -z "${SECRET}" && -f "${INSTALL_DIR}/config.yaml" ]]; then
    local existing
    existing="$("${YQ_BIN}" '.secret // ""' "${INSTALL_DIR}/config.yaml" 2>/dev/null || true)"
    if [[ -n "${existing}" && "${existing}" != "null" ]]; then
      SECRET="${existing}"
      log "Preserving existing dashboard secret (pass --secret to change it)"
    fi
  fi

  inject_runtime_keys "${candidate}"
  validate_config "${candidate}"
  install -m 0644 "${candidate}" "${INSTALL_DIR}/config.yaml"
  rm -f "${candidate}"
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

install_updater() {
  local env_file update_script interval_script service_file timer_file timer_schedule
  [[ "${AUTO_UPDATE}" -eq 1 && -n "${SUBSCRIPTION_URL}" ]] || return 0

  env_file="${INSTALL_DIR}/update.env"
  update_script="${INSTALL_DIR}/update-config.sh"
  interval_script="${INSTALL_DIR}/set-update-interval.sh"
  service_file="/etc/systemd/system/${SERVICE_NAME}-update.service"
  timer_file="/etc/systemd/system/${SERVICE_NAME}-update.timer"

  log "Writing auto-update env: ${env_file}"
  cat > "${env_file}" <<EOF
INSTALL_DIR='${INSTALL_DIR}'
SERVICE_NAME='${SERVICE_NAME}'
YQ_BIN='${YQ_BIN}'
CLASH_USER_AGENT='${CLASH_USER_AGENT}'
SUBSCRIPTION_URL='${SUBSCRIPTION_URL}'
EOF
  chmod 0600 "${env_file}"

  log "Writing auto-update script: ${update_script}"
  # Fully static: reads everything operational from update.env in the same dir.
  cat > "${update_script}" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${HERE}/update.env"

MIHOMO_BIN="${INSTALL_DIR}/mihomo"

log() { printf '[mihomo-update] %s\n' "$*"; }
die() { printf '[mihomo-update] ERROR: %s\n' "$*" >&2; exit 1; }

candidate="$(mktemp)"
trap 'rm -f "${candidate}"' EXIT

log "Fetching subscription"
curl -fL --retry 3 --connect-timeout 20 -A "${CLASH_USER_AGENT}" -o "${candidate}" "${SUBSCRIPTION_URL}"

"${YQ_BIN}" -i '.["external-controller"] = "0.0.0.0:9090" | .["external-ui"] = "ui"' "${candidate}"

# Preserve the secret set at install time.
old_secret="$("${YQ_BIN}" '.secret // ""' "${INSTALL_DIR}/config.yaml" 2>/dev/null || true)"
if [[ -n "${old_secret}" && "${old_secret}" != "null" ]]; then
  SECRET="${old_secret}" "${YQ_BIN}" -i '.secret = strenv(SECRET)' "${candidate}"
fi

vdir="$(mktemp -d)"
cp "${candidate}" "${vdir}/config.yaml"
mkdir -p "${vdir}/ui"
[[ -f "${INSTALL_DIR}/geoip.metadb" ]] && ln -s "${INSTALL_DIR}/geoip.metadb" "${vdir}/geoip.metadb"
if ! "${MIHOMO_BIN}" -t -d "${vdir}"; then
  rm -rf "${vdir}"
  die "downloaded config failed validation; keeping the current config"
fi
rm -rf "${vdir}"

install -m 0644 "${candidate}" "${INSTALL_DIR}/config.yaml"
log "Config updated; restarting ${SERVICE_NAME}"
systemctl restart "${SERVICE_NAME}"
EOF
  chmod 0755 "${update_script}"

  log "Writing interval helper: ${interval_script}"
  # Standalone command to change the timer schedule without re-running the
  # installer. Fully static; reads SERVICE_NAME from update.env in the same dir.
  cat > "${interval_script}" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${HERE}/update.env"

TIMER="${SERVICE_NAME}-update.timer"
TIMER_FILE="/etc/systemd/system/${TIMER}"

usage() {
  cat <<USAGE
Usage: $0 <interval>

  <interval> forms:
    6h | 12h | 30min | 1d     run every N (systemd time span)
    daily                     once a day (with up to 1h jitter)
    OnCalendar:<expr>         raw OnCalendar, e.g. OnCalendar:*-*-* 04:00:00

Examples:
  $0 6h
  $0 daily
  $0 'OnCalendar:*-*-* 04,16:00:00'
USAGE
}

if [[ $# -ne 1 || "$1" == "-h" || "$1" == "--help" ]]; then
  usage
  [[ $# -eq 1 && ( "$1" == "-h" || "$1" == "--help" ) ]] && exit 0 || exit 1
fi

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  exec sudo -- "$0" "$@"
fi

arg="$1"
case "${arg}" in
  daily)
    sched=$'OnCalendar=daily\nRandomizedDelaySec=1h'
    ;;
  OnCalendar:*)
    expr="${arg#OnCalendar:}"
    systemd-analyze calendar "${expr}" >/dev/null 2>&1 \
      || { printf 'ERROR: invalid OnCalendar expression: %s\n' "${expr}" >&2; exit 1; }
    sched="OnCalendar=${expr}"
    ;;
  *)
    systemd-analyze timespan "${arg}" >/dev/null 2>&1 \
      || { printf 'ERROR: invalid interval: %s (try 6h, 30min, daily, or OnCalendar:...)\n' "${arg}" >&2; exit 1; }
    sched=$'OnBootSec=10min\nOnUnitActiveSec='"${arg}"
    ;;
esac

cat > "${TIMER_FILE}" <<TEOF
[Unit]
Description=Scheduled Mihomo subscription update

[Timer]
${sched}
Persistent=true

[Install]
WantedBy=timers.target
TEOF

systemctl daemon-reload
systemctl enable --now "${TIMER}" >/dev/null 2>&1 || true
systemctl restart "${TIMER}"

printf 'Updated %s\n\n' "${TIMER_FILE}"
systemctl list-timers "${TIMER}" --no-pager
EOF
  chmod 0755 "${interval_script}"

  log "Writing auto-update service: ${service_file}"
  cat > "${service_file}" <<EOF
[Unit]
Description=Update Mihomo subscription config
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${update_script}
EOF

  if [[ -n "${UPDATE_INTERVAL}" ]]; then
    timer_schedule=$(printf 'OnBootSec=10min\nOnUnitActiveSec=%s' "${UPDATE_INTERVAL}")
  else
    timer_schedule=$(printf 'OnCalendar=daily\nRandomizedDelaySec=1h')
  fi

  log "Writing auto-update timer: ${timer_file}"
  cat > "${timer_file}" <<EOF
[Unit]
Description=Scheduled Mihomo subscription update

[Timer]
${timer_schedule}
Persistent=true

[Install]
WantedBy=timers.target
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

    if [[ "${AUTO_UPDATE}" -eq 1 && -n "${SUBSCRIPTION_URL}" ]]; then
      log "Enabling and starting ${SERVICE_NAME}-update.timer"
      systemctl enable --now "${SERVICE_NAME}-update.timer"
    fi
  else
    log "Skipped service start. Run: systemctl enable --now ${SERVICE_NAME}"
    if [[ "${AUTO_UPDATE}" -eq 1 && -n "${SUBSCRIPTION_URL}" ]]; then
      log "Auto-update timer not started. Run: systemctl enable --now ${SERVICE_NAME}-update.timer"
    fi
  fi
}

urlencode() {
  # Minimal RFC-3986 encoder so the secret survives in a query string.
  local s="$1" i c out=""
  for (( i = 0; i < ${#s}; i++ )); do
    c="${s:i:1}"
    case "${c}" in
      [a-zA-Z0-9.~_-]) out+="${c}" ;;
      *) printf -v c '%%%02X' "'${c}"; out+="${c}" ;;
    esac
  done
  printf '%s' "${out}"
}

detect_public_ip() {
  # MetaCubeXD defaults its backend to 127.0.0.1, which is wrong from a remote
  # browser. We can't change that frontend default, but we can print a link
  # that prefills the public IP. Try a few providers with a short timeout.
  local ip svc
  for svc in "https://ifconfig.me" "https://api.ipify.org" "https://ip.sb" "https://icanhazip.com"; do
    ip="$(curl -fsS --max-time 5 "${svc}" 2>/dev/null | tr -d '[:space:]')"
    if [[ "${ip}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      printf '%s' "${ip}"
      return 0
    fi
  done
  return 1
}

print_summary() {
  local ip public_ip qs
  ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  public_ip="$(detect_public_ip || true)"

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

Dashboard (in MetaCubeXD set the backend host to the server IP, NOT 127.0.0.1):
  Local:  http://127.0.0.1:9090/ui
EOF

  if [[ -n "${ip}" ]]; then
    printf '  LAN:    http://%s:9090/ui\n' "${ip}"
  fi

  if [[ -n "${public_ip}" ]]; then
    printf '  Public: http://%s:9090/ui\n' "${public_ip}"
    # Prefilled link: metacubexd reads hostname/port/secret from the query string.
    qs="hostname=${public_ip}&port=9090"
    [[ -n "${SECRET}" ]] && qs="${qs}&secret=$(urlencode "${SECRET}")"
    printf '  One-click (prefilled backend):\n    http://%s:9090/ui/?%s\n' "${public_ip}" "${qs}"
  else
    printf '  (could not detect public IP; open http://<server-ip>:9090/ui and set host to that IP)\n'
  fi

  if [[ "${AUTO_UPDATE}" -eq 1 && -n "${SUBSCRIPTION_URL}" ]]; then
    cat <<EOF

Auto-update:
  Schedule:    ${UPDATE_INTERVAL:-daily}
  Change every: ${INSTALL_DIR}/set-update-interval.sh 6h   (or: daily)
  Update now:  systemctl start ${SERVICE_NAME}-update.service
  Status:      systemctl list-timers ${SERVICE_NAME}-update.timer
  Logs:        journalctl -u ${SERVICE_NAME}-update.service
EOF
  fi

  if [[ -z "${SECRET}" ]]; then
    cat <<'EOF'

Notice:
  Dashboard secret was not changed because --secret was not provided.
  For remote access, rerun with --secret 'your-strong-password' or edit the config.
EOF
  fi
}

main() {
  parse_args "$@"
  normalize_proxy
  require_root
  prompt_subscription

  mkdir -p "${INSTALL_DIR}"
  install_packages
  install_yq
  download_mihomo
  install_geoip
  install_config
  install_dashboard
  install_systemd_service
  install_updater
  install_shell_proxy
  start_service
  print_summary
}

# Run main unless the script is being sourced (e.g. by the test suite).
# Using ${BASH_SOURCE[0]:-$0} also covers `curl ... | bash -s --` where
# BASH_SOURCE is unset under `set -u`.
if [[ "${BASH_SOURCE[0]:-$0}" == "$0" ]]; then
  main "$@"
fi
