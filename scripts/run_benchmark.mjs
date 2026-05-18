#!/usr/bin/env node
import crypto from 'node:crypto';
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { spawn, spawnSync } from 'node:child_process';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, '..');

const schemaKeys = [
  'chromium_revision',
  'fork_revision',
  'build_args_hash',
  'platform',
  'gpu_name',
  'driver_version',
  'angle_backend',
  'renderer_type',
  'scene_name',
  'warmup_seconds',
  'measured_seconds',
  'avg_fps',
  'p50_frame_ms',
  'p95_frame_ms',
  'p99_frame_ms',
  'one_percent_low_fps',
  'point_one_percent_low_fps',
  'avg_cpu_frame_ms',
  'avg_gpu_frame_ms',
  'avg_js_frame_ms',
  'avg_render_submission_ms',
  'avg_compositor_latency_ms',
  'avg_presentation_latency_ms',
  'max_frame_ms',
  'dropped_frames',
  'draw_calls',
  'triangles',
  'texture_upload_mb',
  'buffer_upload_mb',
  'shader_compile_events',
  'js_heap_mb',
  'gpu_memory_mb',
  'process_rss_mb',
  'startup_ms_to_first_frame',
  'browser_binary_size_mb',
  'viewer_bundle_size_mb',
  'package_size_mb',
];

function parseArgs(argv) {
  const args = {
    browser: '',
    variant: 'unknown',
    scene: 'many-draw-calls',
    renderer: 'webgl2',
    complexity: '1',
    duration: '30',
    warmup: '5',
    precompile: false,
    prerenderFrames: '0',
    disableGpuTiming: false,
    viewerDir: path.join(rootDir, 'viewer', 'dist'),
    output: path.join(rootDir, 'benchmarks', 'raw', 'result.json'),
    buildArgs: '',
    packageDir: '',
    forkRevision: '',
    viewerFileMode: false,
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
    angleBackend: '',
  };
  const booleanArgs = new Set([
    'viewerMode',
    'viewerFileMode',
    'viewerTrustedContent',
    'viewerAggressiveGpu',
    'viewerRelaxedWebglValidation',
    'viewerInProcessGpu',
    'viewerSingleProcess',
    'viewerDisableUnneededBlinkFeatures',
    'viewerDirectGpuPresentation',
    'precompile',
    'disableGpuTiming',
  ]);

  for (let i = 2; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token.startsWith('--')) {
      throw new Error(`Unexpected positional argument: ${token}`);
    }
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
  ].filter(([, enabled]) => enabled).map(([name]) => `--${name}`);

  if (unsafeFlags.length && (!args.viewerMode || !args.viewerTrustedContent)) {
    throw new Error(
      `Unsafe viewer experiment flags require --viewerMode and --viewerTrustedContent: ${unsafeFlags.join(', ')}`,
    );
  }
}

function ensureFile(file, label) {
  if (!file || !fs.existsSync(file)) {
    throw new Error(`${label} not found: ${file}`);
  }
}

function readTextIfExists(file) {
  return fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : '';
}

function sha256Text(text) {
  return crypto.createHash('sha256').update(text).digest('hex');
}

function bytesToMb(bytes) {
  return bytes / (1024 * 1024);
}

function fileSizeMb(file) {
  try {
    return bytesToMb(fs.statSync(file).size);
  } catch {
    return null;
  }
}

function directorySizeBytes(dir) {
  if (!dir || !fs.existsSync(dir)) return null;
  let total = 0;
  const stack = [dir];
  while (stack.length) {
    const current = stack.pop();
    const entries = fs.readdirSync(current, { withFileTypes: true });
    for (const entry of entries) {
      const full = path.join(current, entry.name);
      if (entry.isDirectory()) {
        stack.push(full);
      } else if (entry.isFile()) {
        total += fs.statSync(full).size;
      }
    }
  }
  return total;
}

function directorySizeMb(dir) {
  const bytes = directorySizeBytes(dir);
  return bytes === null ? null : bytesToMb(bytes);
}

function commandText(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: options.cwd || rootDir,
    encoding: 'utf8',
    shell: false,
  });
  if (result.status !== 0) return '';
  return result.stdout.trim();
}

function getGitRevision(dir) {
  if (!fs.existsSync(path.join(dir, '.git'))) return null;
  return commandText('git', ['rev-parse', 'HEAD'], { cwd: dir }) || null;
}

function getBrowserVersion(browser) {
  if (process.platform === 'win32') {
    const literalPath = browser.replaceAll("'", "''");
    const out = commandText('powershell', [
      '-NoProfile',
      '-Command',
      `(Get-Item -LiteralPath '${literalPath}').VersionInfo.ProductVersion`,
    ]);
    if (out) return out;
  }
  return commandText(browser, ['--version']) || null;
}

function getProcessTreeRssMb(pid) {
  if (process.platform === 'win32') {
    const rootPid = Number(pid);
    if (!Number.isInteger(rootPid) || rootPid <= 0) return null;
    const script = `
$rootPid = ${rootPid}
$all = Get-CimInstance Win32_Process | Select-Object ProcessId, ParentProcessId, WorkingSetSize
$byId = @{}
$byParent = @{}
foreach ($p in $all) {
  $id = [int]$p.ProcessId
  $parent = [int]$p.ParentProcessId
  $byId[$id] = $p
  if (-not $byParent.ContainsKey($parent)) {
    $byParent[$parent] = New-Object System.Collections.Generic.List[int]
  }
  $byParent[$parent].Add($id)
}
$queue = New-Object System.Collections.Generic.Queue[int]
$queue.Enqueue($rootPid)
$visited = @{}
$sum = [int64]0
while ($queue.Count -gt 0) {
  $current = $queue.Dequeue()
  if ($visited.ContainsKey($current)) { continue }
  $visited[$current] = $true
  if ($byId.ContainsKey($current) -and $byId[$current].WorkingSetSize) {
    $sum += [int64]$byId[$current].WorkingSetSize
  }
  if ($byParent.ContainsKey($current)) {
    foreach ($child in $byParent[$current]) {
      $queue.Enqueue([int]$child)
    }
  }
}
$sum
`;
    const out = commandText('powershell', [
      '-NoProfile',
      '-Command',
      script,
    ]);
    const bytes = Number(out);
    return Number.isFinite(bytes) && bytes > 0 ? bytes / (1024 * 1024) : null;
  }

  const out = commandText('ps', ['-e', '-o', 'pid=,ppid=,rss=']);
  const rows = out.split('\n')
    .map((line) => line.trim().split(/\s+/).map(Number))
    .filter((parts) => parts.length === 3 && parts.every(Number.isFinite));
  const byParent = new Map();
  const rssByPid = new Map();
  for (const [rowPid, parentPid, rssKb] of rows) {
    rssByPid.set(rowPid, rssKb);
    if (!byParent.has(parentPid)) byParent.set(parentPid, []);
    byParent.get(parentPid).push(rowPid);
  }
  const queue = [Number(pid)];
  const visited = new Set();
  let rssKb = 0;
  while (queue.length) {
    const current = queue.shift();
    if (visited.has(current)) continue;
    visited.add(current);
    rssKb += rssByPid.get(current) || 0;
    queue.push(...(byParent.get(current) || []));
  }
  return rssKb > 0 ? rssKb / 1024 : null;
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
    ['.jpg', 'image/jpeg'],
    ['.jpeg', 'image/jpeg'],
    ['.webp', 'image/webp'],
    ['.wasm', 'application/wasm'],
  ]);

  const server = http.createServer((req, res) => {
    const url = new URL(req.url || '/', 'http://127.0.0.1');
    const pathname = decodeURIComponent(url.pathname);
    const relative = pathname === '/' ? 'index.html' : pathname.slice(1);
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

  return { server, staticRoot };
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

async function waitForPageTarget(debugPort, expectedUrl, timeoutMs) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const targets = await waitForJson(`http://127.0.0.1:${debugPort}/json/list`, 5000);
    const page = targets.find((target) => target.type === 'page' && target.webSocketDebuggerUrl);
    if (page && (!expectedUrl || page.url.startsWith(expectedUrl))) return page;
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
    const payload = JSON.stringify({ id, method, params });
    const promise = new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
    });
    this.socket.send(payload);
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

function percentile(sorted, fraction) {
  if (!sorted.length) return null;
  const index = Math.min(sorted.length - 1, Math.max(0, Math.floor((sorted.length - 1) * fraction)));
  return sorted[index];
}

function ensureSchema(result) {
  for (const key of schemaKeys) {
    if (!(key in result)) result[key] = null;
  }
  return result;
}

async function main() {
  const args = parseArgs(process.argv);
  assertTrustedViewerExperimentGates(args);
  const browser = path.resolve(args.browser || '');
  const viewerDir = path.resolve(args.viewerDir);
  const duration = Number(args.duration);
  const warmup = Number(args.warmup);
  const complexity = Number(args.complexity);

  ensureFile(browser, 'Browser executable');
  ensureFile(path.join(viewerDir, 'index.html'), 'Built viewer index');

  let server = null;
  let viewerPort = null;
  if (!args.viewerFileMode) {
    const staticServer = startStaticServer(viewerDir);
    server = staticServer.server;
    viewerPort = await listen(server);
  }
  const debugServer = http.createServer();
  const debugPort = await listen(debugServer);
  debugServer.close();

  const query = new URLSearchParams({
    benchmark: '1',
    scene: args.scene,
    renderer: args.renderer,
    complexity: String(complexity),
    duration: String(duration),
    warmup: String(warmup),
    precompile: args.precompile ? '1' : '0',
    prerenderFrames: String(args.prerenderFrames),
    gpuTiming: args.disableGpuTiming ? '0' : '1',
  });
  const viewerIndex = path.join(viewerDir, 'index.html');
  const viewerUrl = args.viewerFileMode
    ? `${pathToFileURL(viewerIndex).href}?${query.toString()}`
    : `http://127.0.0.1:${viewerPort}/?${query.toString()}`;
  const expectedPageUrl = args.viewerFileMode ? pathToFileURL(viewerIndex).href : `http://127.0.0.1:${viewerPort}/`;
  const tmpRoot = path.join(rootDir, 'benchmarks', 'tmp');
  fs.mkdirSync(tmpRoot, { recursive: true });
  const userDataDir = fs.mkdtempSync(path.join(tmpRoot, 'profile-'));
  const checkoutRevision = getGitRevision(path.join(rootDir, 'src'));
  const pinnedChromiumRevision = readTextIfExists(path.join(rootDir, '.chromium_revision')).trim() || checkoutRevision;
  const buildArgsPath = args.buildArgs ? path.resolve(args.buildArgs) : '';
  const buildArgsText = buildArgsPath && fs.existsSync(buildArgsPath) ? readTextIfExists(buildArgsPath) : '';
  const packageDir = args.packageDir ? path.resolve(args.packageDir) : '';
  const browserVersion = getBrowserVersion(browser);
  const srcDir = path.resolve(rootDir, 'src');
  const browserIsFromCheckout = browser.startsWith(`${srcDir}${path.sep}`);
  const chromiumRevision = browserIsFromCheckout ? pinnedChromiumRevision : browserVersion;
  const isForkVariant = args.variant.toLowerCase().includes('fork');
  const forkRevision = args.forkRevision || (browserIsFromCheckout && isForkVariant ? checkoutRevision : null);
  const requestedAngleBackend = args.angleBackend || args.viewerForceAngleBackend || null;

  const browserArgs = [
    `--remote-debugging-port=${debugPort}`,
    `--user-data-dir=${userDataDir}`,
    '--no-first-run',
    '--disable-default-apps',
    '--disable-background-networking',
    '--disable-component-update',
    '--disable-sync',
    '--disable-extensions',
    '--disable-popup-blocking',
    '--disable-software-rasterizer',
    '--enable-unsafe-webgpu',
    '--enable-webgpu-developer-features',
    '--autoplay-policy=no-user-gesture-required',
    '--disable-renderer-backgrounding',
    '--disable-background-timer-throttling',
    '--disable-features=Translate,OptimizationHints,AutofillServerCommunication',
  ];

  if (args.angleBackend) {
    browserArgs.push(`--use-angle=${args.angleBackend}`);
  }
  if (args.viewerMode) {
    browserArgs.push(`--viewer-app-url=${viewerUrl}`);
    browserArgs.push('--viewer-block-external-navigation');
  }
  if (args.viewerTrustedContent) {
    browserArgs.push('--viewer-trusted-content');
  }
  if (args.viewerAggressiveGpu) {
    browserArgs.push('--viewer-aggressive-gpu');
  }
  if (args.viewerRelaxedWebglValidation) {
    browserArgs.push('--viewer-relaxed-webgl-validation');
  }
  if (args.viewerInProcessGpu) {
    browserArgs.push('--viewer-in-process-gpu');
  }
  if (args.viewerSingleProcess) {
    browserArgs.push('--viewer-single-process');
  }
  if (args.viewerForceAngleBackend) {
    browserArgs.push(`--viewer-force-angle-backend=${args.viewerForceAngleBackend}`);
  }
  if (args.viewerDisableUnneededBlinkFeatures) {
    browserArgs.push('--viewer-disable-unneeded-blink-features');
  }
  if (args.viewerDirectGpuPresentation) {
    browserArgs.push('--viewer-direct-gpu-presentation');
  }
  browserArgs.push(...args.browserFlag);
  if (!args.viewerMode) {
    browserArgs.push(viewerUrl);
  }

  fs.mkdirSync(path.dirname(path.resolve(args.output)), { recursive: true });

  const child = spawn(browser, browserArgs, {
    cwd: rootDir,
    stdio: ['ignore', 'pipe', 'pipe'],
    windowsHide: true,
  });

  let childExit = null;
  child.on('exit', (code, signal) => {
    childExit = { code, signal };
  });

  let stdout = '';
  let stderr = '';
  child.stdout.on('data', (chunk) => { stdout += chunk.toString(); });
  child.stderr.on('data', (chunk) => { stderr += chunk.toString(); });

  const rssSamples = [];
  const rssInterval = setInterval(() => {
    const mb = getProcessTreeRssMb(child.pid);
    if (Number.isFinite(mb)) {
      rssSamples.push({ t_ms: Date.now(), mb });
    }
  }, 1000);
  rssInterval.unref?.();

  let cdp = null;
  try {
    const page = await waitForPageTarget(debugPort, expectedPageUrl, 30000);
    cdp = new CdpClient(page.webSocketDebuggerUrl);
    await cdp.connect();

    let result = null;
    const consoleErrors = [];
    cdp.on('Runtime.consoleAPICalled', (params) => {
      const values = consoleArgs(params);
      const parsedResult = parseBenchmarkConsoleResult(values);
      if (parsedResult) {
        result = parsedResult;
      } else if (params.type === 'error') {
        consoleErrors.push(values.join(' '));
      }
    });

    cdp.on('Runtime.exceptionThrown', (params) => {
      consoleErrors.push(params.exceptionDetails?.text || 'Runtime exception');
    });

    await cdp.send('Runtime.enable');
    await cdp.send('Page.enable');
    await cdp.send('Performance.enable').catch(() => {});
    await cdp.send('Page.bringToFront').catch(() => {});

    const timeoutMs = Math.max(60000, (duration + warmup + 45) * 1000);
    const start = Date.now();
    while (!result && Date.now() - start < timeoutMs) {
      if (childExit) {
        throw new Error(`Browser exited before benchmark result. code=${childExit.code} signal=${childExit.signal}`);
      }
      await new Promise((resolve) => setTimeout(resolve, 250));
    }

    if (!result) {
      throw new Error(`Timed out waiting for benchmark result. Console errors: ${consoleErrors.join('\n')}`);
    }

    const perfMetrics = await cdp.send('Performance.getMetrics').catch(() => null);
    const systemInfo = await cdp.send('SystemInfo.getInfo').catch(() => null);
    const jsHeap = perfMetrics?.metrics?.find((metric) => metric.name === 'JSHeapUsedSize')?.value;
    const gpuDevice = systemInfo?.gpu?.devices?.[0] || null;

    result.chromium_revision = result.chromium_revision || chromiumRevision || null;
    result.fork_revision = result.fork_revision || forkRevision || null;
    result.build_args_hash = result.build_args_hash || (buildArgsText ? sha256Text(buildArgsText) : null);
    result.benchmark_variant = args.variant;
    result.viewer_mode = args.viewerMode;
    result.viewer_block_external_navigation = args.viewerMode;
    result.viewer_file_mode = args.viewerFileMode;
    result.viewer_trusted_content = args.viewerTrustedContent;
    result.viewer_aggressive_gpu = args.viewerAggressiveGpu;
    result.viewer_relaxed_webgl_validation = args.viewerRelaxedWebglValidation;
    result.viewer_in_process_gpu = args.viewerInProcessGpu;
    result.viewer_single_process = args.viewerSingleProcess;
    result.viewer_force_angle_backend = args.viewerForceAngleBackend || null;
    result.viewer_disable_unneeded_blink_features = args.viewerDisableUnneededBlinkFeatures;
    result.viewer_direct_gpu_presentation = args.viewerDirectGpuPresentation;
    result.requested_angle_backend = requestedAngleBackend;
    result.browser_flags = browserArgs;
    result.browser_extra_flags = args.browserFlag;
    result.browser_executable = browser;
    result.browser_version = browserVersion;
    result.browser_is_from_checkout = browserIsFromCheckout;
    result.platform = result.platform || `${os.type()} ${os.release()} ${os.arch()}`;
    result.gpu_name = result.gpu_name || gpuDevice?.deviceString || null;
    result.driver_version = result.driver_version || gpuDevice?.driverVendor || gpuDevice?.driverVersion || null;
    result.angle_backend = result.angle_backend || requestedAngleBackend;
    result.js_heap_mb = result.js_heap_mb || (Number.isFinite(jsHeap) ? jsHeap / (1024 * 1024) : null);
    const finalRssMb = getProcessTreeRssMb(child.pid);
    if (Number.isFinite(finalRssMb)) {
      rssSamples.push({ t_ms: Date.now(), mb: finalRssMb });
    }
    const rssValues = rssSamples.map((sample) => sample.mb).filter(Number.isFinite);
    result.process_rss_mb = result.process_rss_mb ?? finalRssMb ?? rssValues.at(-1) ?? null;
    result.process_rss_start_mb = rssValues.length ? rssValues[0] : null;
    result.process_rss_peak_mb = rssValues.length ? Math.max(...rssValues) : null;
    result.process_rss_end_mb = rssValues.length ? rssValues[rssValues.length - 1] : null;
    result.process_rss_delta_mb =
      result.process_rss_start_mb !== null && result.process_rss_end_mb !== null
        ? result.process_rss_end_mb - result.process_rss_start_mb
        : null;
    result.browser_binary_size_mb = fileSizeMb(browser);
    result.viewer_bundle_size_mb = directorySizeMb(viewerDir);
    result.package_size_mb = packageDir ? directorySizeMb(packageDir) : null;
    result.generated_at = result.generated_at || new Date().toISOString();

    if (Array.isArray(result.frame_times_ms) && result.frame_times_ms.length) {
      const sorted = [...result.frame_times_ms].sort((a, b) => a - b);
      result.p50_frame_ms = result.p50_frame_ms ?? percentile(sorted, 0.50);
      result.p95_frame_ms = result.p95_frame_ms ?? percentile(sorted, 0.95);
      result.p99_frame_ms = result.p99_frame_ms ?? percentile(sorted, 0.99);
      result.max_frame_ms = result.max_frame_ms ?? sorted[sorted.length - 1];
    }

    ensureSchema(result);
    fs.writeFileSync(path.resolve(args.output), `${JSON.stringify(result, null, 2)}\n`);
    console.log(`Wrote ${path.resolve(args.output)}`);
  } finally {
    clearInterval(rssInterval);
    if (cdp) cdp.close();
    killProcessTree(child);
    server?.close();

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
