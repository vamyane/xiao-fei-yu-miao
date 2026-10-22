// 小肥鱼喵 · 桌面 App 后端（仅本机 127.0.0.1:5210）
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import net from 'node:net';
import { spawn, execFile } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const APP_DIR = __dirname;
const ROOT = process.env.QQBRIDGE_ROOT || path.resolve(__dirname, '..');
const PORT = 5210;

const execFileP = (file, args, opts = {}) => new Promise((resolve, reject) => {
  execFile(file, args, { windowsHide: true, timeout: 8000, ...opts }, (err, stdout, stderr) => {
    if (err) reject(err); else resolve(String(stdout || ''));
  });
});

function tcpOpen(port, host = '127.0.0.1', timeoutMs = 800) {
  return new Promise((resolve) => {
    const sock = net.connect({ port, host });
    let done = false;
    const finish = (v) => { if (done) return; done = true; try { sock.destroy(); } catch {} resolve(v); };
    sock.setTimeout(timeoutMs);
    sock.once('connect', () => finish(true));
    sock.once('timeout', () => finish(false));
    sock.once('error', () => finish(false));
  });
}

let cache = { at: 0, data: null };

async function dshInfo() {
  try {
    const out = await execFileP('powershell.exe', ['-NoProfile', '-Command',
      "$p=@(Get-Process | Where-Object {$_.ProcessName -like 'DeepSeek Harness*'}).Id; if($p.Count -eq 0){'NONE';exit} ; $ports=@(); foreach($ln in (netstat -ano | Select-String 'LISTENING')){if($ln.Line -match '^\\s*TCP\\s+\\S+:(\\d+)\\s+\\S+\\s+LISTENING\\s+(\\d+)\\s*$'){$port=[int]$Matches[1];$procId=[int]$Matches[2]; if($p -contains $procId){$ports+=$port}}}; ($ports | Sort-Object -Unique) -join ','"
    ]);
    const text = String(out).trim();
    if (text === 'NONE') return { running: false, port: null };
    const ports = text.split(',').map((x) => Number(x)).filter((x) => x > 0);
    for (const port of ports) {
      try {
        const res = await fetch(`http://127.0.0.1:${port}/`, { signal: AbortSignal.timeout(1200) });
        if (res.status >= 200 && res.status < 500) return { running: true, port };
      } catch {}
    }
    return { running: ports.length > 0, port: ports[0] || null };
  } catch {
    return { running: false, port: null };
  }
}

function snowlumaDir() {
  try {
    const c = JSON.parse(fs.readFileSync(path.join(ROOT, 'config.json'), 'utf8'));
    if (c && c.snowluma && c.snowluma.homeDir) return c.snowluma.homeDir;
  } catch {}
  return process.env.SNOWLUMA_DIR || 'D:/SnowLuma';
}
function onebotToken() {
  try {
    const dir = path.join(snowlumaDir(), 'config');
    const file = fs.readdirSync(dir).find((f) => /^onebot_.*\.json$/.test(f));
    if (!file) return null;
    const j = JSON.parse(fs.readFileSync(path.join(dir, file), 'utf8'));
    return j?.networks?.httpServers?.[0]?.accessToken || null;
  } catch { return null; }
}

async function qqInfo() {
  const token = onebotToken();
  if (!token) return { online: false };
  try {
    const res = await fetch('http://127.0.0.1:3000/get_login_info', {
      headers: { authorization: `Bearer ${token}` },
      signal: AbortSignal.timeout(1500)
    });
    if (!res.ok) return { online: false };
    const j = await res.json();
    if (j?.status === 'ok' && j?.retcode === 0 && j?.data) {
      return { online: true, nickname: j.data.nickname, uin: j.data.user_id };
    }
    return { online: false };
  } catch { return { online: false }; }
}

async function getStatus(force = false) {
  const now = Date.now();
  if (!force && cache.data && now - cache.at < 1200) return cache.data;
  const [dsh, snowluma, bridge, comfy, qq] = await Promise.all([
    dshInfo(),
    tcpOpen(5099),
    tcpOpen(3100),
    tcpOpen(8188),
    qqInfo()
  ]);
  const data = {
    at: new Date().toISOString(),
    dsh: { running: dsh.running, port: dsh.port },
    snowluma: { running: snowluma },
    bridge: { running: bridge },
    comfy: { running: comfy },
    qq,
    online: Boolean(dsh.running && snowluma && bridge && qq.online)
  };
  cache = { at: now, data };
  return data;
}

async function readLogs(lines = 120) {
  try {
    const text = await fs.promises.readFile(path.join(ROOT, 'state', 'stdout.log'), 'utf8');
    const arr = text.split(/\r?\n/).filter(Boolean).slice(-lines);
    return arr.join('\n');
  } catch {
    return '(日志为空或桥接未启动)';
  }
}

function runTask(name) {
  return execFileP('schtasks.exe', ['/Run', '/TN', name], { timeout: 10000 });
}

function openTarget(target) {
  const map = {
    bridgeConsole: 'http://127.0.0.1:3100',
    snowluma: 'http://127.0.0.1:5099',
    comfyui: 'http://127.0.0.1:8188',
    logs: path.join(ROOT, 'state'),
    bridgeDir: ROOT
  };
  let t = map[target];
  if (!t) return false;
  if (t.startsWith('http')) {
    spawn('cmd.exe', ['/c', 'start', '', t], { detached: true, windowsHide: true }).unref();
  } else {
    spawn('explorer.exe', [t], { detached: true, windowsHide: true }).unref();
  }
  return true;
}

function openAdvancedPanel() {
  spawn('powershell.exe', ['-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', path.join(ROOT, 'bot-control.ps1')], { detached: true, windowsHide: true }).unref();
  return true;
}

function json(res, code, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(code, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' });
  res.end(body);
}

function readBody(req) {
  return new Promise((resolve) => {
    let data = '';
    req.on('data', (c) => { data += c; if (data.length > 1e6) req.destroy(); });
    req.on('end', () => { try { resolve(JSON.parse(data || '{}')); } catch { resolve({}); } });
  });
}

const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.png': 'image/png', '.svg': 'image/svg+xml', '.ico': 'image/x-icon' };

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://127.0.0.1');
  try {
    if (req.method === 'GET' && (url.pathname === '/' || url.pathname === '/index.html')) {
      const html = await fs.promises.readFile(path.join(APP_DIR, 'index.html'));
      res.writeHead(200, { 'content-type': MIME['.html'], 'cache-control': 'no-store' });
      res.end(html);
      return;
    }
    if (req.method === 'GET' && url.pathname === '/api/status') {
      json(res, 200, await getStatus(true));
      return;
    }
    if (req.method === 'GET' && url.pathname === '/api/logs') {
      const lines = Math.max(20, Math.min(400, Number(url.searchParams.get('lines')) || 120));
      json(res, 200, { ok: true, text: await readLogs(lines) });
      return;
    }
    if (req.method === 'POST' && url.pathname === '/api/action') {
      const body = await readBody(req);
      const action = String(body.action || '');
      if (action === 'start') { await runTask('QQBotStart'); json(res, 200, { ok: true, action }); return; }
      if (action === 'stop') { await runTask('QQBotStop'); json(res, 200, { ok: true, action }); return; }
      if (action === 'restart') {
        await runTask('QQBotStop');
        setTimeout(() => { runTask('QQBotStart').catch(() => {}); }, 4000);
        json(res, 200, { ok: true, action });
        return;
      }
      json(res, 400, { ok: false, error: 'unknown action' });
      return;
    }
    if (req.method === 'POST' && url.pathname === '/api/open') {
      const body = await readBody(req);
      const target = String(body.target || '');
      const ok = target === 'advanced' ? openAdvancedPanel() : openTarget(target);
      json(res, ok ? 200 : 400, { ok });
      return;
    }
    if (req.method === 'POST' && url.pathname === '/api/shutdown') {
      json(res, 200, { ok: true });
      setTimeout(() => process.exit(0), 200);
      return;
    }
    json(res, 404, { ok: false, error: 'not found' });
  } catch (e) {
    json(res, 500, { ok: false, error: String(e?.message ?? e) });
  }
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`[app] listening http://127.0.0.1:${PORT}`);
});

