# SpecCompiler - Windows installer (container mode).
#
# One command in PowerShell (after Docker Desktop or Podman is installed):
#   irm https://raw.githubusercontent.com/specir/SpecCompiler/main/scripts/install.ps1 | iex
# Or from a local clone:
#   powershell -ExecutionPolicy Bypass -File scripts\install.ps1
#
# Installs specc.ps1 + a specc.cmd shim to %LOCALAPPDATA%\SpecCompiler\bin and
# adds it to the user PATH. The GHCR image is pulled lazily on first
# `specc build`.
$ErrorActionPreference = 'Stop'

$GithubRaw = 'https://raw.githubusercontent.com/specir/SpecCompiler/main'
$GhcrRepository = 'specir/speccompiler'
$BinDir = Join-Path $env:LOCALAPPDATA 'SpecCompiler\bin'
$ConfigDir = Join-Path $env:APPDATA 'speccompiler'

Write-Host '=== SpecCompiler Installer ===' -ForegroundColor Cyan

# Pick a container engine: docker preferred, podman as fallback
$engine = $null
if (Get-Command docker -ErrorAction SilentlyContinue) { $engine = 'docker' }
elseif (Get-Command podman -ErrorAction SilentlyContinue) { $engine = 'podman' }
else {
    Write-Host 'Error: no container engine found.' -ForegroundColor Red
    Write-Host 'Install Docker Desktop (https://docs.docker.com/get-docker/)'
    Write-Host 'or Podman (https://podman.io/docs/installation), then re-run this installer.'
    exit 1
}
Write-Host "Using container engine: $engine"

# [1/3] the wrapper + cmd shim
Write-Host '[1/3] Installing specc wrapper...'
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
$localSpecc = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'specc.ps1' } else { $null }
if ($localSpecc -and (Test-Path $localSpecc)) {
    Copy-Item $localSpecc (Join-Path $BinDir 'specc.ps1') -Force
} else {
    Invoke-WebRequest -UseBasicParsing "$GithubRaw/scripts/specc.ps1" -OutFile (Join-Path $BinDir 'specc.ps1')
}
"@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0specc.ps1`" %*" |
    Set-Content -Path (Join-Path $BinDir 'specc.cmd') -Encoding ASCII

# [2/3] config (environment variables win over this file)
Write-Host '[2/3] Writing config...'
New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
@"
# SpecCompiler config — dot-sourced by specc.ps1; environment wins.
if (-not `$env:SPECC_ENGINE) { `$env:SPECC_ENGINE = '$engine' }
if (-not `$env:SPECCOMPILER_IMAGE -and -not `$env:SPECCOMPILER_REPOSITORY) {
    `$env:SPECCOMPILER_REPOSITORY = '$GhcrRepository'
}
"@ | Set-Content -Path (Join-Path $ConfigDir 'env.ps1') -Encoding UTF8
Write-Host "  Using GHCR: ghcr.io/${GhcrRepository}:latest (pulled on first use)"

# [3/3] user PATH
Write-Host '[3/3] Checking PATH...'
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath -notlike "*$BinDir*") {
    [Environment]::SetEnvironmentVariable('Path', "$userPath;$BinDir", 'User')
    Write-Host "  Added $BinDir to your user PATH - open a NEW terminal to pick it up."
}

Write-Host ''
Write-Host '=== Installation Complete ===' -ForegroundColor Green
Write-Host 'Run: specc build [project.yaml]'
if ($engine -eq 'podman') {
    Write-Host 'Note: make sure the Podman VM is running (podman machine init; podman machine start).'
}
