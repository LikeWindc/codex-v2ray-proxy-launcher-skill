param(
  [string]$ProxyUrl = "",
  [string]$ShortcutName = "Codex - Proxy Launcher",
  [string]$NoProxy = "localhost,127.0.0.1,::1",
  [switch]$ForceRestart,
  [switch]$NoDesktopShortcut
)

$ErrorActionPreference = "Stop"

function Test-TcpPort {
  param(
    [string]$HostName,
    [int]$Port,
    [int]$TimeoutMs = 500
  )

  $client = [System.Net.Sockets.TcpClient]::new()
  try {
    $iar = $client.BeginConnect($HostName, $Port, $null, $null)
    if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
      return $false
    }
    $client.EndConnect($iar)
    return $true
  } catch {
    return $false
  } finally {
    $client.Close()
  }
}

function Test-HttpProxyPort {
  param(
    [int]$Port,
    [int]$TimeoutMs = 1500
  )

  $client = [System.Net.Sockets.TcpClient]::new()
  try {
    $iar = $client.BeginConnect("127.0.0.1", $Port, $null, $null)
    if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
      return $false
    }
    $client.EndConnect($iar)
    $client.ReceiveTimeout = $TimeoutMs
    $client.SendTimeout = $TimeoutMs
    $stream = $client.GetStream()
    $probe = "CONNECT chatgpt.com:443 HTTP/1.1`r`nHost: chatgpt.com:443`r`n`r`n"
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($probe)
    $stream.Write($bytes, 0, $bytes.Length)
    $buffer = New-Object byte[] 128
    $read = $stream.Read($buffer, 0, $buffer.Length)
    if ($read -le 0) {
      return $false
    }
    $text = [System.Text.Encoding]::ASCII.GetString($buffer, 0, $read)
    return $text -match '^HTTP/'
  } catch {
    return $false
  } finally {
    $client.Close()
  }
}

function Test-Socks5ProxyPort {
  param(
    [int]$Port,
    [int]$TimeoutMs = 800
  )

  $client = [System.Net.Sockets.TcpClient]::new()
  try {
    $iar = $client.BeginConnect("127.0.0.1", $Port, $null, $null)
    if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
      return $false
    }
    $client.EndConnect($iar)
    $client.ReceiveTimeout = $TimeoutMs
    $client.SendTimeout = $TimeoutMs
    $stream = $client.GetStream()
    $probe = [byte[]](0x05, 0x01, 0x00)
    $stream.Write($probe, 0, $probe.Length)
    $buffer = New-Object byte[] 2
    $read = $stream.Read($buffer, 0, $buffer.Length)
    return ($read -ge 2 -and $buffer[0] -eq 0x05)
  } catch {
    return $false
  } finally {
    $client.Close()
  }
}

function Normalize-ProxyUrl {
  param([string]$Value)

  if ([string]::IsNullOrWhiteSpace($Value)) {
    return $null
  }

  $candidate = $Value.Trim()
  if ($candidate -match '^(?<scheme>https?|socks5h?|socks)://') {
    if ($candidate.StartsWith("socks://")) {
      return "socks5h://" + $candidate.Substring("socks://".Length)
    }
    return $candidate.TrimEnd("/")
  }

  if ($candidate -match '^[^:=\s]+:\d+$') {
    return "http://$candidate"
  }

  return $null
}

function Get-ProxyUrlsFromWindowsSettings {
  $results = New-Object System.Collections.Generic.List[string]

  try {
    $systemProxy = [System.Net.WebRequest]::GetSystemWebProxy()
    $target = [Uri]"https://chatgpt.com/"
    $proxyUri = $systemProxy.GetProxy($target)
    if ($proxyUri -and $proxyUri.AbsoluteUri -ne $target.AbsoluteUri) {
      $normalized = Normalize-ProxyUrl $proxyUri.AbsoluteUri
      if ($normalized) {
        $results.Add($normalized)
      }
    }
  } catch {
  }

  try {
    $settings = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -ErrorAction SilentlyContinue
    if ($settings.ProxyEnable -eq 1 -and -not [string]::IsNullOrWhiteSpace($settings.ProxyServer)) {
      $proxyServer = [string]$settings.ProxyServer
      if ($proxyServer.Contains("=")) {
        $map = @{}
        foreach ($part in $proxyServer.Split(";")) {
          $kv = $part.Split("=", 2)
          if ($kv.Count -eq 2) {
            $map[$kv[0].ToLowerInvariant()] = $kv[1]
          }
        }
        foreach ($key in @("https", "http", "socks")) {
          if ($map.ContainsKey($key)) {
            $value = $map[$key]
            if ($key -eq "socks" -and $value -notmatch '^[a-z]+://') {
              $value = "socks5h://$value"
            }
            $normalized = Normalize-ProxyUrl $value
            if ($normalized) {
              $results.Add($normalized)
            }
          }
        }
      } else {
        $normalized = Normalize-ProxyUrl $proxyServer
        if ($normalized) {
          $results.Add($normalized)
        }
      }
    }
  } catch {
  }

  return $results | Select-Object -Unique
}

function Resolve-ProxyUrl {
  param([string]$ExplicitProxyUrl)

  $explicit = Normalize-ProxyUrl $ExplicitProxyUrl
  if ($explicit) {
    return [pscustomobject]@{ Url = $explicit; Source = "explicit -ProxyUrl" }
  }

  foreach ($name in @("HTTPS_PROXY", "HTTP_PROXY", "ALL_PROXY", "https_proxy", "http_proxy", "all_proxy")) {
    $value = [Environment]::GetEnvironmentVariable($name)
    $normalized = Normalize-ProxyUrl $value
    if ($normalized) {
      return [pscustomobject]@{ Url = $normalized; Source = "environment variable $name" }
    }
  }

  foreach ($url in Get-ProxyUrlsFromWindowsSettings) {
    return [pscustomobject]@{ Url = $url; Source = "Windows proxy settings" }
  }

  $candidates = @(10808, 10809, 7890, 7897, 7891, 2080, 2081, 1080, 1087, 8080, 20170, 20171)
  foreach ($port in $candidates) {
    if (Test-HttpProxyPort -Port $port) {
      return [pscustomobject]@{ Url = "http://127.0.0.1:$port"; Source = "auto-detected local HTTP/mixed proxy port $port" }
    }
  }

  foreach ($port in $candidates) {
    if (Test-Socks5ProxyPort -Port $port) {
      return [pscustomobject]@{ Url = "socks5h://127.0.0.1:$port"; Source = "auto-detected local SOCKS5 proxy port $port" }
    }
  }

  throw "No usable local proxy was detected. Start your proxy client or pass -ProxyUrl, for example -ProxyUrl http://127.0.0.1:7890"
}

function Find-CodexApp {
  $packages = Get-AppxPackage -Name "OpenAI.Codex" -ErrorAction SilentlyContinue |
    Sort-Object Version -Descending

  foreach ($pkg in $packages) {
    $candidate = Join-Path $pkg.InstallLocation "app\Codex.exe"
    if (Test-Path -LiteralPath $candidate) {
      return $candidate
    }
  }

  $cmd = Get-Command "codex.exe" -ErrorAction SilentlyContinue
  if ($cmd -and $cmd.Source) {
    $appDir = Split-Path -Parent (Split-Path -Parent $cmd.Source)
    $candidate = Join-Path $appDir "Codex.exe"
    if (Test-Path -LiteralPath $candidate) {
      return $candidate
    }
  }

  throw "Codex.exe was not found. Launch Codex once from the Start menu, then run this script again."
}

$resolvedProxy = Resolve-ProxyUrl -ExplicitProxyUrl $ProxyUrl
$ProxyUrl = $resolvedProxy.Url

$codexApp = Find-CodexApp
$installDir = Join-Path $env:LOCALAPPDATA "CodexProxyLauncher"
New-Item -ItemType Directory -Force -Path $installDir | Out-Null

$launcherPath = Join-Path $installDir "Start-Codex-with-proxy.ps1"
$launcher = @'
param(
  [string]$ProxyUrl = "__PROXY_URL__",
  [string]$NoProxy = "__NO_PROXY__",
  [switch]$ForceRestart
)

$ErrorActionPreference = "Stop"

function Find-CodexApp {
  $packages = Get-AppxPackage -Name "OpenAI.Codex" -ErrorAction SilentlyContinue |
    Sort-Object Version -Descending

  foreach ($pkg in $packages) {
    $candidate = Join-Path $pkg.InstallLocation "app\Codex.exe"
    if (Test-Path -LiteralPath $candidate) {
      return $candidate
    }
  }

  $cmd = Get-Command "codex.exe" -ErrorAction SilentlyContinue
  if ($cmd -and $cmd.Source) {
    $appDir = Split-Path -Parent (Split-Path -Parent $cmd.Source)
    $candidate = Join-Path $appDir "Codex.exe"
    if (Test-Path -LiteralPath $candidate) {
      return $candidate
    }
  }

  throw "Codex.exe was not found. Launch Codex once from the Start menu, then run this launcher again."
}

$running = Get-Process -ErrorAction SilentlyContinue |
  Where-Object { $_.ProcessName -in @("Codex", "codex") }

if ($running -and -not $ForceRestart) {
  Write-Host "Codex is already running. Quit Codex completely, then run this launcher again."
  Write-Host "Or run with -ForceRestart to close existing Codex processes first."
  Read-Host "Press Enter to close"
  exit 1
}

if ($running -and $ForceRestart) {
  $running | Stop-Process -Force
  Start-Sleep -Seconds 2
}

$codexApp = Find-CodexApp

$env:HTTP_PROXY = $ProxyUrl
$env:HTTPS_PROXY = $ProxyUrl
$env:ALL_PROXY = $ProxyUrl
$env:NO_PROXY = $NoProxy

Write-Host "Starting Codex with proxy: $ProxyUrl"
Start-Process -FilePath $codexApp -WorkingDirectory (Split-Path -Parent $codexApp)
'@

$launcher = $launcher.Replace("__PROXY_URL__", $ProxyUrl.Replace("'", "''"))
$launcher = $launcher.Replace("__NO_PROXY__", $NoProxy.Replace("'", "''"))
Set-Content -LiteralPath $launcherPath -Value $launcher -Encoding UTF8

if (-not $NoDesktopShortcut) {
  $desktop = [Environment]::GetFolderPath("Desktop")
  $shortcutPath = Join-Path $desktop ($ShortcutName + ".lnk")

  $wsh = New-Object -ComObject WScript.Shell
  $shortcut = $wsh.CreateShortcut($shortcutPath)
  $shortcut.TargetPath = "powershell.exe"
  $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$launcherPath`""
  if ($ForceRestart) {
    $shortcut.Arguments = $shortcut.Arguments + " -ForceRestart"
  }
  $shortcut.WorkingDirectory = $installDir
  $shortcut.IconLocation = "$codexApp,0"
  $shortcut.Description = "Start Codex with a proxy only for the Codex process"
  $shortcut.Save()

  Write-Host "Created shortcut: $shortcutPath"
}

Write-Host "Installed launcher: $launcherPath"
Write-Host "Proxy URL: $ProxyUrl"
Write-Host "Proxy source: $($resolvedProxy.Source)"
Write-Host "Quit Codex completely before using the generated shortcut."
