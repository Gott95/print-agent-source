const { spawn } = require("child_process");
const net = require("net");
const WebSocket = require("ws");

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function startMockPrinter(port) {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    const received = {
      port,
      connections: 0,
      bytes: 0,
      chunks: [],
    };

    server.on("connection", (socket) => {
      received.connections += 1;

      socket.on("data", (buf) => {
        received.bytes += buf.length;
        // Guardar una muestra pequeña para inspección
        if (received.chunks.length < 5) {
          received.chunks.push(buf);
        }
      });

      socket.on("error", () => {
        // ignore
      });
    });

    server.on("error", (err) => reject(err));

    server.listen(port, "127.0.0.1", () => {
      console.log(`[MOCK-PRINTER] listening on 127.0.0.1:${port}`);
      resolve({ server, received });
    });
  });
}

function stopServer(server) {
  return new Promise((resolve) => {
    if (!server) return resolve();
    try {
      server.close(() => resolve());
    } catch {
      resolve();
    }
  });
}

function startAgent(wsPort) {
  const child = spawn(process.execPath, ["agent.js", `--port=${wsPort}`], {
    stdio: ["ignore", "pipe", "pipe"],
    windowsHide: true,
  });

  child.stdout.on("data", (d) => process.stdout.write(`[AGENT] ${d}`));
  child.stderr.on("data", (d) => process.stderr.write(`[AGENT-ERR] ${d}`));

  return child;
}

function stopProcess(child) {
  return new Promise((resolve) => {
    if (!child) return resolve();
    let done = false;

    const finish = () => {
      if (done) return;
      done = true;
      resolve();
    };

    child.on("exit", finish);
    try {
      child.kill("SIGTERM");
    } catch {}
    setTimeout(() => {
      try {
        child.kill("SIGKILL");
      } catch {}
      finish();
    }, 1000).unref();
  });
}

function wsRequest(wsUrl, payload, timeoutMs = 2500) {
  return new Promise((resolve) => {
    const ws = new WebSocket(wsUrl);
    const timer = setTimeout(() => {
      try {
        ws.close();
      } catch {}
      resolve({ ok: false, response: { status: "error", msg: "timeout" } });
    }, timeoutMs);

    ws.on("open", () => {
      ws.send(JSON.stringify(payload));
    });

    ws.on("message", (data) => {
      clearTimeout(timer);
      let resp;
      try {
        resp = JSON.parse(data.toString());
      } catch {
        resp = { status: "error", msg: "invalid-json" };
      }
      try {
        ws.close();
      } catch {}
      resolve({ ok: resp && resp.status === "success", response: resp });
    });

    ws.on("error", (err) => {
      clearTimeout(timer);
      resolve({ ok: false, response: { status: "error", msg: err.message } });
    });
  });
}

(async () => {
  const WS_PORT = 18082;
  const WS_URL = `ws://127.0.0.1:${WS_PORT}`;

  let agent;
  let mock9100;
  let mock9101;

  try {
    console.log("=== PRINT-AGENT SMOKE TEST (NO PRINTER NEEDED) ===");

    // 1) Mock printers: 9100 (default) and 9101 (explicit)
    mock9100 = await startMockPrinter(9100);
    mock9101 = await startMockPrinter(9101);

    // 2) Start agent (node) on WS_PORT
    agent = startAgent(WS_PORT);
    await sleep(400);

    // 3) Test A: explicit port
    console.log("\n[Test A] Send payload with port=9101");
    const a = await wsRequest(WS_URL, {
      ip: "127.0.0.1",
      port: 9101,
      data: "HELLO-9101\\n",
    });
    console.log("[Test A] Agent response:", a.response);
    await sleep(200);

    // 4) Test B: no port -> defaults to 9100
    console.log(
      "\n[Test B] Send payload WITHOUT port (should default to 9100)",
    );
    const b = await wsRequest(WS_URL, {
      ip: "127.0.0.1",
      data: "HELLO-DEFAULT\\n",
    });
    console.log("[Test B] Agent response:", b.response);
    await sleep(200);

    const aOk =
      mock9101.received.bytes > 0 &&
      a.response &&
      a.response.status === "success";
    const bOk =
      mock9100.received.bytes > 0 &&
      b.response &&
      b.response.status === "success";

    console.log("\n[RESULTS]");
    console.log(`- Mock 9101 received bytes: ${mock9101.received.bytes}`);
    console.log(`- Mock 9100 received bytes: ${mock9100.received.bytes}`);

    if (!aOk) {
      console.error(
        "FAIL: Test A did not send bytes to port 9101 or agent did not respond success.",
      );
      process.exitCode = 1;
    }
    if (!bOk) {
      console.error(
        "FAIL: Test B did not send bytes to default port 9100 or agent did not respond success.",
      );
      process.exitCode = 1;
    }

    if (aOk && bOk) {
      console.log(
        "PASS: Agent honored explicit port and default port behavior.",
      );
    }
  } catch (e) {
    console.error("SMOKE TEST ERROR:", e && e.message ? e.message : e);
    process.exitCode = 1;
  } finally {
    await stopProcess(agent);
    await stopServer(mock9100 && mock9100.server);
    await stopServer(mock9101 && mock9101.server);
  }
})();
