# Genera un ZIP listo para GitHub Releases (Windows Service bundle).
# Salida: .\dist\PrintAgent-Service-Windows-v<version>.zip
# Requiere: Node.js + npm. (pkg viene en devDependencies)
# Compatible con Windows PowerShell 5.1.

# PSScriptAnalyzer suele marcar falsos positivos en scripts internos; desactivamos verbos.
# PSScriptAnalyzer -DisableRule PSUseApprovedVerbs

$ErrorActionPreference = 'Stop'

function New-Dir([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Get-PackageVersion([string]$PackageJsonPath) {
    $json = Get-Content -LiteralPath $PackageJsonPath -Raw | ConvertFrom-Json
    if (-not $json.version) { throw 'No se pudo leer version desde package.json' }
    return ($json.version.ToString()).Trim()
}

function Invoke-WebDownload([string]$Url, [string]$OutFile) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
}

$Root = $PSScriptRoot
$DistRoot = Join-Path $Root 'dist'
$BundleDir = Join-Path $DistRoot 'PrintAgent-Service-Windows'

$PackageJson = Join-Path $Root 'package.json'
$Version = Get-PackageVersion $PackageJson

$AgentExe = Join-Path $Root 'print-agent.exe'
$WinSwLocal = Join-Path $Root 'WinSW-x64.exe'
$WinSwUrl = 'https://github.com/winsw/winsw/releases/latest/download/WinSW-x64.exe'

$ZipName = "PrintAgent-Service-Windows-v$Version.zip"
$ZipPath = Join-Path $DistRoot $ZipName

Write-Host "== Build bundle v$Version ==" -ForegroundColor Cyan

# 1) npm install (si hace falta)
if (-not (Test-Path -LiteralPath (Join-Path $Root 'node_modules'))) {
    Write-Host 'Instalando dependencias (npm install)...' -ForegroundColor Yellow
    Push-Location $Root
    try {
        npm install
    }
    finally {
        Pop-Location
    }
}

# 2) Compilar exe
Write-Host 'Compilando print-agent.exe (npm run build)...' -ForegroundColor Yellow
Push-Location $Root
try {
    npm run build
}
finally {
    Pop-Location
}

if (-not (Test-Path -LiteralPath $AgentExe)) {
    throw "No se genero print-agent.exe en: $AgentExe"
}

# 3) Obtener WinSW-x64.exe (para instalaciones offline)
if (-not (Test-Path -LiteralPath $WinSwLocal)) {
    Write-Host 'Descargando WinSW-x64.exe...' -ForegroundColor Yellow
    Invoke-WebDownload -Url $WinSwUrl -OutFile $WinSwLocal
}

# 4) Preparar bundle folder
if (Test-Path -LiteralPath $BundleDir) {
    Remove-Item -LiteralPath $BundleDir -Recurse -Force
}
New-Dir $BundleDir

# 5) Copiar artefactos
Copy-Item -LiteralPath $AgentExe -Destination (Join-Path $BundleDir 'print-agent.exe') -Force
Copy-Item -LiteralPath $WinSwLocal -Destination (Join-Path $BundleDir 'WinSW-x64.exe') -Force

Copy-Item -LiteralPath (Join-Path $Root 'INSTALL-SERVICE.cmd') -Destination $BundleDir -Force
Copy-Item -LiteralPath (Join-Path $Root 'UNINSTALL-SERVICE.cmd') -Destination $BundleDir -Force
Copy-Item -LiteralPath (Join-Path $Root 'install-print-agent-service.ps1') -Destination $BundleDir -Force
Copy-Item -LiteralPath (Join-Path $Root 'uninstall-print-agent-service.ps1') -Destination $BundleDir -Force

# README corto para usuarios finales
$QuickReadme = Join-Path $BundleDir 'README-Instalacion.txt'
@"
PRINT AGENT (Servicio Windows)

1) Click derecho: INSTALL-SERVICE.cmd -> Ejecutar como administrador.
2) Verifica en services.msc el servicio: PrintAgent.
3) Para desinstalar: UNINSTALL-SERVICE.cmd

Puerto por defecto: 18080
Logs: C:\ProgramData\PrintAgent\Service\logs\
"@ | Set-Content -LiteralPath $QuickReadme -Encoding UTF8

# 6) Crear ZIP
New-Dir $DistRoot
if (Test-Path -LiteralPath $ZipPath) {
    Remove-Item -LiteralPath $ZipPath -Force
}

Write-Host "Creando ZIP: $ZipPath" -ForegroundColor Yellow
Compress-Archive -Path (Join-Path $BundleDir '*') -DestinationPath $ZipPath -Force

Write-Host 'OK. Bundle generado.' -ForegroundColor Green
Write-Host $ZipPath -ForegroundColor Gray
