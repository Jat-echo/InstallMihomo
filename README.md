# Mihomo Ubuntu 一键安装脚本

这个仓库把笔记“Ubuntu下安装代理软件”整理成了可重复执行的 Ubuntu 安装脚本。脚本以**订阅链接**为主：下载时携带 Clash 风格的 User-Agent，让机场返回完整的 Clash.Meta 配置，并可通过 systemd 定时器**每天自动更新**。

默认流程：

1. 安装 `curl`、`wget`、`gzip`、`unzip` 等依赖，并安装 `yq`。
2. 下载 Mihomo 核心到 `/opt/clash/mihomo`。
3. 下载 `geoip.metadb`。
4. 用 Clash UA 从订阅链接下载配置（或复制 `--config` 指定的本地文件）。
5. 用 `yq` 写入 `external-controller: 0.0.0.0:9090`、`external-ui: ui`，以及可选的 `secret`。
6. 用 `mihomo -t` 校验配置，**通过才安装**，避免坏配置覆盖正在运行的配置。
7. 下载 MetaCubeXD 面板到 `/opt/clash/ui`。
8. 创建并启动 `clash.service`。
9. 安装 `clash-update.timer`，每天自动重新拉取订阅并重启服务。

## 快速使用

在 Ubuntu 服务器上执行（把 URL 换成你的订阅地址）：

```bash
sudo bash install-mihomo.sh --sub 'https://你的机场/订阅地址' --secret '换成你的面板密码'
```

不带 `--sub` 时，脚本会提示你输入订阅链接：

```bash
sudo bash install-mihomo.sh
```

> 订阅链接通常含有私密 token，会被保存在 `/opt/clash/update.env`（权限 600）供自动更新使用。本仓库不会上传你的配置或订阅信息。

## 使用本地配置文件

如果不想用订阅、直接用本地文件：

```bash
sudo bash install-mihomo.sh --config ./config.yaml --secret '换成你的面板密码'
```

本地文件方式不会安装自动更新定时器。

## 自动更新

默认安装 `clash-update.timer`，每天拉取订阅并重启服务。更新流程同样会带 Clash UA 下载、保留已设置的 `secret`、并用 `mihomo -t` 校验后才替换。

```bash
# 立即手动更新一次
sudo systemctl start clash-update.service

# 查看下次更新时间
systemctl list-timers clash-update.timer

# 查看更新日志
journalctl -u clash-update.service
```

自定义更新间隔：

```bash
sudo bash install-mihomo.sh --sub 'https://你的机场/订阅地址' --update-interval 12h
```

不安装自动更新：

```bash
sudo bash install-mihomo.sh --sub 'https://你的机场/订阅地址' --no-auto-update
```

## 常用参数

```text
--sub URL               订阅链接（带 Clash UA 下载完整配置）
--config-url URL        --sub 的别名
--config FILE           使用本地 Clash.Meta 配置文件
--secret SECRET         写入面板密码
--user-agent UA         下载订阅时使用的 User-Agent，默认 clash-verge/v2.3.2
--no-auto-update        不安装自动更新定时器
--update-interval VALUE 自动更新间隔（如 12h、6h），默认每天
--set-shell-proxy       写入 /etc/profile.d/mihomo-proxy.sh
--mihomo-version VER    指定 Mihomo 版本，默认 v1.19.2
--yq-version VER        指定 yq 版本，默认 v4.45.1
--github-proxy URL      指定 GitHub 下载代理，默认 https://gh-proxy.com/
--no-github-proxy       直接从 GitHub 下载
--no-ui                 不安装 MetaCubeXD 面板
--install-dir DIR       指定安装目录，默认 /opt/clash
--service-name NAME     指定 systemd 服务名，默认 clash
--skip-start            只安装，不启动服务和定时器
```

## 验证

查看服务状态：

```bash
systemctl status clash
```

查看日志：

```bash
journalctl -u clash -f
```

测试代理：

```bash
curl -x http://127.0.0.1:7890 https://www.google.com
```

访问面板：

```text
http://服务器IP:9090/ui
```

## 注意

- 脚本需要在 Ubuntu 上用 root 权限运行。
- 订阅服务按 User-Agent 区分返回内容：带 Clash UA 才会返回完整 Clash.Meta 配置，否则可能只返回原始节点链接列表。如遇配置异常，可用 `--user-agent` 换一个 Clash 客户端的 UA。
- 默认使用 `https://gh-proxy.com/` 加速 GitHub 下载；如果服务器能直接访问 GitHub，可以加 `--no-github-proxy`。
- `--set-shell-proxy` 只配置 shell 环境变量，不会修改桌面系统代理。
```
