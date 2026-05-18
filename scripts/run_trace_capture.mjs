#!/usr/bin/env node
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, '..');

function parseArgs(argv) {
  const args = {
    browser: '',
    scene: 'many-draw-calls',
    renderer: 'webgl2',
    complexity: '1',
    duration: '5',
    warmup: '1',
    startDelayMs: '2000',
    precompile: false,
    prerenderFrames: '0',
    viewerDir: path.join(rootDir, 'viewer', 'dist'),
    output: path.join(rootDir, 'benchmarks', 'traces', 'trace.json'),
    categories: [
      'devtools.timeline',
      'disabled-by-default-devtools.timeline',
      'disabled-by-default-devtools.timeline.frame',
      'blink',
      'cc',
      'gpu',
      'viz',
      'v8',
      'disabled-by-default-gpu.service',
      'disabled-by-default-v8.cpu_profiler',
    ].join(','),
    viewerMode: false,
    viewerTrustedContent: false,
    viewerAggressiveGpu: false,
    viewerRelaxedWebglValidation: false,
    viewerInProcessGpu: false,
    viewerSingleProcess: false,
    viewerForceAngleBackend: '',
    viewerDisableUnneededBlinkFeatures: false,
    viewerDirectGpuPresentation: false,
    browserFlag: [],
  };
  const booleanArgs = new Set([
    'viewerMode',
    'viewerTrustedContent',
    'viewerAggressiveGpu',
    'viewerRelaxedWebglValidation',
    'viewerInProcessGpu',
    'viewerSingleProcess',
    'viewerDisableUnneededBlinkFeatures',
    'viewerDirectGpuPresentation',
    'precompile',
  ]);

  for (let i = 2; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token.startsWith('--')) throw new Error(`Unexpected positional argument: ${token}`);
    const key = token.slice(2);
    if (key === 'browser-flag') {
      args.browserFlag.push(argv[++i]);
    } else if (booleanArgs.has(key)) {
      args[key] = true;
    } else if (key in args) {
      args[key] = argv[++i];
    } else {
      throw new Error(`Unknown argument: ${token}`);
    }
  }
  if (!args.browser) {
    throw new Error('Usage: node scripts/run_trace_capture.mjs --browser <browser.exe> [--output trace.json]');
  }
  return args;
}

function assertTrustedViewerExperimentGates(args) {
  const unsafeFlags = [
    ['viewerAggressiveGpu', args.viewerAggressiveGpu],
    ['viewerRelaxedWebglValidation', args.viewerRelaxedWebglValidation],
    ['viewerInProcessGpu', args.viewerInProcessGpu],
    ['viewerSingleProcess', args.viewerSingleProcess],
    ['viewerForceAngleBackend', Boolean(args.viewerForceAngleBackend)],
    ['viewerDisableUnneededBlinkFeatures', args.viewerDisableUnneededBlinkFeatures],
    ['viewerDirectGpuPresentation', args.viewerDirectGpuPresentation],
  ].filter(([, enabled]) => enabled).map(([flag]) => `--${flag}`);

  if (unsafeFlags.length > 0 && (!args.viewerMode || !args.viewerTrustedContent)) {
    throw new Error(`Unsafe viewer experiment flags require --viewerMode and --viewerTrustedContent: ${unsafeFlags.join(', ')}`);
  }
}

function ensureFile(file, label) {
  if (!file || !fs.existsSync(file)) throw new Error(`${label} not found: ${file}`);
}

function killProcessTree(child) {
  if (!child || child.killed) return;
  if (process.platform === 'win32') {
    spawnSync('taskkill', ['/pid', String(child.pid), '/T', '/F'], { stdio: 'ignore' });
  } else {
    child.kill('SIGTERM');
  }
}

async function listen(server) {
  return new Promise((resolve, reject) => {
    server.on('error', reject);
    server.listen(0, '127.0.0.1', () => resolve(server.address().port));
  });
}

function startStaticServer(root) {
  const staticRoot = path.resolve(root);
  const mime = new Map([
    ['.html', 'text/html; charset=utf-8'],
    ['.js', 'text/javascript; charset=utf-8'],
    ['.css', 'text/css; charset=utf-8'],
    ['.json', 'application/json; charset=utf-8'],
    ['.svg', 'image/svg+xml'],
    ['.png', 'image/png'],
    ['.wasm', 'application/wasm'],
  ]);

  return http.createServer((req, res) => {
    const url = new URL(req.url || '/', 'http://127.0.0.1');
    const relative = url.pathname === '/' ? 'index.html' : decodeURIComponent(url.pathname.slice(1));
    const resolved = path.resolve(staticRoot, relative);
    const resolvedRelative = path.relative(staticRoot, resolved);
    if (resolvedRelative.startsWith('..') || path.isAbsolute(resolvedRelative)) {
      res.writeHead(403);
      res.end('Forbidden');
      return;
    }
    fs.readFile(resolved, (err, data) => {
      if (err) {
        res.writeHead(404);
        res.end('Not found');
        return;
      }
      res.writeHead(200, {
        'Content-Type': mime.get(path.extname(resolved)) || 'application/octet-stream',
        'Cache-Control': 'no-store',
      });
      res.end(data);
    });
  });
}

async function waitForJson(url, timeoutMs) {
  const start = Date.now();
  let lastError = null;
  while (Date.now() - start < timeoutMs) {
    try {
      const response = await fetch(url);
      if (response.ok) return await response.json();
      lastError = new Error(`HTTP ${response.status}`);
    } catch (error) {
      lastError = error;
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw lastError || new Error(`Timed out waiting for ${url}`);
}

async function waitForPageTarget(debugPort, timeoutMs) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const targets = await waitForJson(`http://127.0.0.1:${debugPort}/json/list`, 5000);
    const page = targets.find((target) => target.type === 'page' && target.webSocketDebuggerUrl);
    if (page) return page;
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error('Timed out waiting for a debuggable page target.');
}

class CdpClient {
  constructor(url) {
    this.url = url;
    this.nextId = 1;
    this.pending = new Map();
    this.handlers = new Map();
    this.socket = null;
  }

  async connect() {
    this.socket = new WebSocket(this.url);
    this.socket.addEventListener('message', (event) => {
      const text = typeof event.data === 'string' ? event.data : event.data.toString();
      const message = JSON.parse(text);
      if (message.id && this.pending.has(message.id)) {
        const { resolve, reject } = this.pending.get(message.id);
        this.pending.delete(message.id);
        if (message.error) reject(new Error(`${message.error.message || 'CDP error'} (${message.error.code})`));
        else resolve(message.result || {});
      } else if (message.method && this.handlers.has(message.method)) {
        for (const handler of this.handlers.get(message.method)) handler(message.params || {});
      }
    });
    await new Promise((resolve, reject) => {
      this.socket.addEventListener('open', resolve, { once: true });
      this.socket.addEventListener('error', reject, { once: true });
    });
  }

  on(method, handler) {
    if (!this.handlers.has(method)) this.handlers.set(method, []);
    this.handlers.get(method).push(handler);
  }

  send(method, params = {}) {
    const id = this.nextId++;
    const promise = new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
    });
    this.socket.send(JSON.stringify({ id, method, params }));
    return promise;
  }

  close() {
    if (this.socket) this.socket.close();
  }
}

function consoleArgs(params) {
  return (params.args || []).map((arg) => {
    if ('value' in arg) return arg.value;
    return arg.description || arg.unserializableValue || '';
  });
}

function parseBenchmarkConsoleResult(values) {
  if (values[0] === 'THREE_VIEWER_RESULT' && typeof values[1] === 'string') {
    return JSON.parse(values[1]);
  }
  if (typeof values[0] === 'string' && values[0].startsWith('THREE_VIEWER_RESULT ')) {
    return JSON.parse(values[0].slice('THREE_VIEWER_RESULT '.length));
  }
  return null;
}

async function readStream(cdp, handle) {
  let data = '';
  for (;;) {
    const chunk = await cdp.send('IO.read', { handle });
    data += chunk.data || '';
    if (chunk.eof) break;
  }
  await cdp.send('IO.close', { handle }).catch(() => {});
  return data;
}

async function main() {
  const args = parseArgs(process.argv);
  assertTrustedViewerExperimentGates(args);
  const browser = path.resolve(args.browser);
  const viewerDir = path.resolve(args.viewerDir);
  ensureFile(browser, 'Browser executable');
  ensureFile(path.join(viewerDir, 'index.html'), 'Built viewer index');

  const viewerServer = startStaticServer(viewerDir);
  const viewerPort = await listen(viewerServer);
  const debugServer = http.createServer();
  const debugPort = await listen(debugServer);
  debugServer.close();

  const query = new URLSearchParams({
    benchmark: '1',
    scene: args.scene,
    renderer: args.renderer,
    complexity: String(args.complexity),
      duration: String(args.duration),
      warmup: String(args.warmup),
      startDelayMs: String(args.startDelayMs),
      precompile: args.precompile ? '1' : '0',
    prerenderFrames: String(args.prerenderFrames),
  });
  const viewerUrl = `http://127.0.0.1:${viewerPort}/?${query.toString()}`;
  const tmpRoot = path.join(rootDir, 'benchmarks', 'tmp');
  fs.mkdirSync(tmpRoot, { recursive: true });
  const userDataDir = fs.mkdtempSync(path.join(tmpRoot, 'trace-profile-'));

  const browserArgs = [
    `--remote-debugging-port=${debugPort}`,
    `--user-data-dir=${userDataDir}`,
    '--no-first-run',
    '--disable-default-apps',
    '--disable-background-networking',
    '--disable-component-update',
    '--disable-sync',
    '--disable-extensions',
    '--disable-software-rasterizer',
    '--enable-unsafe-webgpu',
    '--enable-webgpu-developer-features',
    '--disable-renderer-backgrounding',
    '--disable-background-timer-throttling',
  ];
  if (args.viewerMode) {
    browserArgs.push(`--viewer-app-url=${viewerUrl}`);
    browserArgs.push('--viewer-block-external-navigation');
  }
  if (args.viewerTrustedContent) browserArgs.push('--viewer-trusted-content');
  if (args.viewerAggressiveGpu) browserArgs.push('--viewer-aggressive-gpu');
  if (args.viewerRelaxedWebglValidation) browserArgs.push('--viewer-relaxed-webgl-validation');
  if (args.viewerInProcessGpu) browserArgs.push('--viewer-in-process-gpu');
  if (args.viewerSingleProcess) browserArgs.push('--viewer-single-process');
  if (args.viewerForceAngleBackend) browserArgs.push(`--viewer-force-angle-backend=${args.viewerForceAngleBackend}`);
  if (args.viewerDisableUnneededBlinkFeatures) browserArgs.push('--viewer-disable-unneeded-blink-features');
  if (args.viewerDirectGpuPresentation) browserArgs.push('--viewer-direct-gpu-presentation');
  browserArgs.push(...args.browserFlag);
  browserArgs.push(args.viewerMode ? 'about:blank' : viewerUrl);

  fs.mkdirSync(path.dirname(path.resolve(args.output)), { recursive: true });
  const child = spawn(browser, browserArgs, {
    cwd: rootDir,
    stdio: ['ignore', 'pipe', 'pipe'],
    windowsHide: true,
  });

  let stdout = '';
  let stderr = '';
  child.stdout.on('data', (chunk) => { stdout += chunk.toString(); });
  child.stderr.on('data', (chunk) => { stderr += chunk.toString(); });

  let cdp = null;
  try {
    const page = await waitForPageTarget(debugPort, 30000);
    cdp = new CdpClient(page.webSocketDebuggerUrl);
    await cdp.connect();
    await cdp.send('Runtime.enable');
    await cdp.send('Page.enable');

    let benchmarkResult = null;
    let traceStream = null;
    cdp.on('Runtime.consoleAPICalled', (params) => {
      const values = consoleArgs(params);
      const parsedResult = parseBenchmarkConsoleResult(values);
      if (parsedResult) {
        benchmarkResult = parsedResult;
      }
    });
    cdp.on('Tracing.tracingComplete', (params) => {
      traceStream = params.stream;
    });

    await cdp.send('Tracing.start', {
      categories: args.categories,
      transferMode: 'ReturnAsStream',
      options: 'record-continuously',
    });

    if (!args.viewerMode) {
      await cdp.send('Page.navigate', { url: viewerUrl });
    }

    const timeoutMs = Math.max(60000, (Number(args.duration) + Number(args.warmup) + 45) * 1000);
    const start = Date.now();
    while (!benchmarkResult && Date.now() - start < timeoutMs) {
      if (child.exitCode !== null) {
        throw new Error(`Browser exited before trace benchmark result with code ${child.exitCode}`);
      }
      await new Promise((resolve) => setTimeout(resolve, 250));
    }
    if (!benchmarkResult) {
      throw new Error('Timed out waiting for benchmark result before ending trace.');
    }

    await cdp.send('Tracing.end');
    const traceStart = Date.now();
    while (!traceStream && Date.now() - traceStart < 30000) {
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
    if (!traceStream) throw new Error('Timed out waiting for trace stream.');

    const traceText = await readStream(cdp, traceStream);
    fs.writeFileSync(path.resolve(args.output), traceText);
    fs.writeFileSync(path.resolve(args.output).replace(/\.json$/i, '.result.json'), `${JSON.stringify({
      generated_at: new Date().toISOString(),
      platform: `${os.type()} ${os.release()} ${os.arch()}`,
      browser,
      scene: args.scene,
      renderer: args.renderer,
      duration_seconds: Number(args.duration),
      warmup_seconds: Number(args.warmup),
      start_delay_ms: Number(args.startDelayMs),
      viewer_mode: args.viewerMode,
      viewer_block_external_navigation: args.viewerMode,
      viewer_trusted_content: args.viewerTrustedContent,
      viewer_aggressive_gpu: args.viewerAggressiveGpu,
      viewer_relaxed_webgl_validation: args.viewerRelaxedWebglValidation,
      viewer_in_process_gpu: args.viewerInProcessGpu,
      viewer_single_process: args.viewerSingleProcess,
      viewer_force_angle_backend: args.viewerForceAngleBackend || null,
      requested_angle_backend: args.viewerForceAngleBackend || null,
      viewer_disable_unneeded_blink_features: args.viewerDisableUnneededBlinkFeatures,
      viewer_direct_gpu_presentation: args.viewerDirectGpuPresentation,
      browser_flags: browserArgs,
      browser_extra_flags: args.browserFlag,
      categories: args.categories,
      benchmark_result: benchmarkResult,
    }, null, 2)}\n`);
    console.log(`Wrote ${path.resolve(args.output)}`);
  } finally {
    if (cdp) cdp.close();
    killProcessTree(child);
    viewerServer.close();

    const logPath = path.resolve(args.output).replace(/\.json$/i, '.browser.log');
    if (stdout || stderr) {
      fs.writeFileSync(logPath, [
        '=== stdout ===',
        stdout,
        '=== stderr ===',
        stderr,
      ].join('\n'));
    }
  }
}

main().catch((error) => {
  console.error(error.stack || error.message);
  process.exit(1);
});
