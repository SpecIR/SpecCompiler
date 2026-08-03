# SpecCompiler — Windows wrapper (container mode via Docker Desktop or Podman).
# Installed by scripts/install.ps1 next to a specc.cmd shim, so `specc` works
# from both cmd and PowerShell without execution-policy changes.
# Config: %APPDATA%\speccompiler\env.ps1 (environment variables win over it).
$ErrorActionPreference = 'Stop'

$configFile = Join-Path $env:APPDATA 'speccompiler\env.ps1'
if (Test-Path $configFile) { . $configFile }

function Show-Usage {
    Write-Host 'SpecCompiler' -ForegroundColor Cyan
    Write-Host ''
    Write-Host 'Usage: specc build [project.yaml]'
    Write-Host ''
    Write-Host '  Build the project (default: project.yaml)'
    Write-Host ''
    Write-Host 'Environment:'
    Write-Host '  SPECC_ENGINE              container engine (docker | podman)'
    Write-Host '  SPECCOMPILER_IMAGE        full image reference (highest priority)'
    Write-Host '  SPECCOMPILER_REPOSITORY   GitHub slug to resolve the GHCR image'
}

if (-not $args -or $args[0] -in @('-h', '--help', 'help')) { Show-Usage; exit 0 }
$rest = @($args)
if ($rest[0] -eq 'build') { $rest = @($rest | Select-Object -Skip 1) }
$project = if ($rest.Count -ge 1) { $rest[0] } else { 'project.yaml' }
if (-not (Test-Path $project)) {
    Write-Host "Error: $project not found" -ForegroundColor Red
    exit 1
}

# Pick a container engine: docker preferred, podman as fallback
$engine = $env:SPECC_ENGINE
if (-not $engine) {
    if (Get-Command docker -ErrorAction SilentlyContinue) { $engine = 'docker' }
    elseif (Get-Command podman -ErrorAction SilentlyContinue) { $engine = 'podman' }
    else {
        Write-Host 'Error: no container engine found' -ForegroundColor Red
        Write-Host 'Install Docker Desktop (https://docs.docker.com/get-docker/) or Podman (https://podman.io).'
        exit 1
    }
}
& $engine info *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: cannot connect to $engine" -ForegroundColor Red
    if ($engine -eq 'podman') {
        Write-Host 'Start the Podman VM first:'
        Write-Host '  podman machine init   (first time only)'
        Write-Host '  podman machine start'
    } else {
        Write-Host 'Start Docker Desktop and retry.'
    }
    exit 1
}

# Resolve the image
if ($env:SPECCOMPILER_IMAGE) { $image = $env:SPECCOMPILER_IMAGE }
elseif ($env:SPECCOMPILER_REPOSITORY) { $image = "ghcr.io/$($env:SPECCOMPILER_REPOSITORY):latest" }
else { $image = 'ghcr.io/specir/speccompiler:latest' }

& $engine image inspect $image *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Image '$image' not found locally. Pulling..." -ForegroundColor Cyan
    & $engine pull $image
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: failed to pull image '$image'" -ForegroundColor Red
        exit 1
    }
}

# No -u uid:gid on Windows — the Docker Desktop / Podman machine VM owns the mount
$logLevel = if ($env:SPECCOMPILER_LOG_LEVEL) { $env:SPECCOMPILER_LOG_LEVEL } else { 'INFO' }
Write-Host 'Building project...' -ForegroundColor Cyan
& $engine run --rm `
    -v "${PWD}:/workspace" `
    -w /workspace `
    -e "SPECCOMPILER_LOG_LEVEL=$logLevel" `
    $image build $project
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host 'Build complete.' -ForegroundColor Green
