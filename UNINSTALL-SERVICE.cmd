@echo off
setlocal

REM Desinstalador amigable (doble click).
REM Eleva a Administrador y ejecuta el script PowerShell de desinstalación.

cd /d "%~dp0"

REM Auto-elevate
net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Solicitando permisos de administrador...
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%COMSPEC%' -ArgumentList '/c', '"'%~f0'"'' -Verb RunAs"
  exit /b
)

echo Desinstalando Print Agent (servicio)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall-print-agent-service.ps1"

echo.
echo Listo. Puedes cerrar esta ventana.
pause
