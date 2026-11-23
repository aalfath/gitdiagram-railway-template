// A tiny Upstash-REST-compatible bridge to Railway Redis, on 127.0.0.1 only.
// GitDiagram talks to Redis through Upstash's REST API (POST / with a command
// array, POST /pipeline with several); this answers the same requests from a
// normal Redis server, so no Upstash account is needed.
import http from "node:http";
import { createClient } from "@redis/client";

const port = Number(process.env.SHIM_PORT || 8079);
const token = process.env.UPSTASH_REDIS_REST_TOKEN || "";
const url = process.env.REDIS_URL || "";
if (!url) {
  console.error("redis-rest-shim: REDIS_URL is not set");
  process.exit(1);
}
if (token.length < 16) {
  console.error("redis-rest-shim: UPSTASH_REDIS_REST_TOKEN is missing");
  process.exit(1);
}

const client = createClient({
  url,
  socket: {
    connectTimeout: 10_000,
    reconnectStrategy: (retries) => Math.min(250 * (retries + 1), 3_000),
  },
});
let lastError = "";
client.on("error", (error) => {
  if (error.message !== lastError) console.error(`redis-rest-shim: ${error.message}`);
  lastError = error.message;
});
client.on("ready", () => {
  lastError = "";
  console.log("redis-rest-shim: connected to Redis");
});
client.connect().catch((error) => {
  console.error(`redis-rest-shim: cannot connect: ${error.message}`);
  process.exit(1);
});

const toArgs = (command) => command.map((part) => (typeof part === "string" ? part : String(part)));

async function run(command) {
  if (!Array.isArray(command) || command.length === 0) throw new Error("ERR empty command");
  return client.sendCommand(toArgs(command));
}

function reply(res, status, body) {
  const data = JSON.stringify(body);
  res.writeHead(status, { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(data) });
  res.end(data);
}

http
  .createServer((req, res) => {
    if (req.method === "GET" && req.url === "/health") {
      return reply(res, client.isReady ? 200 : 503, { ok: client.isReady });
    }
    if (req.headers.authorization !== `Bearer ${token}`) return reply(res, 401, { error: "Unauthorized" });
    if (req.method !== "POST") return reply(res, 405, { error: "Method not allowed" });
    const chunks = [];
    req.on("data", (chunk) => chunks.push(chunk));
    req.on("end", async () => {
      let body;
      try {
        body = JSON.parse(Buffer.concat(chunks).toString("utf8") || "null");
      } catch {
        return reply(res, 400, { error: "ERR invalid JSON" });
      }
      const path = (req.url || "/").split("?")[0].replace(/\/+$/, "");
      if (path === "/pipeline" || path === "/multi-exec") {
        if (!Array.isArray(body)) return reply(res, 400, { error: "ERR expected an array of commands" });
        const results = [];
        for (const command of body) {
          try {
            results.push({ result: await run(command) });
          } catch (error) {
            results.push({ error: error.message });
          }
        }
        return reply(res, 200, results);
      }
      if (path !== "") return reply(res, 404, { error: "Not found" });
      try {
        reply(res, 200, { result: await run(body) });
      } catch (error) {
        reply(res, 400, { error: error.message });
      }
    });
  })
  .listen(port, "127.0.0.1", () => console.log(`redis-rest-shim: listening on 127.0.0.1:${port}`));
