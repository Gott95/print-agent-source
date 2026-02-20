# print-agent-source

## Protocolo WebSocket (formato de impresión)

El frontend se conecta al agente por WebSocket y envía un **JSON** por cada trabajo de impresión.

**URL (por defecto)**

- `ws://<host>:18080`

**Request (frontend → agente)**

Campos soportados:

- `ip` (string, requerido): IP/host de la impresora de red.
- `data` (string, requerido): contenido a imprimir (ESC/POS como string).
- `port` (number, opcional): puerto TCP de la impresora (default 9100).

Compatibilidad: el agente también acepta `printerPort` o `puerto` como alias de `port`.

Ejemplo:

```json
{
  "ip": "192.168.1.50",
  "port": 9100,
  "data": "TEXTO\n"
}
```

**Encoding de `data`**

- El agente escribe `data` al socket TCP usando `latin1` (bytes 0–255), para preservar bytes típicos de ESC/POS.

**Response (agente → frontend)**

El agente responde con JSON:

```json
{ "status": "success", "msg": "Enviado a impresora" }
```

o en error:

```json
{ "status": "error", "msg": "Impresora no responde (Timeout)" }
```

**Dónde está implementado**

- Lado agente (server WS + parse de payload): [agent.js](agent.js)
- Lado frontend (tipos y envío del payload): [FrontEasyWeb/src/app/shared/services/printer.service.ts](../FrontEasyWeb/src/app/shared/services/printer.service.ts)

## Instalación como servicio (Windows, recomendado para usuarios no técnicos)

En la carpeta del agente tienes instaladores por doble click:

- Ejecuta `INSTALL-SERVICE.cmd` (click derecho → **Ejecutar como administrador**).
- Para desinstalar: `UNINSTALL-SERVICE.cmd` (click derecho → **Ejecutar como administrador**)..

El servicio se instala como **PrintAgent** y escucha por defecto en **18080**.

Verificación rápida:

- Abrir `services.msc` y buscar **Print Agent** / **PrintAgent**.
- `sc.exe query PrintAgent`
- `netstat -ano | findstr :18080`

Logs del servicio (WinSW): `C:\ProgramData\PrintAgent\Service\logs\`

## Crear ZIP para GitHub Releases (bundle offline)

Genera un ZIP listo para compartir con usuarios finales (incluye `print-agent.exe`, WinSW y los instaladores por doble click):

```powershell
powershell -ExecutionPolicy Bypass -File .\build-release-zip.ps1
```

Salida: `dist\PrintAgent-Service-Windows-v<version>.zip`

## Smoke test (sin impresora)

Ejecuta un test de consola que:

- levanta 2 impresoras falsas (mock TCP) en `127.0.0.1:9100` y `127.0.0.1:9101`
- levanta el agente en WebSocket (`127.0.0.1:18082`)
- envía 2 jobs (con `port` y sin `port`) y valida que se enviaron bytes

Comandos:

```bash
npm install
npm run smoke:test
```
