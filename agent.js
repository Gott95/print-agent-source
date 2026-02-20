const WebSocket = require("ws");
const net = require("net");
const path = require("path");
const fs = require("fs");

// CONFIGURACIÓN
const AGENT_VERSION = "1.0.0";

function isPackaged() {
  return Boolean(process.pkg);
}

function parsePort(value) {
  const num = Number(value);
  if (!Number.isInteger(num)) return null;
  if (num < 1 || num > 65535) return null;
  return num;
}

function getPortFromArgs() {
  const args = process.argv.slice(2);

  const eqArg = args.find((a) => a.startsWith("--port="));
  if (eqArg) {
    const [, portValue] = eqArg.split("=");
    return parsePort(portValue);
  }

  const idx = args.indexOf("--port");
  if (idx >= 0 && args[idx + 1]) {
    return parsePort(args[idx + 1]);
  }

  return null;
}

const WS_PORT =
  getPortFromArgs() ?? parsePort(process.env.PRINT_AGENT_PORT) ?? 18080;

const WS_HOST = process.env.PRINT_AGENT_HOST || "0.0.0.0";

function getLogDir() {
  const envDir = (process.env.PRINT_AGENT_LOG_DIR || "").trim();
  if (envDir) return envDir;

  // Prefer ProgramData on Windows.
  const programData = (process.env.ProgramData || "").trim();
  if (programData) return path.join(programData, "PrintAgent");

  // When packaged, cwd can be System32; use executable folder.
  if (isPackaged()) return path.join(path.dirname(process.execPath), "logs");

  return path.join(process.cwd(), "PrintAgent");
}

// Logging simple en archivo (para debug sin consola)
const logFile = path.join(getLogDir(), "agent.log");

function log(msg) {
  const timestamp = new Date().toISOString();
  const entry = `[${timestamp}] ${msg}\n`;
  // Intentar escribir en log, si falla (permisos), solo consola
  try {
    const dir = path.dirname(logFile);
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    fs.appendFileSync(logFile, entry);
  } catch (e) {}
  console.log(entry.trim());
}

// INICIO DEL SERVIDOR
let wss;
try {
  wss = new WebSocket.Server({ port: WS_PORT, host: WS_HOST });
} catch (e) {
  const msg =
    e && e.code === "EADDRINUSE"
      ? `ERROR: El puerto ${WS_PORT} ya está en uso.`
      : `ERROR: No se pudo iniciar el servidor WebSocket: ${e && e.message ? e.message : String(e)}`;
  log(msg);
  process.exit(1);
}

log(
  `Print Agent v${AGENT_VERSION} iniciado en ws://${WS_HOST}:${WS_PORT} (pid=${process.pid}, packaged=${isPackaged()})`,
);

// Si el puerto se ocupa después de iniciar, ws lo reporta por eventos.
if (wss && wss.on) {
  wss.on("error", (err) => {
    if (err && err.code === "EADDRINUSE") {
      log(`ERROR: El puerto ${WS_PORT} ya está en uso.`);
    } else {
      log(
        `ERROR: WebSocket server: ${err && err.message ? err.message : String(err)}`,
      );
    }
  });
}

wss.on("connection", (ws, req) => {
  const clientIp = req.socket.remoteAddress;
  log(`Cliente conectado desde: ${clientIp}`);

  ws.on("message", (message) => {
    try {
      const payload = JSON.parse(message);
      // Esperamos: { ip: "192.168.1.50", data: "...", port?: 9100 }

      if (!payload.ip || !payload.data) {
        ws.send(
          JSON.stringify({ status: "error", msg: "Faltan datos (IP o Data)" }),
        );
        return;
      }

      // Backward-compatible: si no viene puerto, usa 9100.
      const printerPort =
        parsePort(payload.port) ??
        parsePort(payload.printerPort) ??
        parsePort(payload.puerto) ??
        9100;

      printToNetworkPrinter(payload.ip, payload.data, printerPort, ws);
    } catch (e) {
      log(`Error procesando mensaje: ${e.message}`);
      ws.send(JSON.stringify({ status: "error", msg: "JSON Inválido" }));
    }
  });

  ws.on("error", (err) => log(`Error WebSocket: ${err.message}`));
});

function printToNetworkPrinter(ip, data, printerPort, wsClient) {
  const client = new net.Socket();
  const PRINTER_PORT = printerPort || 9100; // Default: 9100

  // Timeout de 5 segundos para no colgar el proceso si la IP no existe
  client.setTimeout(5000);

  client.connect(PRINTER_PORT, ip, () => {
    log(`Enviando datos a ${ip}:${PRINTER_PORT}`);
    // 'latin1' preserva valores 0-255 para ESC/POS cuando data viene como string.
    client.write(Buffer.from(data, "latin1"));
    client.end();
    wsClient.send(
      JSON.stringify({ status: "success", msg: "Enviado a impresora" }),
    );
  });

  client.on("timeout", () => {
    log(`Timeout conectando a ${ip}:${PRINTER_PORT}`);
    client.destroy();
    wsClient.send(
      JSON.stringify({
        status: "error",
        msg: "Impresora no responde (Timeout)",
      }),
    );
  });

  client.on("error", (err) => {
    log(`Error TCP ${ip}:${PRINTER_PORT}: ${err.message}`);
    wsClient.send(JSON.stringify({ status: "error", msg: err.message }));
  });
}

function shutdown(signal) {
  try {
    log(`Cerrando agente (${signal})...`);
  } catch {}

  try {
    wss && wss.close(() => process.exit(0));
    // Si no hay callback (por cualquier razón), salir igual.
    setTimeout(() => process.exit(0), 1000).unref();
  } catch (e) {
    process.exit(0);
  }
}

process.on("SIGINT", () => shutdown("SIGINT"));
process.on("SIGTERM", () => shutdown("SIGTERM"));
