# --- CONFIGURACIÓN FINAL ---
$UrlDescarga = "https://github.com/Gott95/print-agent-source/releases/download/v1.0.0/print-agent.zip"
# ---------------------------

$NombreApp = "PrintAgent"
$DirDestino = "C:\ProgramData\$NombreApp"
$NombreExe = "print-agent.exe"
$RutaZip = "$DirDestino\paquete.zip"
$RutaExeFinal = "$DirDestino\$NombreExe"

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
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $UrlDescarga -OutFile $RutaZip
    Write-Host "      Descarga completada." -ForegroundColor Green
}
catch {
    Write-Error "Error fatal descargando el archivo."
    Write-Host "Detalle: $_" -ForegroundColor Red
    Pause
    Exit
}

# 4. Descomprimir e Instalar
Write-Host "[4/6] Instalando..." -ForegroundColor Yellow
try {
    # Descomprimir
    Expand-Archive -LiteralPath $RutaZip -DestinationPath $DirDestino -Force
    Remove-Item -Path $RutaZip -Force # Borrar zip

    # CORRECCIÓN DE ERRORES DE COMPRESIÓN:
    # Si al descomprimir quedó en una subcarpeta (ej: PrintAgent/print-agent.exe), lo movemos a la raíz.
    if (!(Test-Path $RutaExeFinal)) {
        $PosibleSubcarpeta = Get-ChildItem -Path $DirDestino -Filter "$NombreExe" -Recurse | Select-Object -First 1
        if ($PosibleSubcarpeta) {
            Move-Item -Path $PosibleSubcarpeta.FullName -Destination $RutaExeFinal -Force
            Write-Host "      Archivo movido desde subcarpeta." -ForegroundColor Gray
        }
    }
}
catch {
    Write-Error "Error al descomprimir."
    Pause
    Exit
}

# Verificar que el exe existe antes de seguir
if (!(Test-Path $RutaExeFinal)) {
    Write-Error "ERROR CRÍTICO: No se encontró '$NombreExe' después de descomprimir."
    Write-Host "El archivo ZIP parece estar vacío o dañado." -ForegroundColor Red
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
try {
    New-NetFirewallRule -DisplayName "PrintAgent Server" -Direction Inbound -LocalPort 8080 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
} catch {}

Start-Process -FilePath $RutaExeFinal -WindowStyle Hidden

Write-Host " "
Write-Host "✅ INSTALACIÓN COMPLETADA CON ÉXITO" -ForegroundColor Green
Write-Host "El agente ya está corriendo en segundo plano."
Write-Host "Puede cerrar esta ventana."
Start-Sleep -Seconds 5