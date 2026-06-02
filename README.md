# Mihomo Ubuntu 一键安装脚本

这个仓库把笔记“Ubuntu下安装代理软件”整理成了可重复执行的 Ubuntu 安装脚本。

默认流程：

1. 安装 `curl`、`wget`、`gzip`、`unzip` 等依赖。
2. 下载 Mihomo 核心到 `/opt/clash/mihomo`。
3. 下载 `geoip.metadb`。
4. 复制你提供的 Clash.Meta 配置文件到 `/opt/clash/config.yaml`。
5. 确保配置中启用 `external-controller: 0.0.0.0:9090` 和 `external-ui: ui`。
6. 下载 MetaCubeXD 面板到 `/opt/clash/ui`。
7. 创建并启动 `clash.service` systemd 服务。

## 快速使用

先把你的 Clash.Meta 配置文件放到脚本同目录，文件名使用 `ClashMeta-UAH-20260602.yaml`，然后在 Ubuntu 服务器上执行：

```bash
sudo bash install-mihomo.sh --secret '换成你的面板密码'
```

如果不想设置面板密码：

```bash
sudo bash install-mihomo.sh
```

这个仓库不会上传你的 YAML 配置文件。也可以用 `--config` 或 `--config-url` 明确指定配置来源。

## 使用其他配置

使用本地配置文件：

```bash
sudo bash install-mihomo.sh --config ./config.yaml --secret '换成你的面板密码'
```

使用订阅或配置 URL：

```bash
sudo bash install-mihomo.sh --config-url 'https://example.com/your-config.yaml' --secret '换成你的面板密码'
```

## 常用参数

```text
--config FILE           使用本地 Clash.Meta 配置文件
--config-url URL        从 URL 下载配置文件
--secret SECRET         写入 external-controller 面板密码
--set-shell-proxy       写入 /etc/profile.d/mihomo-proxy.sh
--mihomo-version VER    指定 Mihomo 版本，默认 v1.19.2
--github-proxy URL      指定 GitHub 下载代理，默认 https://gh-proxy.com/
--no-github-proxy       直接从 GitHub 下载
--no-ui                 不安装 MetaCubeXD 面板
--install-dir DIR       指定安装目录，默认 /opt/clash
--service-name NAME     指定 systemd 服务名，默认 clash
--skip-start            只安装，不启动服务
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
- 默认使用 `https://gh-proxy.com/` 加速 GitHub 下载；如果服务器能直接访问 GitHub，可以加 `--no-github-proxy`。
- `--set-shell-proxy` 只配置 shell 环境变量，不会修改桌面系统代理。
