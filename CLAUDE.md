# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 概述

本仓库的核心是一个 Bash 脚本（`install-mihomo.sh`），用于在 Ubuntu 上把 Mihomo（Clash.Meta）代理内核安装为 systemd 服务，并附带安装 MetaCubeXD 网页面板。脚本以**订阅链接**为主输入：带 Clash 风格 User-Agent 下载完整配置，并安装一个 systemd timer 实现每日自动更新。把手写笔记 `Ubuntu下安装代理软件 *.md` 整理成了可重复执行、幂等的安装器。文档（`README.md`）为中文。

## 常用命令

两个测试相互独立，都必须通过：

```bash
# 行为测试 —— source 脚本后调用其中的 YAML 编辑函数（在 Linux/bash 下运行）
bash tests/install-script.functions.test.sh

# 静态测试 —— grep install-mihomo.sh 中必须存在的内容（在 Windows/PowerShell 下运行）
pwsh tests/install-script.static.test.ps1   # 或：powershell -File tests/install-script.static.test.ps1
```

没有构建步骤。要实际运行安装器需要一台 root 权限的 Ubuntu 主机（脚本会调用 `apt-get`、写入 `/opt/clash`、管理 systemd）——不要在开发机上运行它。

## 架构

脚本由一组职责单一的小函数组成，由文件底部的 `main()` 编排。后续修改必须保留以下设计要点：

- **可被 source**：`main "$@"` 只在 `[[ "${BASH_SOURCE[0]}" == "$0" ]]` 守卫下执行，因此测试可以 `source` 脚本来单独调用各个函数（如 `parse_args`、`proxied_url`、`inject_runtime_keys`）而不触发安装。请保留此守卫，并保持函数可被独立调用。
- **订阅是按 User-Agent 区分内容的**（关键）：目标机场对带 Clash 风格 UA（默认 `clash-verge/v2.3.2`，可 `--user-agent` 覆盖）的请求返回完整 Clash.Meta 配置，对默认 UA 只返回原始 `vless://` 节点分享链接列表。因此 `fetch_subscription` 必须带 `-A "${CLASH_USER_AGENT}"`，更新脚本里也一样。返回体常常是 **JSON**（JSON 是 YAML 超集，Mihomo 能解析）。
- **配置改写用 yq，不要用按行 awk/sed**：`inject_runtime_keys` 用 `yq` 写 `external-controller`/`external-ui`/`secret`，因为订阅返回的 JSON 用行匹配会产出非法 YAML。dash 键必须用 `.["external-controller"]` 括号形式；`secret` 用 `strenv(SECRET)` 注入以安全处理特殊字符。`yq`（mikefarah）由 `install_yq` 安装，优先复用系统已有的。
- **下载即校验**（`validate_config`）：候选配置先经 `mihomo -t -d <tmpdir>`（临时目录里软链 `geoip.metadb`、建空 `ui/`）校验，**通过才用 `install -m 0644` 落到 `config.yaml`**，避免一次坏抓取搞挂正在运行的服务。
- **自动更新**（`install_updater`，仅订阅模式且未 `--no-auto-update` 时）：把操作参数写入 `${INSTALL_DIR}/update.env`（含订阅 URL 与 UA，权限 600），生成完全静态的 `update-config.sh`（用 `<<'EOF'` 引号 heredoc，运行时 `source update.env`），以及 `${SERVICE_NAME}-update.service`/`.timer`。更新流程：带 UA 下载 → yq 注入并**保留旧 `secret`** → `mihomo -t` 校验 → 替换 → `systemctl restart`。默认 `OnCalendar=daily`，`--update-interval` 改用 `OnUnitActiveSec`。
- **GitHub 下载代理**：所有 GitHub release 下载（mihomo、geoip、yq、面板）都经过 `proxied_url`（前缀 `GITHUB_PROXY`，默认 `https://gh-proxy.com/`，`--no-github-proxy` 清空）。新增 github.com 下载应走它；订阅 URL（`--sub`）不应经过它。
- **架构映射**（`detect_arch`）：把 `uname -m` 映射为 `amd64`/`arm64`/`armv7`；yq 资产名需把 `armv7` 转成 `arm`。未知架构直接报错退出。

两个测试守护的内容不同——PowerShell 静态测试断言脚本中存在一组必需的字符串模式，因此重命名函数、参数或 systemd 单元名都会让它失败。bash 行为测试在 `yq` 存在时才跑 `inject_runtime_keys` 校验（否则跳过）。当有意改动这些内容时，请同步更新 `tests/install-script.static.test.ps1` 的 `$requiredPatterns` 和 `tests/install-script.functions.test.sh`。

## 约定

- 脚本启用了 `set -Eeuo pipefail`；输出请用 `die`/`log`，变量优先用 `local`。
- `.gitignore` 排除了 `*.yaml`/`*.yml`（只跟踪 `*.sample.yaml/yml`），因此用户的代理配置不会被提交。仓库里残留的 `ClashMeta-UAH-20260602.yaml` 是早期写死的样例，现已不再被脚本引用（改用订阅链接），且本就被 git 忽略。
- 既是默认值也是文档化行为的设置，作为文件顶部的全局变量存在（`INSTALL_DIR=/opt/clash`、`SERVICE_NAME=clash`、`MIHOMO_VERSION` 等）。代理监听 `127.0.0.1:7890`；面板/API 监听 `:9090`。
