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
    '--sub',
    '--config-url',
    '--config',
    '--secret',
    '--user-agent',
    '--no-auto-update',
    '--update-interval',
    'CLASH_USER_AGENT',
    'prompt_subscription',
    'require_root',
    'detect_arch',
    'install_yq',
    'yq_linux_',
    'download_mihomo',
    'fetch_subscription',
    'inject_runtime_keys',
    'validate_config',
    ' -t -d ',
    'install_config',
    'install_geoip',
    'install_dashboard',
    'install_systemd_service',
    'install_updater',
    'detect_public_ip',
    'ifconfig.me',
    'urlencode',
    'update.env',
    'update-config.sh',
    'set-update-interval.sh',
    'OnUnitActiveSec',
    '-update.timer',
    'WantedBy=timers.target',
    'systemctl daemon-reload',
    'systemctl enable --now',
    'systemctl restart',
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
