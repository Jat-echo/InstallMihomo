#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/install-mihomo.sh"

tmp_file="$(mktemp)"
trap 'rm -f "${tmp_file}"' EXIT

cat > "${tmp_file}" <<'YAML'
external-controller: 127.0.0.1:9090
external-ui: old
secret: ''
YAML

set_yaml_top_level_key "external-controller" "0.0.0.0:9090" "${tmp_file}"
set_yaml_top_level_key "external-ui" "ui" "${tmp_file}"
set_yaml_top_level_key "secret" "$(yaml_single_quote "a'b&c")" "${tmp_file}"

grep -Fx "external-controller: 0.0.0.0:9090" "${tmp_file}"
grep -Fx "external-ui: ui" "${tmp_file}"
grep -Fx "secret: 'a''b&c'" "${tmp_file}"

printf 'install script function checks passed\n'
