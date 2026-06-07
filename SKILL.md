---
name: codex-v2ray-proxy-launcher
description: Create a Windows desktop launcher that starts Codex with an automatically detected local proxy only for the Codex process. Use when Codex WebSocket streaming disconnects, reconnects repeatedly, falls back to HTTP, or when the user wants Codex to use v2rayN, Clash, Mihomo, sing-box, NekoRay, or another local proxy without enabling TUN or changing system-wide proxy settings.
---

# Codex Proxy Launcher

## Overview

Use this skill to give Codex a process-scoped proxy on Windows. It creates a desktop shortcut with the Codex icon; the shortcut starts Codex through a small PowerShell launcher that sets proxy environment variables only for that Codex process.

This avoids TUN mode and does not change Windows system proxy, browser proxy, or other applications.

## Quick Start

1. Check that the user's proxy client is running.
2. Run the installer script from this skill:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\install-codex-v2ray-launcher.ps1
```

The script auto-detects the proxy in this order:

1. Explicit `-ProxyUrl`
2. `HTTPS_PROXY`, `HTTP_PROXY`, or `ALL_PROXY`
3. Windows user/system proxy settings
4. Common local proxy ports for v2rayN, Clash/Mihomo, sing-box, NekoRay, and similar clients

For a custom mixed HTTP port:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\install-codex-v2ray-launcher.ps1 -ProxyUrl "http://127.0.0.1:7890"
```

For a SOCKS port, only use this if the installed Codex build supports SOCKS proxy environment variables:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\install-codex-v2ray-launcher.ps1 -ProxyUrl "socks5h://127.0.0.1:10808"
```

## Workflow

1. Detect the local proxy:
   - Prefer an explicit `-ProxyUrl` when the user knows the port.
   - Otherwise use environment variables and Windows proxy settings.
   - Otherwise check common local ports: `10808`, `10809`, `7890`, `7897`, `7891`, `2080`, `2081`, `1080`, `1087`, `8080`, `20170`, `20171`.
   - Prefer HTTP/mixed proxy ports because Codex reliably honors standard `HTTP_PROXY` and `HTTPS_PROXY` environment variables.

2. Install the launcher:
   - Run `scripts/install-codex-v2ray-launcher.ps1`.
   - The script locates the current Windows Store Codex install through `Get-AppxPackage`.
   - It writes a support launcher under `%LOCALAPPDATA%\CodexProxyLauncher`.
   - It creates a desktop shortcut named `Codex - Proxy Launcher.lnk`.
   - The shortcut uses `Codex.exe` as its icon.

3. Use the launcher:
   - Fully quit existing Codex processes first.
   - Start Codex from the generated shortcut.
   - Open a new Codex conversation and check whether the repeated `responses_websocket` reconnects disappear.

## Verification

Use these checks when diagnosing:

```powershell
Get-ChildItem Env:*proxy*
```

```powershell
netsh winhttp show proxy
```

```powershell
curl.exe -I -x http://127.0.0.1:7890 https://chatgpt.com/
```

To inspect recent Codex retry logs:

```powershell
sqlite3 "$env:USERPROFILE\.codex\logs_2.sqlite" "select datetime(ts,'unixepoch'), target, feedback_log_body from logs where feedback_log_body like '%stream disconnected - retrying sampling request%' order by ts desc limit 10;"
```

## Notes

- This skill configures a process-scoped proxy, not a URL-path-specific proxy. TLS prevents reliable routing by encrypted paths such as `/backend-api/codex/responses` at a normal local proxy layer.
- Existing Codex processes keep their old environment. If Codex is already running, quit it before using the generated shortcut.
- If auto-detection chooses the wrong port, rerun the installer with `-ProxyUrl`.
