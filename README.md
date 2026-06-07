# Codex 本机代理启动器 Skill

这个仓库是一个 Codex Skill，用来在 Windows 上创建一个“只让 Codex 走本机代理”的桌面启动器。

它适合解决这类情况：

- Codex 新对话启动时反复出现 WebSocket reconnect。
- Codex 日志里出现 `stream disconnected - retrying sampling request (1/5)`，随后 `falling back to HTTP`。
- 不想开启 TUN/全局代理，因为会影响其他网站或应用。
- 只想让 Codex 进程走 Clash、Mihomo、sing-box、NekoRay 等本机代理。

## 工作原理

脚本不会修改 Windows 系统代理，也不会影响浏览器或其他软件。

它会创建一个桌面快捷方式。这个快捷方式启动 Codex 前，只在当前 Codex 进程环境里设置：

```powershell
HTTP_PROXY
HTTPS_PROXY
ALL_PROXY
NO_PROXY
```

因此代理只对这次启动出来的 Codex 生效。

## 自动识别代理

默认安装时，脚本会按下面顺序自动寻找代理：

1. 用户手动传入的 `-ProxyUrl`
2. 环境变量：`HTTPS_PROXY`、`HTTP_PROXY`、`ALL_PROXY`
3. Windows 当前用户/系统代理设置
4. 常见本机代理端口

会探测的常见端口包括：

```text
10808, 10809, 7890, 7897, 7891, 2080, 2081, 1080, 1087, 8080, 20170, 20171
```

脚本会尽量判断端口是 HTTP/mixed 代理还是 SOCKS5 代理。优先使用 HTTP/mixed 代理，因为 Codex 对标准 `HTTP_PROXY` / `HTTPS_PROXY` 的兼容性更稳定。

## 使用方法

### 1. 安装 Skill

如果你的 Codex 支持从 GitHub 安装 skill，可以使用这个仓库：

```text
https://github.com/LikeWindc/codex-proxy-launcher-skill
```

也可以手动下载/克隆后，把目录作为 Codex skill 使用。

### 2. 运行安装脚本

进入 skill 目录后执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\install-codex-proxy-launcher.ps1
```

脚本会自动：

- 检测本机代理
- 定位 Windows 版 Codex 安装路径
- 在 `%LOCALAPPDATA%\CodexProxyLauncher` 写入启动脚本
- 在桌面创建 `Codex - Proxy Launcher.lnk`
- 给快捷方式使用 Codex 图标

之后先完全退出当前 Codex，再双击桌面的 `Codex - Proxy Launcher` 启动。

### 3. 手动指定代理端口

如果自动识别错了，或者你知道自己的代理端口，可以手动指定：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\install-codex-proxy-launcher.ps1 -ProxyUrl "http://127.0.0.1:7890"
```

其他本机代理客户端 mixed/http 端口示例：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\install-codex-proxy-launcher.ps1 -ProxyUrl "http://127.0.0.1:10808"
```

SOCKS5 示例：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\install-codex-proxy-launcher.ps1 -ProxyUrl "socks5h://127.0.0.1:10808"
```

## 验证是否生效

先确认本机代理端口可用：

```powershell
Test-NetConnection 127.0.0.1 -Port 7890 -InformationLevel Quiet
```

测试代理访问 ChatGPT：

```powershell
curl.exe -I -x http://127.0.0.1:7890 https://chatgpt.com/
```

如果你的代理端口是 `10808`，就改成：

```powershell
curl.exe -I -x http://127.0.0.1:10808 https://chatgpt.com/
```

查看 Codex 是否还在重试 WebSocket：

```powershell
sqlite3 "$env:USERPROFILE\.codex\logs_2.sqlite" "select datetime(ts,'unixepoch'), target, feedback_log_body from logs where feedback_log_body like '%stream disconnected - retrying sampling request%' order by ts desc limit 10;"
```

如果新对话不再出现连续 `1/5` 到 `5/5` 的 retry，说明代理启动器生效了。

## 参数说明

```powershell
-ProxyUrl
```

手动指定代理，例如 `http://127.0.0.1:7890` 或 `socks5h://127.0.0.1:10808`。

```powershell
-ShortcutName
```

自定义桌面快捷方式名称，默认是 `Codex - Proxy Launcher`。

```powershell
-NoProxy
```

自定义不走代理的地址，默认是 `localhost,127.0.0.1,::1`。

```powershell
-ForceRestart
```

生成的启动器可以强制关闭已有 Codex 进程后再启动。

```powershell
-NoDesktopShortcut
```

只生成启动脚本，不创建桌面快捷方式，适合测试或自动化环境。

## 注意事项

- 已经运行的 Codex 不会继承新代理环境，必须完全退出后重新用快捷方式启动。
- 这个方案是“按进程代理”，不是“只代理某个 WebSocket URL”。普通本机代理无法稳定按 TLS 加密后的路径分流。
- 如果你使用的是 Clash/Mihomo，建议使用 mixed/http 端口，比如 `7890`。
- 如果你的本机代理客户端使用 `10808` 等自定义端口，具体以你的软件设置为准。
- 如果代理客户端、端口或协议改变，重新运行安装脚本即可。

## License

MIT
