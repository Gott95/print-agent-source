@echo off
setlocal

REM Instalador amigable (doble click) para usuarios no técnicos.
REM Eleva a Administrador y ejecuta el script PowerShell de instalación del servicio.

cd /d "%~dp0"

REM Auto-elevate
net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Solicitando permisos de administrador...
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%COMSPEC%' -ArgumentList '/c', '"'%~f0'"'' -Verb RunAs"
  exit /b
)

echo Instalando Print Agent como servicio...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-print-agent-service.ps1"

echo.
echo Listo. Puedes cerrar esta ventana.
pause
