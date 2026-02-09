const WebSocket = require('ws');
const net = require('net');
const path = require('path');
const fs = require('fs');

// CONFIGURACIÓN
const WS_PORT = 8080;
const AGENT_VERSION = "1.0.0";

// Logging simple en archivo (para debug sin consola)
const logFile = path.join(process.env.ProgramData || process.cwd(), 'PrintAgent', 'agent.log');

function log(msg) {
    const timestamp = new Date().toISOString();
    const entry = `[${timestamp}] ${msg}\n`;
    // Intentar escribir en log, si falla (permisos), solo consola
    try {
        if (!fs.existsSync(path.dirname(logFile))) fs.mkdirSync(path.dirname(logFile), { recursive: true });
        fs.appendFileSync(logFile, entry);
    } catch (e) {}
    console.log(entry.trim());
}

// INICIO DEL SERVIDOR
const wss = new WebSocket.Server({ port: WS_PORT, host: '0.0.0.0' });
log(`🚀 Agente de Impresión v${AGENT_VERSION} iniciado en puerto ${WS_PORT}`);

wss.on('connection', (ws, req) => {
    const clientIp = req.socket.remoteAddress;
    log(`✅ Cliente conectado desde: ${clientIp}`);

    ws.on('message', (message) => {
        try {
            const payload = JSON.parse(message);
            // Esperamos: { ip: "192.168.1.50", data: "TEXTO_O_HEX" }
            
            if (!payload.ip || !payload.data) {
                ws.send(JSON.stringify({ status: 'error', msg: 'Faltan datos (IP o Data)' }));
                return;
            }

            printToNetworkPrinter(payload.ip, payload.data, ws);

        } catch (e) {
            log(`❌ Error procesando mensaje: ${e.message}`);
            ws.send(JSON.stringify({ status: 'error', msg: 'JSON Inválido' }));
        }
    });

    ws.on('error', (err) => log(`⚠️ Error WebSocket: ${err.message}`));
});

function printToNetworkPrinter(ip, data, wsClient) {
    const client = new net.Socket();
    const PRINTER_PORT = 9100; // Estándar para impresoras térmicas/red

    // Timeout de 5 segundos para no colgar el proceso si la IP no existe
    client.setTimeout(5000);

    client.connect(PRINTER_PORT, ip, () => {
        log(`🖨️ Enviando datos a ${ip}`);
        client.write(Buffer.from(data, 'binary')); // Importante: Binary para caracteres especiales
        client.end();
        wsClient.send(JSON.stringify({ status: 'success', msg: 'Enviado a impresora' }));
    });

    client.on('timeout', () => {
        log(`⏰ Timeout conectando a ${ip}`);
        client.destroy();
        wsClient.send(JSON.stringify({ status: 'error', msg: 'Impresora no responde (Timeout)' }));
    });

    client.on('error', (err) => {
        log(`❌ Error TCP ${ip}: ${err.message}`);
        wsClient.send(JSON.stringify({ status: 'error', msg: err.message }));
    });
}