// 媒体能力 MCP server（stdio）：AI 画图 / 发本地图片 / 文字转语音。
// 由 DSH 的 MCP 客户端 spawn（cordis.patch.yml 里的 mcp-media 行）。
//
// 工具：
//   qq_generate_image  —— ComfyUI 生成图片 → 直接发到 QQ 会话（也可只生成不发）
//   qq_send_image      —— 把本地已有图片发到 QQ 会话（只允许白名单目录）
//   qq_send_tts        —— edge-tts 合成语音 → 写进桥接语音库 → 以 QQ 语音条发出
//
// 安全边界：
// - 会话 key 必须先命中桥接 config.json 的 allow/deny 白名单；
// - token 通过桥接 /api/socialV2/state 校验（与会话令牌同口径）；
// - 图片只允许发给白名单会话，且只允许读取白名单目录里的文件；
// - 发送频率有硬上限，防止刷屏。
import fs from 'node:fs';
import path from 'node:path';
import { spawn, execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { z } from 'zod';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '..');
const MEDIA_DIR = path.join(ROOT, 'media');
const AUDIO_DIR = path.join(ROOT, 'audio');
const COMFY_OUTPUT_DIR = 'D:/ComfyUI/ComfyUI_windows_portable/ComfyUI/output';
const execFileAsync = promisify(execFile);

function loadConfig() {
  try {
    let text = fs.readFileSync(path.join(ROOT, 'config.json'), 'utf8');
    if (text.charCodeAt(0) === 0xFEFF) text = text.slice(1);
    return JSON.parse(text);
  } catch {
    return {};
  }
}

function errorText(value, fallback) {
  if (typeof value === 'string' && value.trim()) return value.trim();
  if (value && typeof value === 'object') {
    try { const t = JSON.stringify(value); if (t && t !== '{}') return t.slice(0, 500); } catch {}
    const m = value.message ?? value.msg ?? value.error;
    if (typeof m === 'string' && m.trim()) return m.trim().slice(0, 500);
  }
  return fallback;
}

function getAccess() {
  const c = loadConfig();
  return {
    allowGroups: (c.allow?.groups ?? []).map(String),
    allowPrivate: (c.allow?.private ?? []).map(String),
    denyGroups: (c.deny?.groups ?? []).map(String),
    denyPrivate: (c.deny?.private ?? []).map(String),
    allowAllWhenEmpty: c.allowAllWhenEmpty === true
  };
}

function isAllowed(allowList, denyList, id, allowAllWhenEmpty) {
  const s = String(id);
  if (denyList.includes(s)) return false;
  if (allowList.length > 0) return allowList.includes(s);
  return allowAllWhenEmpty;
}

function parseKey(key) {
  const m = /^(group|private):(.+)$/.exec(String(key ?? '').trim());
  if (!m) throw new Error('key 格式必须是 group:群号 或 private:QQ号');
  return { scope: m[1], id: m[2] };
}

function assertAllowed(key) {
  const { scope, id } = parseKey(key);
  const a = getAccess();
  const ok = scope === 'group'
    ? isAllowed(a.allowGroups, a.denyGroups, id, a.allowAllWhenEmpty)
    : isAllowed(a.allowPrivate, a.denyPrivate, id, a.allowAllWhenEmpty);
  if (!ok) throw new Error(`目标会话不在白名单内：${key}`);
}

function getOneBotConfig() {
  const c = loadConfig();
  return {
    httpUrl: (c.snowluma?.httpUrl ?? 'http://127.0.0.1:3000').replace(/\/+$/, ''),
    token: c.snowluma?.accessToken ?? ''
  };
}

async function onebot(action, params = {}, timeoutMs = 60000) {
  const { httpUrl, token } = getOneBotConfig();
  const res = await fetch(`${httpUrl}/${action}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: JSON.stringify(params),
    signal: AbortSignal.timeout(timeoutMs)
  });
  if (!res.ok) throw new Error(`OneBot HTTP ${res.status}`);
  const body = await res.json();
  if (body.status !== 'ok' || body.retcode !== 0) throw new Error(`OneBot ${action} 失败: retcode=${body.retcode} ${body.wording ?? ''}`);
  return body.data;
}

// ---------- 桥接 API（校验会话 token / 语音发送） ----------
function agentApiBase() {
  const port = Number(loadConfig().consolePort) || 3100;
  return `http://127.0.0.1:${port}`;
}

function readConsoleToken() {
  try {
    const c = loadConfig();
    const configured = String(c.consoleToken ?? '').trim();
    if (/^[A-Za-z0-9_-]{16,128}$/.test(configured)) return configured;
  } catch {}
  try {
    return fs.readFileSync(path.join(ROOT, 'state', 'console-token'), 'utf8').trim();
  } catch {
    return '';
  }
}

async function agentApi(pathname, init = {}) {
  const timeoutMs = init.timeoutMs || 15000;
  const { timeoutMs: _omit, ...rest } = init;
  const headers = {
    'content-type': 'application/json',
    ...(readConsoleToken() ? { 'x-console-token': readConsoleToken() } : {}),
    'x-agent-call': '1',
    ...(rest.headers ?? {})
  };
  const res = await fetch(`${agentApiBase()}${pathname}`, { ...rest, headers, signal: AbortSignal.timeout(timeoutMs) });
  let body = null;
  try { body = await res.json(); } catch {}
  if (!res.ok) throw new Error(errorText(body?.error, `桥接 API HTTP ${res.status}`));
  if (body && typeof body === 'object' && body.ok === false) throw new Error(errorText(body.error, '桥接 API 返回 ok:false'));
  return body;
}

async function validateSession(key, token) {
  if (!token) throw new Error('缺少会话令牌 token（见唤醒提示里的【会话令牌】）');
  const q = new URLSearchParams({ key: String(key) });
  await agentApi(`/api/socialV2/state?${q.toString()}`, { headers: { 'x-agent-token': String(token) } });
}

// ---------- 频率限制 ----------
const rate = { image: [], tts: [] };
function rateOk(kind, perMinute) {
  const now = Date.now();
  rate[kind] = rate[kind].filter((t) => now - t < 60000);
  if (rate[kind].length >= perMinute) return false;
  rate[kind].push(now);
  return true;
}

// ---------- 发图 ----------
function allowedImageRoots() {
  const c = loadConfig().media ?? {};
  const roots = Array.isArray(c.allowedImageDirs) && c.allowedImageDirs.length
    ? c.allowedImageDirs
    : [MEDIA_DIR, COMFY_OUTPUT_DIR];
  return roots.map((r) => path.resolve(String(r)));
}

function assertSafeImagePath(p) {
  const resolved = path.resolve(String(p));
  const roots = allowedImageRoots();
  if (!roots.some((root) => resolved === root || resolved.startsWith(root + path.sep))) {
    throw new Error(`图片路径不在允许目录内：${resolved}（允许：${roots.join(' / ')}）`);
  }
  return resolved;
}

async function sendImageFile(key, token, filePath, caption = '') {
  assertAllowed(key);
  await validateSession(key, token);
  const { scope, id } = parseKey(key);
  const abs = assertSafeImagePath(filePath);
  const stat = fs.statSync(abs);
  const maxBytes = Number(loadConfig().media?.maxImageBytes) || 10 * 1024 * 1024;
  if (stat.size > maxBytes) throw new Error(`图片过大：${(stat.size / 1048576).toFixed(1)}MB > ${(maxBytes / 1048576).toFixed(0)}MB`);
  const ext = path.extname(abs).slice(1).toLowerCase() || 'png';
  const mime = ext === 'jpg' || ext === 'jpeg' ? 'image/jpeg' : ext === 'gif' ? 'image/gif' : ext === 'webp' ? 'image/webp' : 'image/png';
  const b64 = fs.readFileSync(abs).toString('base64');
  const segment = { type: 'image', data: { file: `base64://${b64}` } };
  const action = scope === 'group' ? 'send_group_msg' : 'send_private_msg';
  const params = scope === 'group'
    ? { group_id: Number(id), message: [segment] }
    : { user_id: Number(id), message: [segment] };
  const data = await onebot(action, params, 120000);
  return { messageId: data?.message_id, mime, bytes: stat.size, caption };
}

// ---------- ComfyUI 生成 ----------
async function comfyFetch(pathname, init = {}, timeoutMs = 30000) {
  const base = (loadConfig().media?.comfyUrl ?? 'http://127.0.0.1:8188').replace(/\/+$/, '');
  const res = await fetch(`${base}${pathname}`, { ...init, signal: AbortSignal.timeout(timeoutMs) });
  if (!res.ok) throw new Error(`ComfyUI HTTP ${res.status}（${pathname}）`);
  return res;
}

async function comfyGenerate({ prompt, negative = '', width = 768, height = 768, steps = 24, cfg = 7, seed }) {
  const c = loadConfig().media ?? {};
  const ckpt = c.checkpoint || 'Counterfeit-V2.5_fp16.safetensors';
  const stylePrefix = c.stylePrefix ?? 'masterpiece, best quality, ';
  const actualPrompt = String(prompt).startsWith('masterpiece') ? String(prompt) : stylePrefix + String(prompt);
  const actualSeed = Number.isFinite(Number(seed)) ? Number(seed) : Math.floor(Math.random() * 2 ** 48);
  const workflow = {
    4: { class_type: 'CheckpointLoaderSimple', inputs: { ckpt_name: ckpt } },
    5: { class_type: 'EmptyLatentImage', inputs: { width: Number(width), height: Number(height), batch_size: 1 } },
    6: { class_type: 'CLIPTextEncode', inputs: { text: actualPrompt, clip: ['4', 1] } },
    7: { class_type: 'CLIPTextEncode', inputs: { text: String(negative || 'lowres, bad anatomy, bad hands, text, error, worst quality, low quality, jpeg artifacts, watermark, signature'), clip: ['4', 1] } },
    3: {
      class_type: 'KSampler',
      inputs: {
        seed: actualSeed, steps: Number(steps), cfg: Number(cfg),
        sampler_name: 'dpmpp_2m', scheduler: 'karras', denoise: 1,
        model: ['4', 0], positive: ['6', 0], negative: ['7', 0], latent_image: ['5', 0]
      }
    },
    8: { class_type: 'VAEDecode', inputs: { samples: ['3', 0], vae: ['4', 2] } },
    9: { class_type: 'SaveImage', inputs: { filename_prefix: 'qqbot', images: ['8', 0] } }
  };
  const submit = await comfyFetch('/prompt', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ prompt: workflow, client_id: `qqbot-${Date.now()}` })
  });
  const submitted = await submit.json();
  const promptId = submitted.prompt_id;
  if (!promptId) throw new Error('ComfyUI 未返回 prompt_id');
  const deadline = Date.now() + 180000;
  let images = null;
  while (Date.now() < deadline) {
    await new Promise((r) => setTimeout(r, 1200));
    const histRes = await comfyFetch(`/history/${promptId}`);
    const hist = await histRes.json();
    const entry = hist[promptId];
    if (!entry || !entry.outputs) continue;
    for (const out of Object.values(entry.outputs)) {
      if (Array.isArray(out.images) && out.images.length) { images = out.images; break; }
    }
    if (images) break;
    if (entry.status?.status_str === 'error') throw new Error('ComfyUI 生成失败（工作流报错）');
  }
  if (!images) throw new Error('ComfyUI 生成超时（180 秒）');
  const img = images[0];
  const q = new URLSearchParams({ filename: img.filename, subfolder: img.subfolder ?? '', type: img.type ?? 'output' });
  const view = await comfyFetch(`/view?${q.toString()}`, {}, 60000);
  const buf = Buffer.from(await view.arrayBuffer());
  fs.mkdirSync(MEDIA_DIR, { recursive: true });
  const outFile = path.join(MEDIA_DIR, `comfy-${Date.now()}.png`);
  fs.writeFileSync(outFile, buf);
  return { file: outFile, buffer: buf, seed: actualSeed, width, height, prompt: actualPrompt };
}

// ---------- 撒娇后期：句尾拖音 + 微微上扬 ----------
// 把最后 tailMs 毫秒单独拉出来：轻微升调（pitch）+ 放慢（duration），再和正文拼接。
// 纯本地 ffmpeg 处理，可随时用 config 的 media.cutePost.enabled 关闭。
async function applyCutePost(inputFile) {
  const c = loadConfig().media ?? {};
  const cp = c.cutePost ?? {};
  if (cp.enabled !== true) return inputFile;
  const ffmpeg = String(cp.ffmpegPath || 'ffmpeg');
  const ffprobe = String(cp.ffprobePath || 'ffprobe');
  const tailSec = Math.max(0.25, Math.min(1.2, Number(cp.tailMs ?? 550) / 1000));
  const pitch = Math.max(1.0, Math.min(1.15, Number(cp.pitch ?? 1.06)));
  const duration = Math.max(1.0, Math.min(1.35, Number(cp.duration ?? 1.18)));
  const volume = Math.max(0.5, Math.min(1.5, Number(cp.volume ?? 1.02)));
  let durationSec = 0;
  try {
    const { stdout } = await execFileAsync(
      ffprobe,
      ['-v', 'error', '-show_entries', 'format=duration', '-of', 'default=noprint_wrappers=1:nokey=1', inputFile],
      { windowsHide: true, timeout: 10000 }
    );
    durationSec = Number(String(stdout).trim());
  } catch {
    return inputFile;
  }
  if (!Number.isFinite(durationSec) || durationSec < 1.0) return inputFile;
  const main = Math.max(0.3, durationSec - tailSec);
  const atempo = 1 / (duration * pitch);
  if (atempo < 0.5 || atempo > 2.0) return inputFile;
  const filter = `[0:a]atrim=0:${main.toFixed(3)},asetpts=PTS-STARTPTS[a];`
    + `[0:a]atrim=start=${main.toFixed(3)},asetpts=PTS-STARTPTS,asetrate=24000*${pitch},aresample=24000,atempo=${atempo.toFixed(4)}[b];`
    + `[a][b]concat=n=2:v=0:a=1,volume=${volume}[out]`;
  const outFile = inputFile.replace(/\.[^.]+$/, '') + '-cute.mp3';
  try {
    await execFileAsync(
      ffmpeg,
      ['-y', '-i', inputFile, '-filter_complex', filter, '-map', '[out]', '-ar', '24000', '-ac', '1', outFile],
      { windowsHide: true, timeout: 30000 }
    );
    if (fs.existsSync(outFile) && fs.statSync(outFile).size > 1000) return outFile;
  } catch {}
  return inputFile;
}

// ---------- TTS ----------
function ttsPython() {
  const c = loadConfig().media ?? {};
  if (c.ttsPythonPath) return String(c.ttsPythonPath);
  return path.join(ROOT, 'tools', 'tts', 'Scripts', 'python.exe');
}

function runProcess(cmd, args, timeoutMs = 90000) {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, args, { windowsHide: true });
    let stderr = '';
    const timer = setTimeout(() => { try { child.kill(); } catch {}; reject(new Error('TTS 进程超时')); }, timeoutMs);
    child.stderr.on('data', (d) => { stderr += d.toString(); });
    child.on('error', (e) => { clearTimeout(timer); reject(e); });
    child.on('close', (code) => {
      clearTimeout(timer);
      if (code === 0) resolve();
      else reject(new Error(`TTS 失败（exit ${code}）：${stderr.slice(0, 300)}`));
    });
  });
}

// 语音配置：默认走阿里云百炼（叶清禾）；没有 Key 或显式配置时回退 edge-tts。
function ttsConfig() {
  const m = loadConfig().media ?? {};
  const t = m.tts ?? {};
  const apiKey = String(t.apiKey ?? m.dashscopeApiKey ?? process.env.DASHSCOPE_API_KEY ?? '').trim();
  const explicitProvider = String(t.provider ?? m.ttsProvider ?? '').trim();
  return {
    provider: explicitProvider || (apiKey ? 'dashscope' : 'edge'),
    apiKey,
    model: String(t.model ?? m.dashscopeModel ?? 'qwen-audio-3.1-tts-flash'),
    voice: String(t.voice ?? m.dashscopeVoice ?? 'yeqinghe_v3.1'),
    workspaceId: String(t.workspaceId ?? m.dashscopeWorkspaceId ?? '').trim(),
    region: String(t.region ?? m.dashscopeRegion ?? 'beijing').trim(),
    instruction: String(t.instruction ?? m.ttsInstruction ?? '').trim(),
    rate: Number(t.rate ?? m.ttsRateValue ?? 1.0),
    pitch: Number(t.pitch ?? m.ttsPitchValue ?? 1.0),
    edgeVoice: String(m.ttsVoice ?? 'zh-CN-XiaoxiaoNeural')
  };
}

function normalizeTtsText(text) {
  const clean = String(text ?? '').replace(/[\r\n]+/g, ' ').trim();
  if (!clean) throw new Error('text 不能为空');
  if (clean.length > 200) throw new Error('text 太长（最多 200 字，语音条会过长）');
  return clean;
}

// 阿里云百炼非实时语音合成（Qwen-Audio-TTS）
async function synthTtsDashscope(text, voiceOverride) {
  const cfg = ttsConfig();
  if (!cfg.apiKey) throw new Error('未配置阿里云百炼 DashScope API Key（config.json 的 media.tts.apiKey）');
  const clean = normalizeTtsText(text);
  const useVoice = String(voiceOverride || cfg.voice);
  const regionHost = cfg.region === 'singapore' ? 'ap-southeast-1.maas.aliyuncs.com' : 'cn-beijing.maas.aliyuncs.com';
  const host = cfg.workspaceId ? `${cfg.workspaceId}.${regionHost}` : 'dashscope.aliyuncs.com';
  const url = `https://${host}/api/v1/services/audio/tts/SpeechSynthesizer`;
  const input = {
    text: clean,
    voice: useVoice,
    format: 'mp3',
    sample_rate: 24000
  };
  if (cfg.instruction) input.instruction = cfg.instruction;
  if (Number.isFinite(cfg.rate) && cfg.rate !== 1.0) input.rate = cfg.rate;
  if (Number.isFinite(cfg.pitch) && cfg.pitch !== 1.0) input.pitch = cfg.pitch;
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${cfg.apiKey}` },
    body: JSON.stringify({ model: cfg.model, input }),
    signal: AbortSignal.timeout(60000)
  });
  const raw = await res.text();
  if (!res.ok) {
    let msg = raw.slice(0, 400);
    try { const j = JSON.parse(raw); msg = j.message || j.code || msg; } catch {}
    throw new Error(`阿里云 TTS 失败（HTTP ${res.status}）：${msg}`);
  }
  let json = null;
  try { json = JSON.parse(raw); } catch { throw new Error('阿里云 TTS 返回非 JSON'); }
  const audioUrl = json?.output?.audio?.url;
  if (!audioUrl) throw new Error(`阿里云 TTS 未返回音频地址：${raw.slice(0, 300)}`);
  const audioRes = await fetch(audioUrl, { signal: AbortSignal.timeout(60000) });
  if (!audioRes.ok) throw new Error(`下载合成音频失败（HTTP ${audioRes.status}）`);
  const buf = Buffer.from(await audioRes.arrayBuffer());
  if (buf.length < 1000) throw new Error('阿里云 TTS 合成音频为空');
  const maxBytes = Number(loadConfig().media?.maxVoiceBytes) || 12 * 1024 * 1024;
  if (buf.length > maxBytes) throw new Error('合成音频过大');
  const dir = path.join(AUDIO_DIR, 'tts');
  fs.mkdirSync(dir, { recursive: true });
  const name = `tts-${Date.now()}.mp3`;
  const abs = path.join(dir, name);
  fs.writeFileSync(abs, buf);
  const postPath = await applyCutePost(abs);
  const stat2 = fs.statSync(postPath);
  return { abs: postPath, rel: `tts/${path.basename(postPath)}`, bytes: stat2.size, voice: useVoice, provider: 'dashscope' };
}

// edge-tts（免费兜底）
async function synthTtsEdge(text, voiceOverride) {
  const c = loadConfig().media ?? {};
  const py = ttsPython();
  if (!fs.existsSync(py)) throw new Error(`找不到 TTS 解释器：${py}（先安装 edge-tts）`);
  const clean = normalizeTtsText(text);
  const useVoice = String(voiceOverride || c.ttsVoice || 'zh-CN-XiaoxiaoNeural');
  const dir = path.join(AUDIO_DIR, 'tts');
  fs.mkdirSync(dir, { recursive: true });
  const name = `tts-${Date.now()}.mp3`;
  const abs = path.join(dir, name);
  const args = ['-m', 'edge_tts', '--voice', useVoice, '--text', clean, '--write-media', abs];
  let rateStr = String(c.ttsRate ?? '');
  if (rateStr) args.push('--rate', rateStr);
  let pitchStr = String(c.ttsPitch ?? '');
  if (pitchStr) args.push('--pitch', pitchStr);
  await runProcess(py, args, 60000);
  const stat = fs.statSync(abs);
  if (stat.size < 1000) throw new Error('TTS 生成的音频为空');
  const maxBytes = Number(c.maxVoiceBytes) || 12 * 1024 * 1024;
  if (stat.size > maxBytes) throw new Error('TTS 音频过大');
  const postPath = await applyCutePost(abs);
  const stat2 = fs.statSync(postPath);
  return { abs: postPath, rel: `tts/${path.basename(postPath)}`, bytes: stat2.size, voice: useVoice, provider: 'edge' };
}

async function synthTts(text, voice) {
  const cfg = ttsConfig();
  // voice 参数：看起来像 Qwen 音色 ID（含 _v3）就透传；否则回退配置里的默认音色
  const override = voice && /_v3/i.test(String(voice)) ? String(voice) : undefined;
  if (cfg.provider === 'dashscope') return synthTtsDashscope(text, override);
  return synthTtsEdge(text, voice);
}

// ---------- MCP 工具 ----------
const server = new McpServer({ name: 'media', version: '0.1.0' });

server.tool(
  'qq_generate_image',
  '用本地 ComfyUI 生成一张图片并直接发到当前 QQ 会话。适合群友要求画图、要表情包、要插画时使用。注意：① 画图较慢（10~40 秒），一次对话最多画 1~2 张；② prompt 用英文或中文都可以，但英文效果更好；③ 默认 768x768（二次元模型），不要频繁画；④ 生成后图片会直接以图片消息发出，你可以先用返回的预览确认画面内容；⑤ 不要用它生成侵权/真人明星/色情/政治内容。',
  {
    key: z.string().describe('会话 key，格式 group:群号 或 private:QQ号'),
    token: z.string().describe('会话令牌（见唤醒提示中的【会话令牌】）'),
    prompt: z.string().describe('画面描述，尽量具体：主体 + 动作 + 场景 + 风格；英文效果更好'),
    negative: z.string().optional().describe('反向提示词（可选）'),
    width: z.number().optional().describe('宽，默认 768（范围 512~1024，必须是 64 的倍数）'),
    height: z.number().optional().describe('高，默认 768（范围 512~1024，必须是 64 的倍数）'),
    steps: z.number().optional().describe('采样步数，默认 24（10~40）'),
    seed: z.number().optional().describe('可选：固定种子复现同一张图'),
    send: z.boolean().optional().describe('是否直接发到 QQ，默认 true；false 时只生成并返回预览')
  },
  async ({ key, token, prompt, negative, width, height, steps, seed, send }) => {
    try {
      assertAllowed(key);
      await validateSession(key, token);
      if (!rateOk('image', Number(loadConfig().media?.maxImagesPerMinute) || 4)) {
        return { content: [{ type: 'text', text: '画图太频繁了（每分钟上限），等一会儿再画。' }], isError: true };
      }
      const w = Math.min(1024, Math.max(512, Math.round((Number(width) || 768) / 64) * 64));
      const h = Math.min(1024, Math.max(512, Math.round((Number(height) || 768) / 64) * 64));
      const gen = await comfyGenerate({ prompt, negative: negative ?? '', width: w, height: h, steps: steps ?? 24, seed });
      let sendResult = null;
      if (send !== false) sendResult = await sendImageFile(key, token, gen.file, prompt);
      return {
        content: [
          { type: 'text', text: `已生成图片${sendResult ? `并发送（message_id=${sendResult.messageId}）` : '（未发送）'}：${gen.width}x${gen.height}, seed=${gen.seed}` },
          { type: 'image', mimeType: 'image/png', data: gen.buffer.toString('base64') }
        ]
      };
    } catch (error) {
      return { content: [{ type: 'text', text: `画图失败：${errorText(error?.message ?? error, '未知错误')}。如果提示连接失败，说明 ComfyUI 没启动（start-all.ps1 会拉起）。` }], isError: true };
    }
  }
);

server.tool(
  'qq_send_image',
  '把一张本地图片发到当前 QQ 会话。只允许发送白名单目录（qq-bridge/media、ComfyUI/output）里的文件；图片不能超过 10MB。适合把已经生成/准备好的图片发出去。',
  {
    key: z.string().describe('会话 key，格式 group:群号 或 private:QQ号'),
    token: z.string().describe('会话令牌（见唤醒提示中的【会话令牌】）'),
    imagePath: z.string().describe('图片绝对路径（必须在白名单目录内）'),
    caption: z.string().optional().describe('可选：写进会话记录的说明')
  },
  async ({ key, token, imagePath, caption }) => {
    try {
      if (!rateOk('image', Number(loadConfig().media?.maxImagesPerMinute) || 4)) {
        return { content: [{ type: 'text', text: '发图太频繁了（每分钟上限），等一会儿。' }], isError: true };
      }
      const result = await sendImageFile(key, token, imagePath, caption ?? '');
      return { content: [{ type: 'text', text: `已发送图片（message_id=${result.messageId}，${(result.bytes / 1024).toFixed(0)}KB）` }] };
    } catch (error) {
      return { content: [{ type: 'text', text: `发图失败：${errorText(error?.message ?? error, '未知错误')}` }], isError: true };
    }
  }
);

server.tool(
  'qq_send_tts',
  '把一句话用 TTS 合成语音，并以 QQ 语音条发到当前会话。适合想“开口说话”时用（晚安、撒娇、正经说一句），但语音比打字更打扰：一次对话最多 1~2 条，不要连续发。注意：① 文本会被完整念出来，别超过 60 字；② 默认女声（zh-CN-XiaoxiaoNeural），可用 voice 参数换音色；③ 只有返回 verified=true 才代表语音真的发出去了。',
  {
    key: z.string().describe('会话 key，格式 group:群号 或 private:QQ号'),
    token: z.string().describe('会话令牌（见唤醒提示中的【会话令牌】）'),
    text: z.string().describe('要念的话，最多 60 字，口语化、不用表情符号'),
    voice: z.string().optional().describe('edge-tts 音色名，默认 zh-CN-XiaoxiaoNeural；可选 zh-CN-YunxiNeural（男）、zh-CN-XiaoyiNeural（活泼女）等')
  },
  async ({ key, token, text, voice }) => {
    try {
      assertAllowed(key);
      await validateSession(key, token);
      if (!rateOk('tts', Number(loadConfig().media?.maxTtsPerMinute) || 3)) {
        return { content: [{ type: 'text', text: '语音发太频繁了（每分钟上限），等一会儿。' }], isError: true };
      }
      const tts = await synthTts(text, voice);
      const data = await agentApi('/api/socialV2/send-voice', {
        method: 'POST',
        headers: { 'x-agent-token': String(token) },
        body: JSON.stringify({ key, voice: tts.rel, label: '', verify: true, readback: false, token }),
        timeoutMs: 300000
      });
      const verified = data?.verified === true;
      return {
        content: [{
          type: 'text',
          text: verified
            ? `语音已发出（${tts.voice}，${(tts.bytes / 1024).toFixed(0)}KB，verified=true）`
            : `语音发送结果未确认：${errorText(data?.error, JSON.stringify(data)?.slice(0, 300))}`
        }],
        isError: !verified
      };
    } catch (error) {
      return { content: [{ type: 'text', text: `发语音失败：${errorText(error?.message ?? error, '未知错误')}` }], isError: true };
    }
  }
);

// ---------- 自检模式（不启动 MCP，不影响 DSH） ----------
async function selfTest() {
  const cfg = loadConfig();
  console.log('config media:', JSON.stringify(cfg.media ?? {}, null, 2));
  console.log('access:', JSON.stringify(getAccess()));
  console.log('onebot:', JSON.stringify({ ...getOneBotConfig(), token: getOneBotConfig().token ? '***' : '' }));
  try {
    const r = await comfyFetch('/system_stats', {}, 10000);
    console.log('ComfyUI:', r.status, 'OK');
  } catch (e) {
    console.log('ComfyUI: 不可用', e.message);
  }
  try {
    const t = await synthTts('自检语音，一切正常。', undefined);
    console.log('TTS OK:', t.rel, t.bytes, 'bytes');
  } catch (e) {
    console.log('TTS 失败:', e.message);
  }
}

if (process.argv.includes('--selftest')) {
  await selfTest();
  process.exit(0);
}

await server.connect(new StdioServerTransport());
