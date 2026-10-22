#!/usr/bin/env node
// G2 spike: Nova'nın dayandığı CLI protokolünü gerçek `claude` ile doğrular.
//   1) stream-json giriş/çıkış, kısmi mesajlar (text_delta)
//   2) izin isteği: control_request/can_use_tool → control_response (allow + updatedPermissions)
//   3) aynı süreçte ikinci tur + control_request/interrupt
// Geçici bir dizinde çalışır; ucuz model (haiku) kullanır. Kullanım: `make spike` (CLAUDE_BIN ile yol verilebilir).
import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { mkdtempSync, readFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const cwd = mkdtempSync(join(tmpdir(), 'nova-spike-'));
const bin = process.env.CLAUDE_BIN ?? 'claude';
const args = ['-p', '--input-format', 'stream-json', '--output-format', 'stream-json', '--verbose',
  '--include-partial-messages', '--model', 'haiku', '--tools', 'Write,Read', '--permission-mode', 'default',
  '--permission-prompts', 'host', '--permission-prompt-tool', 'stdio', '--no-session-persistence'];
const t0 = performance.now();
const p = spawn(bin, args, { cwd, stdio: ['pipe', 'pipe', 'inherit'] });
const send = (o) => p.stdin.write(JSON.stringify(o) + '\n');
const checks = { init: false, textDelta: false, canUseTool: false, toolSucceeded: false, interruptAck: false, interruptedResult: false };
let firstByte = null, firstDelta = null, turn = 0, interruptSent = false;

createInterface({ input: p.stdout }).on('line', (line) => {
  firstByte ??= performance.now() - t0;
  let m;
  try { m = JSON.parse(line); } catch { return; }
  if (m.type === 'system' && m.subtype === 'init') checks.init = true;
  if (m.type === 'stream_event' && m.event?.delta?.type === 'text_delta') {
    checks.textDelta = true;
    firstDelta ??= performance.now() - t0;
    if (turn === 1 && !interruptSent) {
      interruptSent = true;
      send({ type: 'control_request', request_id: 'int-1', request: { subtype: 'interrupt' } });
    }
  }
  if (m.type === 'control_request' && m.request?.subtype === 'can_use_tool') {
    checks.canUseTool = true;
    send({ type: 'control_response', response: { subtype: 'success', request_id: m.request_id,
      response: { behavior: 'allow', updatedInput: m.request.input, updatedPermissions: m.request.permission_suggestions ?? [] } } });
  }
  if (m.type === 'control_response' && m.response?.request_id === 'int-1') checks.interruptAck = m.response.subtype === 'success';
  if (m.type === 'user') {
    for (const b of m.message?.content ?? []) if (b.type === 'tool_result' && !b.is_error) checks.toolSucceeded = true;
  }
  if (m.type === 'result') {
    turn++;
    if (turn === 1) send({ type: 'user', message: { role: 'user', content: 'Write a 300 word essay about the sea.' } });
    else { checks.interruptedResult = m.is_error === true; p.stdin.end(); }
  }
});

send({ type: 'control_request', request_id: 'init', request: { subtype: 'initialize' } });
send({ type: 'user', message: { role: 'user', content: 'Create a file named b.txt containing "y" using the Write tool, then reply OK.' } });

p.on('exit', () => {
  const file = join(cwd, 'b.txt');
  const wrote = existsSync(file) && readFileSync(file, 'utf8').trim() === 'y';
  console.log(JSON.stringify({ ...checks, fileWritten: wrote, firstStdoutMs: Math.round(firstByte), firstTextDeltaMs: Math.round(firstDelta), cwd }, null, 2));
  const ok = Object.values(checks).every(Boolean) && wrote;
  console.log(ok ? 'SPIKE PASS' : 'SPIKE FAIL');
  process.exit(ok ? 0 : 1);
});
