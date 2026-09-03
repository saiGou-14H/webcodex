#!/usr/bin/env node
"use strict";
/* codex-acp-proxy: WebCodex Runner <-> ACP v1 (NDJSON stdio) <-> codex
 * 环境变量:
 *   CODEX_ACP_STUB=1    用 stub 输出，便于冒烟测试（无需 codex）
 *   CODEX_CMD=<path>    codex 入口；若为 .js，用 node 直接跑；否则直接 spawn。
 *                      建议（Windows npm 全局）设为 ...\@openai\codex\bin\codex.js
 */
const readline = require("readline");
const { spawn } = require("child_process");

const PROTO = 1;
const sessions = new Map();
const STUB = process.env.CODEX_ACP_STUB === "1";
const CODEX_CMD = process.env.CODEX_CMD || "codex";
const IS_WIN = process.platform === "win32";

function send(o) { process.stdout.write(JSON.stringify(o) + "\n"); }
function reply(req, result, error) {
  if (error) send({ jsonrpc: "2.0", id: req.id, error });
  else send({ jsonrpc: "2.0", id: req.id, result });
}
function notify(method, params) { send({ jsonrpc: "2.0", method, params }); }
function update(sid, upd) { notify("session/update", { sessionId: sid, update: upd }); }
function finishErr(sid, msg, resolve) {
  update(sid, { sessionUpdate: "agent_message_chunk", content: { type: "text", text: msg } });
  update(sid, { sessionUpdate: "terminal_activity", stop_reason: "error", status: "failed" });
  resolve({ status: "failed", stop: "error", out: msg });
}

function codexCommand(cwd, instruction) {
  const args = ["exec", "--json", instruction];
  if (/\.[jJ][sS]$/.test(CODEX_CMD)) {
    // 用当前 node 直接跑 codex 的 .js 入口（绕开 .cmd/.exe 查找，参数安全）
    return { child: spawn(process.execPath, [CODEX_CMD, ...args], { cwd: cwd || process.cwd(), env: process.env }) };
  }
  // 非 .js：Windows 用 shell 以便解析 .cmd/.ps1 shim；其它平台直接跑
  return { child: spawn(CODEX_CMD, args, { cwd: cwd || process.cwd(), env: process.env, shell: IS_WIN }) };
}

function runCodex(sid, cwd, instruction) {
  return new Promise((resolve) => {
    if (STUB) {
      const out = "[[STUB]] " + instruction;
      update(sid, { sessionUpdate: "agent_message_chunk", content: { type: "text", text: out } });
      update(sid, { sessionUpdate: "terminal_activity", stop_reason: "end_turn", status: "completed" });
      return resolve({ status: "completed", stop: "end_turn", out });
    }
    let child;
    try { child = codexCommand(cwd, instruction).child; }
    catch (e) { return finishErr(sid, String(e), resolve); }
    let buf = "";
    child.stdout.on("data", (d) => { buf += d.toString(); update(sid, { sessionUpdate: "agent_message_chunk", content: { type: "text", text: d.toString() } }); });
    child.stderr.on("data", (d) => { buf += "\n" + d.toString(); update(sid, { sessionUpdate: "agent_message_chunk", content: { type: "text", text: d.toString() } }); });
    child.on("error", (e) => finishErr(sid, String(e), resolve));
    child.on("close", (code) => {
      const ok = code === 0;
      update(sid, { sessionUpdate: "terminal_activity", stop_reason: ok ? "end_turn" : "error", status: ok ? "completed" : "failed" });
      resolve({ status: ok ? "completed" : "failed", stop: ok ? "end_turn" : "error", out: buf || ("[codex exited " + code + "]") });
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
    sessions.set(sid, { id: sid, cwd: params.cwd || process.cwd() });
    reply(req, { sessionId: sid, agentCapabilities: {} });
  } else if (method === "session/set_config_option") {
    reply(req, {});
  } else if (method === "session/prompt") {
    const sid = params.sessionId;
    const sess = sessions.get(sid) || { id: sid, cwd: params.cwd || process.cwd() };
    const instruction = params.instruction || params.text || "";
    runCodex(sid, sess.cwd, instruction).then((res) => {
      reply(req, { message: { role: "agent", content: [{ type: "text", text: res.out }] }, stopReason: res.stop, status: res.status });
    });
  } else if (method === "session/cancel") {
    reply(req, {});
  } else {
    reply(req, null, { code: -32601, message: "method " + method + " not found" });
  }
});
