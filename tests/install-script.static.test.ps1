$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$scriptPath = Join-Path $repoRoot 'install-mihomo.sh'

if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "install-mihomo.sh does not exist"
}

$content = Get-Content -LiteralPath $scriptPath -Raw -Encoding UTF8

$requiredPatterns = @(
    '#!/usr/bin/env bash',
    'set -Eeuo pipefail',
    'Usage:',
    '--config',
    '--config-url',
    '--secret',
    '--set-shell-proxy',
    'require_root',
    'detect_arch',
    'download_mihomo',
    'install_config',
    'install_geoip',
    'install_dashboard',
    'install_systemd_service',
    'systemctl daemon-reload',
    'systemctl enable --now',
    'ExecStart=',
    '/mihomo -d ',
    'external-controller',
    'external-ui',
    'secret',
    'http://127.0.0.1:7890'
)

foreach ($pattern in $requiredPatterns) {
    if (-not $content.Contains($pattern)) {
        throw "install-mihomo.sh missing required content: $pattern"
    }
}

Write-Host 'install script static checks passed'
