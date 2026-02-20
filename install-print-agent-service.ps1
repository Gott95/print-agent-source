# Instala Print Agent como servicio de Windows usando WinSW.
# Requiere ejecutar PowerShell como Administrador.
#
# Qué hace:
# - Copia print-agent.exe a C:\ProgramData\PrintAgent\Service
# - Descarga WinSW-x64.exe y lo renombra a PrintAgentService.exe
# - Genera PrintAgentService.xml
# - Instala e inicia el servicio

$ErrorActionPreference = 'Stop'

function Assert-Admin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Ejecuta este script como Administrador (Run as Administrator).'
    }
}

function New-DirectoryIfMissing([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Write-ServiceXml([string]$XmlPath, [int]$Port) {
    $xml = @"
<service>
  <id>PrintAgent</id>
  <name>Print Agent</name>
  <description>Agente de impresion (WebSocket -> TCP 9100) para comandas ESC/POS.</description>
    <startmode>Automatic</startmode>
    <workingdirectory>%BASE%</workingdirectory>
  <executable>%BASE%\\print-agent.exe</executable>
  <arguments>--port $Port</arguments>
  <logpath>%BASE%\\logs</logpath>
  <log mode="roll-by-size">
    <sizeThreshold>10240</sizeThreshold>
    <keepFiles>8</keepFiles>
  </log>
  <onfailure action="restart" delay="5 sec" />
  <stoptimeout>10 sec</stoptimeout>
</service>
"@

    Set-Content -LiteralPath $XmlPath -Value $xml -Encoding UTF8
}

function Add-FirewallRuleIfMissing([int]$Port) {
    try {
        $ruleName = 'PrintAgent WebSocket'
        $existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
        if (-not $existing) {
            New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -LocalPort $Port -Protocol TCP -Action Allow | Out-Null
        }
    }
    catch {
        # Si falla (por política), no bloquear instalación del servicio.
    }
}

Assert-Admin

$Port = 18080
$InstallRoot = Join-Path $env:ProgramData 'PrintAgent'
$InstallDir = Join-Path $InstallRoot 'Service'

$WrapperExe = Join-Path $InstallDir 'PrintAgentService.exe'
$WrapperXml = Join-Path $InstallDir 'PrintAgentService.xml'
$AgentExe = Join-Path $InstallDir 'print-agent.exe'

$SourceAgentExe = Join-Path $PSScriptRoot 'print-agent.exe'

Write-Host "== PrintAgent: instalar como servicio ==" -ForegroundColor Cyan
Write-Host "Destino: $InstallDir" -ForegroundColor Gray

New-DirectoryIfMissing $InstallDir

if (-not (Test-Path -LiteralPath $SourceAgentExe)) {
    throw "No se encontro print-agent.exe en: $SourceAgentExe`nCompila primero con: npm install; npm run build"
}

# 1) Copiar agente
Copy-Item -LiteralPath $SourceAgentExe -Destination $AgentExe -Force

# 2) Obtener WinSW (preferir local para instalaciones offline)
$LocalWinSw = Join-Path $PSScriptRoot 'WinSW-x64.exe'
if (Test-Path -LiteralPath $LocalWinSw) {
    Write-Host "Usando WinSW local: $LocalWinSw" -ForegroundColor Yellow
    Copy-Item -LiteralPath $LocalWinSw -Destination $WrapperExe -Force
}
else {
    $winswUrl = 'https://github.com/winsw/winsw/releases/latest/download/WinSW-x64.exe'
    Write-Host "Descargando WinSW..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $winswUrl -OutFile $WrapperExe -UseBasicParsing
}

# 3) Generar XML
Write-Host "Generando configuracion de servicio..." -ForegroundColor Yellow
Write-ServiceXml -XmlPath $WrapperXml -Port $Port

# 3.1) Si el puerto está ocupado, solo detener si el proceso parece ser print-agent.
try {
    $conn = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($conn) {
        $owningPid = [int]$conn.OwningProcess
        $p = Get-Process -Id $owningPid -ErrorAction SilentlyContinue
        $pname = ''
        if ($p -and $p.Name) {
            $pname = $p.Name.ToString()
        }

        if ($pname -and $pname.ToLower().StartsWith('print-agent')) {
            Write-Host "Puerto $Port en uso por $pname (pid=$owningPid). Deteniendo..." -ForegroundColor Yellow
            Stop-Process -Id $owningPid -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 400
        }
        else {
            throw "El puerto $Port ya está en uso por PID=$owningPid ($pname). Libera el puerto o cambia el puerto en el XML antes de instalar."
        }
    }
}
catch {
    throw
}

# 4) Firewall (best-effort)
Add-FirewallRuleIfMissing -Port $Port

# 5) Instalar/Iniciar servicio
Write-Host "Instalando servicio..." -ForegroundColor Yellow
& $WrapperExe install

Write-Host "Iniciando servicio..." -ForegroundColor Yellow
& $WrapperExe start

Write-Host "OK. Servicio instalado e iniciado." -ForegroundColor Green
Write-Host "Verifica estado con: sc.exe query PrintAgent" -ForegroundColor Gray
Write-Host "Verifica puerto con: netstat -ano | findstr :$Port" -ForegroundColor Gray
