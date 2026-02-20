# Desinstala Print Agent como servicio de Windows (WinSW).
# Requiere ejecutar PowerShell como Administrador.

$ErrorActionPreference = 'Stop'

$ServiceName = 'PrintAgent'
$DefaultPort = 18080

function Assert-Admin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Ejecuta este script como Administrador (Run as Administrator).'
    }
}

Assert-Admin

$InstallDir = Join-Path (Join-Path $env:ProgramData 'PrintAgent') 'Service'
$WrapperExe = Join-Path $InstallDir 'PrintAgentService.exe'

Write-Host "== PrintAgent: desinstalar servicio ==" -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $WrapperExe)) {
    Write-Host "No se encontro el wrapper en: $WrapperExe" -ForegroundColor Yellow
    Write-Host "Intentando remover el servicio igual (sc.exe)..." -ForegroundColor Yellow
}

if (Test-Path -LiteralPath $WrapperExe) {
    try {
        Write-Host "Deteniendo servicio (WinSW)..." -ForegroundColor Yellow
        & $WrapperExe stop | Out-Null
    }
    catch {
        Write-Host "No se pudo detener via WinSW (continuando)..." -ForegroundColor DarkYellow
    }

    try {
        Write-Host "Desinstalando servicio (WinSW)..." -ForegroundColor Yellow
        & $WrapperExe uninstall | Out-Null
    }
    catch {
        Write-Host "No se pudo desinstalar via WinSW (continuando)..." -ForegroundColor DarkYellow
    }
}

# Verificación y fallback con sc.exe (WinSW puede fallar silenciosamente si el servicio está en un estado raro)
try {
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($svc) {
        if ($svc.Status -ne 'Stopped') {
            Write-Host "Deteniendo servicio ($ServiceName) via sc.exe..." -ForegroundColor Yellow
            sc.exe stop $ServiceName | Out-Null

            $deadline = (Get-Date).AddSeconds(15)
            do {
                Start-Sleep -Milliseconds 400
                $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
            } while ($svc -and $svc.Status -ne 'Stopped' -and (Get-Date) -lt $deadline)
        }

        Write-Host "Eliminando servicio ($ServiceName) via sc.exe..." -ForegroundColor Yellow
        sc.exe delete $ServiceName | Out-Null
        Start-Sleep -Milliseconds 400
    }
}
catch {
    # No bloquear por errores de permisos/servicios.
}

# Si quedó un proceso escuchando el puerto del agente, intentar cerrarlo (solo si parece ser nuestro agente)
try {
    $conn = Get-NetTCPConnection -LocalPort $DefaultPort -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($conn) {
        $owningPid = [int]$conn.OwningProcess
        $p = Get-Process -Id $owningPid -ErrorAction SilentlyContinue
        $pname = ''
        if ($p -and $p.Name) { $pname = $p.Name.ToString() }

        $looksLikeAgent = $false
        if ($pname) {
            $n = $pname.ToLower()
            if ($n.StartsWith('print-agent') -or $n.StartsWith('printagentservice') -or $n -eq 'winsw') {
                $looksLikeAgent = $true
            }
        }

        if ($looksLikeAgent) {
            Write-Host "Puerto $DefaultPort sigue en LISTEN (pid=$owningPid, $pname). Cerrando proceso..." -ForegroundColor Yellow
            Stop-Process -Id $owningPid -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 400
        }
        else {
            Write-Host "Advertencia: el puerto $DefaultPort está en uso por PID=$owningPid ($pname). No se cerró por seguridad." -ForegroundColor DarkYellow
        }
    }
}
catch {
    # Si Get-NetTCPConnection no está disponible o falla, ignorar.
}

Write-Host "Listo. Servicio removido." -ForegroundColor Green
Write-Host "Nota: los archivos quedan en $InstallDir (puedes borrarlos si deseas)." -ForegroundColor Gray

Write-Host "Verifica estado con: sc.exe query $ServiceName" -ForegroundColor Gray
Write-Host "Verifica puerto con: netstat -ano | findstr :$DefaultPort" -ForegroundColor Gray
