# --- CONFIGURACIÓN FINAL ---
# Repo privado: el instalador soporta token por variable de entorno.
# - Preferido: definir $env:GITHUB_TOKEN antes de ejecutar.
# - Alternativas: $env:GH_TOKEN o $env:GITHUB_PAT
#
# Para repos privados, la descarga más confiable es vía API de GitHub (usa el token).
# Si no hay token o la API falla, intenta el URL directo.
$GitHubOwner = 'Gott95'
$GitHubRepo = 'print-agent-source'
$ReleaseTag = 'v1.0.0'
$AssetName = 'print-agent.zip'
$UrlDescarga = "https://github.com/$GitHubOwner/$GitHubRepo/releases/download/$ReleaseTag/$AssetName"

$Port = 18080
# ---------------------------

$NombreApp = "PrintAgent"
$DirDestino = "C:\ProgramData\$NombreApp"
$NombreExe = "print-agent.exe"
$TempBase = Join-Path $env:TEMP "${NombreApp}-installer"
$null = New-Item -ItemType Directory -Path $TempBase -Force -ErrorAction SilentlyContinue
$RutaZip = Join-Path $TempBase "paquete.zip"
$DirExtract = Join-Path $TempBase "extract"
$RutaExeFinal = "$DirDestino\$NombreExe"

$RutaAgentJsLocal = Join-Path $PSScriptRoot 'agent.js'
$RutaAgentJsFinal = Join-Path $DirDestino 'agent.js'

function Get-GitHubToken() {
    $t = $env:GITHUB_TOKEN
    if (-not $t) { $t = $env:GH_TOKEN }
    if (-not $t) { $t = $env:GITHUB_PAT }
    if (-not $t) { return $null }
    $t = $t.Trim()
    if ($t.Length -gt 0) {
        return $t
    }
    return $null
}

function Get-GitHubHeaders([string]$Token, [string]$Accept = 'application/vnd.github+json') {
    $h = @{
        'User-Agent' = 'PrintAgentInstaller'
        'Accept'     = $Accept
    }
    if ($Token) {
        # Bearer funciona para fine-grained y classic tokens
        $h['Authorization'] = "Bearer $Token"
    }
    return $h
}

function Download-GitHubReleaseAsset([string]$Owner, [string]$Repo, [string]$Tag, [string]$Asset, [string]$OutFile) {
    $token = Get-GitHubToken
    if (-not $token) {
        return $false
    }

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $releaseUrl = "https://api.github.com/repos/$Owner/$Repo/releases/tags/$Tag"
        $release = Invoke-RestMethod -Uri $releaseUrl -Headers (Get-GitHubHeaders -Token $token) -ErrorAction Stop

        $assetObj = $null
        foreach ($a in $release.assets) {
            if ($a.name -eq $Asset) { $assetObj = $a; break }
        }
        if (-not $assetObj) {
            throw "No se encontró el asset '$Asset' en el release '$Tag'."
        }

        $assetId = $assetObj.id
        $downloadUrl = "https://api.github.com/repos/$Owner/$Repo/releases/assets/$assetId"
        Invoke-WebRequest -Uri $downloadUrl -Headers (Get-GitHubHeaders -Token $token -Accept 'application/octet-stream') -OutFile $OutFile -ErrorAction Stop
        return $true
    }
    catch {
        Write-Host "      Descarga vía API falló (token)." -ForegroundColor Yellow
        Write-Host "      Detalle: $($_.Exception.Message)" -ForegroundColor DarkYellow
        return $false
    }
}

function Get-NodePath() {
    try {
        $cmd = Get-Command node -ErrorAction Stop
        return $cmd.Source
    }
    catch {
        return $null
    }
}

function Install-FromLocalNode([int]$PortValue) {
    Write-Host "      Instalando desde agent.js local (Node)..." -ForegroundColor Yellow

    if (!(Test-Path $RutaAgentJsLocal)) {
        Write-Error "No se encontró agent.js en la carpeta del instalador: $RutaAgentJsLocal"
        Pause
        Exit
    }

    $NodePath = Get-NodePath
    if (-not $NodePath) {
        Write-Error "Node.js no está instalado o no está en PATH. Instale Node.js o corrija el URL de descarga."
        Pause
        Exit
    }

    Copy-Item -Path $RutaAgentJsLocal -Destination $RutaAgentJsFinal -Force

    # Crear acceso directo en inicio: PowerShell oculto ejecutando node agent.js --port=...
    $StartupPath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\ServicioImpresion.lnk"
    $WshShell = New-Object -comObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($StartupPath)
    $Shortcut.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $Shortcut.WindowStyle = 7 # Minimizado
    $Shortcut.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command \"& `\"$NodePath`\" `\"$RutaAgentJsFinal`\" --port=$PortValue\""
    $Shortcut.Save()

    # Firewall
    try {
        New-NetFirewallRule -DisplayName "PrintAgent Server" -Direction Inbound -LocalPort $PortValue -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
    }
    catch {}

    # Arrancar
    Start-Process -FilePath $NodePath -ArgumentList "`"$RutaAgentJsFinal`" --port=$PortValue" -WindowStyle Hidden

    Write-Host " "
    Write-Host "✅ INSTALACIÓN COMPLETADA (Node)" -ForegroundColor Green
    Write-Host "El agente ya está corriendo en segundo plano." -ForegroundColor Gray
    Write-Host "Puerto configurado: $PortValue" -ForegroundColor Gray
    Write-Host "En el módulo de impresoras configure el agente como: IP:$PortValue (ej: localhost:$PortValue)" -ForegroundColor Gray
    Write-Host "Puede cerrar esta ventana." -ForegroundColor Gray
    Start-Sleep -Seconds 5
    Exit
}

function Test-PortInUse([int]$p) {
    try {
        $c = Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction Stop
        return ($c | Measure-Object).Count -gt 0
    }
    catch {
        return $false
    }
}

# Limpiar pantalla y mostrar banner
Clear-Host
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "   INSTALADOR DE AGENTE DE IMPRESIÓN      " -ForegroundColor White
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " "

# 1. Preparar Entorno
Write-Host "[1/6] Preparando carpetas..." -ForegroundColor Yellow
if (!(Test-Path -Path $DirDestino)) {
    New-Item -ItemType Directory -Path $DirDestino -Force | Out-Null
}

# 2. Detener procesos antiguos
Write-Host "[2/6] Deteniendo servicios anteriores..." -ForegroundColor Yellow
$Proceso = Get-Process -Name "print-agent" -ErrorAction SilentlyContinue
if ($Proceso) {
    Stop-Process -Name "print-agent" -Force
}
Start-Sleep -Seconds 1

# 3. Descargar
Write-Host "[3/6] Descargando componentes desde GitHub..." -ForegroundColor Yellow
try {
    Write-Host "      URL: $UrlDescarga" -ForegroundColor DarkGray
    Write-Host "      ZIP destino: $RutaZip" -ForegroundColor DarkGray
    # 1) Intentar descarga vía API (repo privado) si hay token
    $downloaded = Download-GitHubReleaseAsset -Owner $GitHubOwner -Repo $GitHubRepo -Tag $ReleaseTag -Asset $AssetName -OutFile $RutaZip

    if (-not $downloaded) {
        # 2) Fallback: URL directo (funciona en repos públicos)
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $UrlDescarga -OutFile $RutaZip -MaximumRedirection 10 -ErrorAction Stop
    }

    Write-Host "      Descarga completada." -ForegroundColor Green
    try {
        $zipInfo = Get-Item -LiteralPath $RutaZip -ErrorAction Stop
        Write-Host "      Tamaño ZIP: $([Math]::Round($zipInfo.Length / 1MB, 2)) MB" -ForegroundColor DarkGray
    }
    catch {}
}
catch {
    Write-Host "      No se pudo descargar desde GitHub." -ForegroundColor Yellow
    Write-Host "      Detalle: $($_.Exception.Message)" -ForegroundColor DarkYellow

    # Fallback: instalar desde Node local
    if (Test-PortInUse $Port) {
        Write-Host "      El puerto $Port ya está en uso. Configurando el agente en 18080..." -ForegroundColor Yellow
        $Port = 18080
    }
    Install-FromLocalNode -PortValue $Port
}

# 4. Descomprimir e Instalar
Write-Host "[4/6] Instalando..." -ForegroundColor Yellow
try {
    if (Test-Path $DirExtract) {
        Remove-Item -Path $DirExtract -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $DirExtract -Force | Out-Null

    # Descomprimir
    Expand-Archive -LiteralPath $RutaZip -DestinationPath $DirExtract -Force
    Remove-Item -Path $RutaZip -Force # Borrar zip

    # CORRECCIÓN DE ERRORES DE COMPRESIÓN:
    # Si al descomprimir quedó en una subcarpeta (ej: PrintAgent/print-agent.exe), lo movemos a la raíz.
    $Encontrado = Get-ChildItem -Path $DirExtract -Filter "$NombreExe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($Encontrado) {
        Copy-Item -Path $Encontrado.FullName -Destination $RutaExeFinal -Force
        Write-Host "      EXE instalado en: $RutaExeFinal" -ForegroundColor Gray
    } else {
        Write-Error "ERROR CRÍTICO: No se encontró '$NombreExe' dentro del ZIP."
        Pause
        Exit
    }
}
catch {
    Write-Error "Error al descomprimir."
    Pause
    Exit
}

# 5. Configurar Inicio Automático
Write-Host "[5/6] Configurando inicio automático..." -ForegroundColor Yellow
$StartupPath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\ServicioImpresion.lnk"
$WshShell = New-Object -comObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut($StartupPath)
$Shortcut.TargetPath = $RutaExeFinal
$Shortcut.WindowStyle = 7 # Minimizado
$Shortcut.Save()

# 6. Firewall y Arranque
Write-Host "[6/6] Finalizando..." -ForegroundColor Yellow

# Evitar conflicto típico: el Gateway/Backend suele estar en 8080
if (Test-PortInUse $Port) {
    Write-Host "      El puerto $Port ya está en uso. Configurando el agente en 18080..." -ForegroundColor Yellow
    $Port = 18080
}

try {
    New-NetFirewallRule -DisplayName "PrintAgent Server" -Direction Inbound -LocalPort $Port -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
}
catch {}

# Persistir argumentos también en el acceso directo de inicio
try {
    $Shortcut.Arguments = "--port=$Port"
    $Shortcut.Save()
}
catch {}

Start-Process -FilePath $RutaExeFinal -ArgumentList "--port=$Port" -WindowStyle Hidden

Write-Host " "
Write-Host "✅ INSTALACIÓN COMPLETADA CON ÉXITO" -ForegroundColor Green
Write-Host "El agente ya está corriendo en segundo plano."
Write-Host "Puerto configurado: $Port" -ForegroundColor Gray
Write-Host "En el módulo de impresoras configure el agente como: IP:$Port (ej: localhost:$Port)" -ForegroundColor Gray
Write-Host "Puede cerrar esta ventana."
Start-Sleep -Seconds 5