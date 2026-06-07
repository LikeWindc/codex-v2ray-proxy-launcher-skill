param(
  [string]$ProxyUrl = "",
  [string]$ShortcutName = "Codex - v2ray Proxy Launcher",
  [switch]$ForceRestart,
  [switch]$NoDesktopShortcut
)

$ErrorActionPreference = "Stop"

function Test-LocalPort {
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

function Get-DefaultProxyUrl {
  $candidates = @(10808, 10809, 7890, 7891, 1080, 1087, 8080)
  foreach ($port in $candidates) {
    if (Test-LocalPort -HostName "127.0.0.1" -Port $port) {
      return "http://127.0.0.1:$port"
    }
  }
  throw "No local v2ray proxy port was detected. Start v2rayN or pass -ProxyUrl, for example -ProxyUrl http://127.0.0.1:10808"
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

if ([string]::IsNullOrWhiteSpace($ProxyUrl)) {
  $ProxyUrl = Get-DefaultProxyUrl
}

$codexApp = Find-CodexApp
$installDir = Join-Path $env:LOCALAPPDATA "CodexV2rayProxyLauncher"
New-Item -ItemType Directory -Force -Path $installDir | Out-Null

$launcherPath = Join-Path $installDir "Start-Codex-v2ray.ps1"
$launcher = @'
param(
  [string]$ProxyUrl = "__PROXY_URL__",
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
$env:NO_PROXY = "localhost,127.0.0.1,::1"

Write-Host "Starting Codex with proxy: $ProxyUrl"
Start-Process -FilePath $codexApp -WorkingDirectory (Split-Path -Parent $codexApp)
'@

$launcher = $launcher.Replace("__PROXY_URL__", $ProxyUrl.Replace("'", "''"))
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
  $shortcut.Description = "Start Codex with a v2ray proxy only for the Codex process"
  $shortcut.Save()

  Write-Host "Created shortcut: $shortcutPath"
}

Write-Host "Installed launcher: $launcherPath"
Write-Host "Proxy URL: $ProxyUrl"
Write-Host "Quit Codex completely before using the generated shortcut."
