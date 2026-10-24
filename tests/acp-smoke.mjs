#!/usr/bin/env node
// acp-smoke.mjs — minimal Agent Client Protocol client used to verify that an
// ACP agent (Claude Code or Codex) starts inside the fidfab image, negotiates
// the protocol, and (when credentials are present) answers a prompt.
//
// Usage:
//   node acp-smoke.mjs [--handshake-only] [--timeout <s>] -- <agent command> [args...]
//
// Exit codes: 0 ok, 1 protocol/handshake failure, 2 prompt failed or wrong
// answer, 3 timeout.
import { spawn } from "node:child_process";
import { createInterface } from "node:readline";

const argv = process.argv.slice(2);
let handshakeOnly = false;
let timeoutSec = 180;
const sep = argv.indexOf("--");
const opts = sep >= 0 ? argv.slice(0, sep) : argv;
const cmd = sep >= 0 ? argv.slice(sep + 1) : [];
for (let i = 0; i < opts.length; i++) {
  if (opts[i] === "--handshake-only") handshakeOnly = true;
  else if (opts[i] === "--timeout") timeoutSec = Number(opts[++i]);
}
if (cmd.length === 0) {
  console.error("usage: acp-smoke.mjs [--handshake-only] [--timeout s] -- <command> [args]");
  process.exit(64);
}

const MAGIC = "FIDFAB_ACP_OK";
const child = spawn(cmd[0], cmd.slice(1), { stdio: ["pipe", "pipe", "inherit"], cwd: process.cwd() });
const rl = createInterface({ input: child.stdout });
let nextId = 1;
const pending = new Map();
let agentText = "";

function send(obj) {
  child.stdin.write(JSON.stringify(obj) + "\n");
}
function request(method, params) {
  const id = nextId++;
  return new Promise((resolve, reject) => {
    pending.set(id, { resolve, reject, method });
    send({ jsonrpc: "2.0", id, method, params });
  });
}
rl.on("line", (line) => {
  let msg;
  try { msg = JSON.parse(line); } catch { return; }
  if (msg.id !== undefined && (msg.result !== undefined || msg.error !== undefined) && pending.has(msg.id)) {
    const p = pending.get(msg.id); pending.delete(msg.id);
    msg.error ? p.reject(new Error(`${p.method}: ${JSON.stringify(msg.error)}`)) : p.resolve(msg.result);
    return;
  }
  if (msg.method === "session/update") {
    const u = msg.params?.update;
    if (u?.sessionUpdate === "agent_message_chunk" && u.content?.type === "text") agentText += u.content.text;
    return;
  }
  if (msg.method === "session/request_permission" && msg.id !== undefined) {
    // Inside the sandbox every tool call is allowed; pick the first "allow" option.
    const options = msg.params?.options ?? [];
    const allow = options.find((o) => /allow/i.test(o.kind ?? o.optionId ?? "")) ?? options[0];
    send({ jsonrpc: "2.0", id: msg.id, result: { outcome: { outcome: "selected", optionId: allow?.optionId } } });
    return;
  }
  if (msg.id !== undefined && msg.method) {
    // Unknown request from the agent (e.g. fs/*): refuse politely.
    send({ jsonrpc: "2.0", id: msg.id, error: { code: -32601, message: `unsupported: ${msg.method}` } });
  }
});

const timer = setTimeout(() => { console.error(`acp-smoke: timeout after ${timeoutSec}s`); child.kill("SIGKILL"); process.exit(3); }, timeoutSec * 1000);
child.on("exit", (code) => { if (!done) { console.error(`acp-smoke: agent exited early with code ${code}`); process.exit(1); } });
let done = false;

try {
  const init = await request("initialize", {
    protocolVersion: 1,
    clientCapabilities: { fs: { readTextFile: false, writeTextFile: false }, terminal: false },
    clientInfo: { name: "fidfab-acp-smoke", version: "0.1.0" },
  });
  console.log(`acp-smoke: initialized protocolVersion=${init.protocolVersion} agent=${JSON.stringify(init.agentInfo ?? init.agentCapabilities ?? {}).slice(0, 200)}`);
  if (handshakeOnly) { done = true; clearTimeout(timer); child.kill(); process.exit(0); }

  const session = await request("session/new", { cwd: process.cwd(), mcpServers: [] });
  console.log(`acp-smoke: session ${session.sessionId}`);
  const result = await request("session/prompt", {
    sessionId: session.sessionId,
    prompt: [{ type: "text", text: `Reply with exactly the token ${MAGIC} and nothing else. Do not use any tools.` }],
  });
  console.log(`acp-smoke: stopReason=${result.stopReason} text=${JSON.stringify(agentText.trim()).slice(0, 200)}`);
  done = true; clearTimeout(timer); child.kill();
  process.exit(agentText.includes(MAGIC) ? 0 : 2);
} catch (err) {
  console.error(`acp-smoke: ${err.message}`);
  done = true; clearTimeout(timer); child.kill();
  process.exit(1);
}
