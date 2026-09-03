#!/usr/bin/env node
"use strict";
const readline = require("readline");
const { spawn } = require("child_process");
const fs = require("fs");

const PROTO = 1;
const sessions = new Map();          // sid -> { cwd, cancel: boolean, child }
const STUB = process.env.CODEX_ACP_STUB === "1";
const CODEX_CMD = process.env.CODEX_CMD || "codex";
const IS_WIN = process.platform === "win32";
const SANDBOX = process.env.CODEX_SANDBOX || "danger-full-access";

function send(o) { process.stdout.write(JSON.stringify(o) + "\n"); }
function reply(req, result, error) {
  if (error) send({ jsonrpc: "2.0", id: req.id, error });
  else send({ jsonrpc: "2.0", id: req.id, result });
}
function notify(method, params) { send({ jsonrpc: "2.0", method, params }); }
function update(sid, upd) { notify("session/update", { sessionId: sid, update: upd }); }
function msgChunk(sid, text) { update(sid, { sessionUpdate: "agent_message_chunk", content: { type: "text", text } }); }

function spawnCodex(cwd) {
  const args = ["exec", "--sandbox", SANDBOX];
  if (/\.[jJ][sS]$/.test(CODEX_CMD)) return spawn(process.execPath, [CODEX_CMD, ...args], { cwd: cwd || process.cwd(), env: process.env });
  if (fs.existsSync(CODEX_CMD)) return spawn(CODEX_CMD, args, { cwd: cwd || process.cwd(), env: process.env });
  return spawn(CODEX_CMD, args, { cwd: cwd || process.cwd(), env: process.env, shell: IS_WIN });
}

// Run one prompt; resolve with a PromptResponse stopReason. If canceled, kill child.
function runCodex(sid, cwd, instruction) {
  return new Promise((resolve) => {
    const sess = sessions.get(sid) || { cancel: false, child: null };
    sessions.set(sid, sess);
    if (STUB) {
      msgChunk(sid, "[[STUB]] " + instruction);
      resolve({ stop: "end_turn" });
      return;
    }
    let child;
    try { child = spawnCodex(cwd); } catch (e) { return resolve({ stop: "cancelled", err: String(e) }); }
    sess.child = child;
    // write instruction to stdin then EOF
    try { if (child.stdin) { child.stdin.write(instruction); child.stdin.end(); } } catch (_) {}
    const onCancel = () => { if (sess.cancel) { try { child.kill(); } catch (_) {} } };
    const t = setInterval(onCancel, 500);
    let buf = "";
    child.stdout.on("data", (d) => { buf += d.toString(); msgChunk(sid, d.toString()); });
    child.stderr.on("data", (d) => { buf += "\n" + d.toString(); msgChunk(sid, d.toString()); });
    child.on("error", (e) => { clearInterval(t); resolve({ stop: "cancelled", err: String(e) }); });
    child.on("close", (code) => {
      clearInterval(t);
      // If cancel was requested, ACP requires stopReason "cancelled".
      if (sess.cancel) return resolve({ stop: "cancelled" });
      resolve({ stop: code === 0 ? "end_turn" : "cancelled", code });
    });
  });
}

const rl = readline.createInterface({ input: process.stdin, terminal: false });
rl.on("line", (line) => {
  line = line.trim();
  if (!line) return;
  let req;
  try { req = JSON.parse(line); } catch { return; }
  const method = req.method, params = req.params || {};
  if (method === "initialize") {
    reply(req, { protocolVersion: PROTO, agentCapabilities: {} });
  } else if (method === "session/new") {
    const sid = "sess_" + Math.random().toString(16).slice(2);
    sessions.set(sid, { id: sid, cwd: params.cwd || process.cwd(), cancel: false, child: null });
    reply(req, { sessionId: sid, agentCapabilities: {} });
  } else if (method === "session/set_config_option") {
    reply(req, {});
  } else if (method === "session/prompt") {
    const sid = params.sessionId;
    const sess = sessions.get(sid) || { id: sid, cwd: params.cwd || process.cwd(), cancel: false, child: null };
    sessions.set(sid, sess);
    const instruction = params.instruction || params.text || "";
    runCodex(sid, sess.cwd, instruction).then((res) => {
      // PromptResponse: { stopReason: <snake_case stop> } (camelCase wire)
      reply(req, { stopReason: res.stop });
    });
  } else if (method === "session/cancel") {
    const sid = params.sessionId;
    const sess = sessions.get(sid);
    if (sess) { sess.cancel = true; try { if (sess.child) sess.child.kill(); } catch (_) {} }
    reply(req, {});
  } else {
    reply(req, null, { code: -32601, message: "method " + method + " not found" });
  }
});
