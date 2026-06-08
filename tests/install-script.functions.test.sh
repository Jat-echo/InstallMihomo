#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/install-mihomo.sh"

# --- proxied_url / normalize_proxy ---
GITHUB_PROXY="https://gh-proxy.com"
normalize_proxy
[[ "${GITHUB_PROXY}" == "https://gh-proxy.com/" ]] || { echo "normalize_proxy failed"; exit 1; }
[[ "$(proxied_url "https://github.com/x")" == "https://gh-proxy.com/https://github.com/x" ]] \
  || { echo "proxied_url failed"; exit 1; }

GITHUB_PROXY=""
[[ "$(proxied_url "https://github.com/x")" == "https://github.com/x" ]] \
  || { echo "proxied_url (no proxy) failed"; exit 1; }

# --- parse_args: subscription URL is primary, --config is the fallback ---
SUBSCRIPTION_URL="" ; CONFIG_FILE="" ; INSTALL_DIR="/opt/clash"
parse_args --sub "http://example.com/sub"
[[ "${SUBSCRIPTION_URL}" == "http://example.com/sub" && -z "${CONFIG_FILE}" ]] \
  || { echo "--sub did not populate SUBSCRIPTION_URL"; exit 1; }

parse_args --config "/tmp/local.yaml"
[[ "${CONFIG_FILE}" == "/tmp/local.yaml" && -z "${SUBSCRIPTION_URL}" ]] \
  || { echo "--config did not override subscription"; exit 1; }

parse_args --config-url "http://example.com/sub2"
[[ "${SUBSCRIPTION_URL}" == "http://example.com/sub2" ]] \
  || { echo "--config-url alias failed"; exit 1; }

parse_args --install-dir /opt/x
[[ "${MIHOMO_BIN}" == "/opt/x/mihomo" ]] \
  || { echo "MIHOMO_BIN not derived from --install-dir"; exit 1; }

# --- inject_runtime_keys: must work on JSON subscription output (needs yq) ---
if command -v yq >/dev/null 2>&1 && yq --version 2>/dev/null | grep -qi 'mikefarah'; then
  YQ_BIN="$(command -v yq)"
  tmp_file="$(mktemp)"
  trap 'rm -f "${tmp_file}"' EXIT
  printf '{"port": 7890, "external-controller": "127.0.0.1:9090"}\n' > "${tmp_file}"

  SECRET="a'b&c"
  inject_runtime_keys "${tmp_file}"

  [[ "$(yq '.["external-controller"]' "${tmp_file}")" == "0.0.0.0:9090" ]] \
    || { echo "external-controller not rewritten"; exit 1; }
  [[ "$(yq '.["external-ui"]' "${tmp_file}")" == "ui" ]] \
    || { echo "external-ui not set"; exit 1; }
  [[ "$(yq '.secret' "${tmp_file}")" == "a'b&c" ]] \
    || { echo "secret not set safely"; exit 1; }
  printf 'inject_runtime_keys checks passed (yq present)\n'
else
  printf 'skipping inject_runtime_keys checks (yq not installed)\n'
fi

printf 'install script function checks passed\n'
