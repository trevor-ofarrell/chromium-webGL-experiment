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
    disableGpuTiming: false,
    textureUploadMode: 'canvas',
    webgpuBundleMode: 'off',
    queueInstrumentation: false,
    commandEncoderInstrumentation: false,
    bindGroupInstrumentation: false,
    pipelineStateInstrumentation: false,
    bufferStateInstrumentation: false,
    renderStateInstrumentation: false,
    immediateInstrumentation: false,
    showHud: false,
    precompile: false,
    prerenderFrames: '0',
    settleGpuAfterWarmup: false,
    pipelineQuietFrames: '0',
    pipelineQuietMaxFrames: '30',
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
    viewerZeroCopy: false,
    viewerInProcessGpu: false,
    viewerSingleProcess: false,
    viewerForceAngleBackend: '',
    viewerDisableUnneededBlinkFeatures: false,
    viewerDirectGpuPresentation: false,
    viewerDeferWebgpuPipelineFlush: false,
    viewerDeferWebgpuQueueFlush: false,
    viewerDeferWebgpuSubmitFlush: false,
    viewerSkipWebgpuCanvasTextureValidation: false,
    viewerSkipWebgpuCanvasMemoryAccounting: false,
    viewerSkipWebgpuCopyExternalImageColorConversion: false,
    viewerSkipWebgpuCopyExternalImageColorSpaceValidation: false,
    viewerSkipWebgpuCopyExternalImageDestValidation: false,
    viewerSkipWebgpuCopyExternalImageSourceValidation: false,
    viewerSkipWebgpuCopyExternalImageCopySizeValidation: false,
    viewerSkipWebgpuWriteTextureLayoutValidation: false,
    viewerRejectWebgpuCpuTextureFallback: false,
    viewerSkipWebgpuUseCounters: false,
    viewerCacheWebgpuBindGroupLayouts: false,
    viewerSkipWebgpuCommandLabels: false,
    viewerSkipWebgpuResourceLabels: false,
    viewerSkipWebgpuShaderSourceNullCheck: false,
    viewerSkipWebgpuShaderMemoryAccounting: false,
    viewerSkipWebgpuRedundantPipelineSets: false,
    viewerSkipWebgpuRedundantBindGroupSets: false,
    viewerSkipWebgpuRedundantBufferSets: false,
    viewerSkipWebgpuRedundantRenderStateSets: false,
    viewerTraceWebgpuQueue: false,
    browserFlag: [],
    unsafeFullSizeWindow: false,
    allowSoftwareRendering: false,
  };
  const booleanArgs = new Set([
    'viewerMode',
    'viewerTrustedContent',
    'viewerAggressiveGpu',
    'viewerRelaxedWebglValidation',
    'viewerZeroCopy',
    'viewerInProcessGpu',
    'viewerSingleProcess',
    'viewerDisableUnneededBlinkFeatures',
    'viewerDirectGpuPresentation',
    'viewerDeferWebgpuPipelineFlush',
    'viewerDeferWebgpuQueueFlush',
    'viewerDeferWebgpuSubmitFlush',
    'viewerSkipWebgpuCanvasTextureValidation',
    'viewerSkipWebgpuCanvasMemoryAccounting',
    'viewerSkipWebgpuCopyExternalImageColorConversion',
    'viewerSkipWebgpuCopyExternalImageColorSpaceValidation',
    'viewerSkipWebgpuCopyExternalImageDestValidation',
    'viewerSkipWebgpuCopyExternalImageSourceValidation',
    'viewerSkipWebgpuCopyExternalImageCopySizeValidation',
    'viewerSkipWebgpuWriteTextureLayoutValidation',
    'viewerRejectWebgpuCpuTextureFallback',
    'viewerSkipWebgpuUseCounters',
    'viewerCacheWebgpuBindGroupLayouts',
    'viewerSkipWebgpuCommandLabels',
    'viewerSkipWebgpuResourceLabels',
    'viewerSkipWebgpuShaderSourceNullCheck',
    'viewerSkipWebgpuShaderMemoryAccounting',
    'viewerSkipWebgpuRedundantPipelineSets',
    'viewerSkipWebgpuRedundantBindGroupSets',
    'viewerSkipWebgpuRedundantBufferSets',
    'viewerSkipWebgpuRedundantRenderStateSets',
    'viewerTraceWebgpuQueue',
    'precompile',
    'settleGpuAfterWarmup',
    'disableGpuTiming',
    'queueInstrumentation',
    'commandEncoderInstrumentation',
    'bindGroupInstrumentation',
    'pipelineStateInstrumentation',
    'bufferStateInstrumentation',
    'renderStateInstrumentation',
    'immediateInstrumentation',
    'showHud',
    'unsafeFullSizeWindow',
    'allowSoftwareRendering',
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
  if (!['canvas', 'data'].includes(args.textureUploadMode)) {
    throw new Error('--textureUploadMode must be canvas or data');
  }
  if (!['off', 'static'].includes(args.webgpuBundleMode)) {
    throw new Error('--webgpuBundleMode must be off or static');
  }
  if (args.webgpuBundleMode !== 'off' && args.renderer !== 'webgpu') {
    throw new Error('--webgpuBundleMode is only supported for --renderer webgpu');
  }
  if (Number(args.pipelineQuietFrames) < 0 || Number(args.pipelineQuietMaxFrames) < 0) {
    throw new Error('--pipelineQuietFrames and --pipelineQuietMaxFrames must be non-negative');
  }
  if (Number(args.pipelineQuietFrames) > 0 && args.renderer !== 'webgpu') {
    throw new Error('--pipelineQuietFrames is only supported for --renderer webgpu');
  }
  if (args.bindGroupInstrumentation && args.renderer !== 'webgpu') {
    throw new Error('--bindGroupInstrumentation is only supported for --renderer webgpu');
  }
  if (args.commandEncoderInstrumentation && args.renderer !== 'webgpu') {
    throw new Error('--commandEncoderInstrumentation is only supported for --renderer webgpu');
  }
  if (args.pipelineStateInstrumentation && args.renderer !== 'webgpu') {
    throw new Error('--pipelineStateInstrumentation is only supported for --renderer webgpu');
  }
  if (args.bufferStateInstrumentation && args.renderer !== 'webgpu') {
    throw new Error('--bufferStateInstrumentation is only supported for --renderer webgpu');
  }
  if (args.renderStateInstrumentation && args.renderer !== 'webgpu') {
    throw new Error('--renderStateInstrumentation is only supported for --renderer webgpu');
  }
  if (args.immediateInstrumentation && args.renderer !== 'webgpu') {
    throw new Error('--immediateInstrumentation is only supported for --renderer webgpu');
  }
  return args;
}

function assertTrustedViewerExperimentGates(args) {
  const unsafeFlags = [
    ['viewerAggressiveGpu', args.viewerAggressiveGpu],
    ['viewerRelaxedWebglValidation', args.viewerRelaxedWebglValidation],
    ['viewerZeroCopy', args.viewerZeroCopy],
    ['viewerInProcessGpu', args.viewerInProcessGpu],
    ['viewerSingleProcess', args.viewerSingleProcess],
    ['viewerForceAngleBackend', Boolean(args.viewerForceAngleBackend)],
    ['viewerDisableUnneededBlinkFeatures', args.viewerDisableUnneededBlinkFeatures],
    ['viewerDirectGpuPresentation', args.viewerDirectGpuPresentation],
    ['viewerDeferWebgpuPipelineFlush', args.viewerDeferWebgpuPipelineFlush],
    ['viewerDeferWebgpuQueueFlush', args.viewerDeferWebgpuQueueFlush],
    ['viewerDeferWebgpuSubmitFlush', args.viewerDeferWebgpuSubmitFlush],
    ['viewerSkipWebgpuCanvasTextureValidation', args.viewerSkipWebgpuCanvasTextureValidation],
    ['viewerSkipWebgpuCanvasMemoryAccounting', args.viewerSkipWebgpuCanvasMemoryAccounting],
    ['viewerSkipWebgpuCopyExternalImageColorConversion', args.viewerSkipWebgpuCopyExternalImageColorConversion],
    ['viewerSkipWebgpuCopyExternalImageColorSpaceValidation', args.viewerSkipWebgpuCopyExternalImageColorSpaceValidation],
    ['viewerSkipWebgpuCopyExternalImageDestValidation', args.viewerSkipWebgpuCopyExternalImageDestValidation],
    ['viewerSkipWebgpuCopyExternalImageSourceValidation', args.viewerSkipWebgpuCopyExternalImageSourceValidation],
    ['viewerSkipWebgpuCopyExternalImageCopySizeValidation', args.viewerSkipWebgpuCopyExternalImageCopySizeValidation],
    ['viewerSkipWebgpuWriteTextureLayoutValidation', args.viewerSkipWebgpuWriteTextureLayoutValidation],
    ['viewerRejectWebgpuCpuTextureFallback', args.viewerRejectWebgpuCpuTextureFallback],
    ['viewerSkipWebgpuUseCounters', args.viewerSkipWebgpuUseCounters],
    ['viewerCacheWebgpuBindGroupLayouts', args.viewerCacheWebgpuBindGroupLayouts],
    ['viewerSkipWebgpuCommandLabels', args.viewerSkipWebgpuCommandLabels],
    ['viewerSkipWebgpuResourceLabels', args.viewerSkipWebgpuResourceLabels],
    ['viewerSkipWebgpuShaderSourceNullCheck', args.viewerSkipWebgpuShaderSourceNullCheck],
    ['viewerSkipWebgpuShaderMemoryAccounting', args.viewerSkipWebgpuShaderMemoryAccounting],
    ['viewerSkipWebgpuRedundantPipelineSets', args.viewerSkipWebgpuRedundantPipelineSets],
    ['viewerSkipWebgpuRedundantBindGroupSets', args.viewerSkipWebgpuRedundantBindGroupSets],
    ['viewerSkipWebgpuRedundantBufferSets', args.viewerSkipWebgpuRedundantBufferSets],
    ['viewerSkipWebgpuRedundantRenderStateSets', args.viewerSkipWebgpuRedundantRenderStateSets],
    ['viewerTraceWebgpuQueue', args.viewerTraceWebgpuQueue],
  ].filter(([, enabled]) => enabled).map(([flag]) => `--${flag}`);
  const unsafeBrowserFlags = args.browserFlag.filter((flag) => (
    flag === '--use-webgpu-adapter' ||
    flag.startsWith('--use-webgpu-adapter=') ||
    flag === '--enable-dawn-features' ||
    flag.startsWith('--enable-dawn-features=') ||
    flag === '--disable-dawn-features' ||
    flag.startsWith('--disable-dawn-features=') ||
    flag === '--enable-features' ||
    flag.startsWith('--enable-features=') ||
    flag === '--disable-features' ||
    flag.startsWith('--disable-features=') ||
    flag === '--enable-gpu-memory-buffer-compositor-resources' ||
    flag === '--ui-enable-zero-copy' ||
    flag === '--enable-gpu-rasterization' ||
    flag === '--disable-frame-rate-limit' ||
    flag === '--disable-gpu-vsync'
  ));
  unsafeFlags.push(...unsafeBrowserFlags);

  if (unsafeFlags.length > 0 && (!args.viewerMode || !args.viewerTrustedContent)) {
    throw new Error(`Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent: ${unsafeFlags.join(', ')}`);
  }
  if (args.viewerZeroCopy && args.renderer !== 'webgl2') {
    throw new Error('--viewerZeroCopy is currently restricted to --renderer webgl2 because WebGPU zero-copy evidence regressed.');
  }
  if (args.viewerDeferWebgpuPipelineFlush && args.renderer !== 'webgpu') {
    throw new Error('--viewerDeferWebgpuPipelineFlush is only valid with --renderer webgpu.');
  }
  if (args.viewerDeferWebgpuQueueFlush && args.renderer !== 'webgpu') {
    throw new Error('--viewerDeferWebgpuQueueFlush is only valid with --renderer webgpu.');
  }
  if (args.viewerDeferWebgpuSubmitFlush && args.renderer !== 'webgpu') {
    throw new Error('--viewerDeferWebgpuSubmitFlush is only valid with --renderer webgpu.');
  }
  if (args.viewerSkipWebgpuCanvasTextureValidation && args.renderer !== 'webgpu') {
    throw new Error('--viewerSkipWebgpuCanvasTextureValidation is only valid with --renderer webgpu.');
  }
  if (args.viewerSkipWebgpuCanvasMemoryAccounting && args.renderer !== 'webgpu') {
    throw new Error('--viewerSkipWebgpuCanvasMemoryAccounting is only valid with --renderer webgpu.');
  }
  if (args.viewerSkipWebgpuCopyExternalImageColorConversion && args.renderer !== 'webgpu') {
    throw new Error('--viewerSkipWebgpuCopyExternalImageColorConversion is only valid with --renderer webgpu.');
  }
  if (args.viewerSkipWebgpuCopyExternalImageColorSpaceValidation && args.renderer !== 'webgpu') {
    throw new Error('--viewerSkipWebgpuCopyExternalImageColorSpaceValidation is only valid with --renderer webgpu.');
  }
  if (args.viewerSkipWebgpuCopyExternalImageDestValidation && args.renderer !== 'webgpu') {
    throw new Error('--viewerSkipWebgpuCopyExternalImageDestValidation is only valid with --renderer webgpu.');
  }
  if (args.viewerSkipWebgpuCopyExternalImageSourceValidation && args.renderer !== 'webgpu') {
    throw new Error('--viewerSkipWebgpuCopyExternalImageSourceValidation is only valid with --renderer webgpu.');
  }
  if (args.viewerSkipWebgpuCopyExternalImageCopySizeValidation && args.renderer !== 'webgpu') {
    throw new Error('--viewerSkipWebgpuCopyExternalImageCopySizeValidation is only valid with --renderer webgpu.');
  }
  if (args.viewerSkipWebgpuWriteTextureLayoutValidation && args.renderer !== 'webgpu') {
    throw new Error('--viewerSkipWebgpuWriteTextureLayoutValidation is only valid with --renderer webgpu.');
  }
  if (args.viewerRejectWebgpuCpuTextureFallback && args.renderer !== 'webgpu') {
    throw new Error('--viewerRejectWebgpuCpuTextureFallback is only valid with --renderer webgpu.');
  }
  if (args.viewerSkipWebgpuUseCounters && args.renderer !== 'webgpu') {
    throw new Error('--viewerSkipWebgpuUseCounters is only valid with --renderer webgpu.');
  }
  if (args.viewerCacheWebgpuBindGroupLayouts && args.renderer !== 'webgpu') {
    throw new Error('--viewerCacheWebgpuBindGroupLayouts is only valid with --renderer webgpu.');
  }
  if (args.viewerSkipWebgpuCommandLabels && args.renderer !== 'webgpu') {
    throw new Error('--viewerSkipWebgpuCommandLabels is only valid with --renderer webgpu.');
  }
  if (args.viewerSkipWebgpuResourceLabels && args.renderer !== 'webgpu') {
    throw new Error('--viewerSkipWebgpuResourceLabels is only valid with --renderer webgpu.');
  }
  if (args.viewerSkipWebgpuShaderSourceNullCheck && args.renderer !== 'webgpu') {
    throw new Error('--viewerSkipWebgpuShaderSourceNullCheck is only valid with --renderer webgpu.');
  }
  if (args.viewerSkipWebgpuShaderMemoryAccounting && args.renderer !== 'webgpu') {
    throw new Error('--viewerSkipWebgpuShaderMemoryAccounting is only valid with --renderer webgpu.');
  }
  if (args.viewerSkipWebgpuRedundantPipelineSets && args.renderer !== 'webgpu') {
    throw new Error('--viewerSkipWebgpuRedundantPipelineSets is only valid with --renderer webgpu.');
  }
  if (args.viewerSkipWebgpuRedundantBindGroupSets && args.renderer !== 'webgpu') {
    throw new Error('--viewerSkipWebgpuRedundantBindGroupSets is only valid with --renderer webgpu.');
  }
  if (args.viewerSkipWebgpuRedundantBufferSets && args.renderer !== 'webgpu') {
    throw new Error('--viewerSkipWebgpuRedundantBufferSets is only valid with --renderer webgpu.');
  }
  if (args.viewerSkipWebgpuRedundantRenderStateSets && args.renderer !== 'webgpu') {
    throw new Error('--viewerSkipWebgpuRedundantRenderStateSets is only valid with --renderer webgpu.');
  }
  if (args.viewerTraceWebgpuQueue && args.renderer !== 'webgpu') {
    throw new Error('--viewerTraceWebgpuQueue is only valid with --renderer webgpu.');
  }
}

function ensureFile(file, label) {
  if (!file || !fs.existsSync(file)) throw new Error(`${label} not found: ${file}`);
}

function hasSwitch(flags, name) {
  return flags.some((flag) => flag === name || flag.startsWith(`${name}=`));
}

function pushDefaultFlag(flags, extraFlags, flag) {
  const name = flag.split('=')[0];
  if (!hasSwitch(flags, name) && !hasSwitch(extraFlags, name)) {
    flags.push(flag);
  }
}

function addSafeDesktopFlags(flags, extraFlags) {
  pushDefaultFlag(flags, extraFlags, '--force-high-performance-gpu');
  pushDefaultFlag(flags, extraFlags, '--window-size=640,480');
  pushDefaultFlag(flags, extraFlags, '--window-position=40,40');
  pushDefaultFlag(flags, extraFlags, '--force-device-scale-factor=1');
}

function softwareRendererReason(metadata) {
  const haystack = [
    metadata?.gpu_name,
    metadata?.driver_version,
    metadata?.angle_backend,
  ]
    .filter((value) => typeof value === 'string')
    .join(' ')
    .toLowerCase();

  if (!haystack) return '';

  const patterns = [
    ['swiftshader', 'SwiftShader'],
    ['llvmpipe', 'llvmpipe'],
    ['softpipe', 'softpipe'],
    ['software rasterizer', 'software rasterizer'],
    ['software renderer', 'software renderer'],
    ['microsoft basic render driver', 'Microsoft Basic Render Driver'],
    ['microsoft basic renderer', 'Microsoft Basic Renderer'],
    ['warp', 'WARP'],
  ];

  const match = patterns.find(([pattern]) => haystack.includes(pattern));
  return match ? match[1] : '';
}

function gpuMetadataFromSystemInfo(systemInfo, angleBackend = null) {
  const gpuDevice = systemInfo?.gpu?.devices?.[0] || null;
  return {
    gpu_name: gpuDevice?.deviceString || null,
    driver_version: gpuDevice?.driverVendor || gpuDevice?.driverVersion || null,
    angle_backend: angleBackend,
  };
}

function assertNoSoftwareRenderer(metadata, context, allowSoftwareRendering) {
  const reason = softwareRendererReason(metadata);
  if (!reason || allowSoftwareRendering) return;

  throw new Error(
    `${context} reported software-rendered GPU path (${reason}). ` +
    'Trace evidence must use hardware GPU acceleration; rerun after fixing the driver/GPU path, ' +
    'or pass --allowSoftwareRendering only for diagnostic failure-mode traces that will not be retained as speed evidence.',
  );
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
  let lastError = null;
  while (Date.now() - start < timeoutMs) {
    try {
      const targets = await waitForJson(`http://127.0.0.1:${debugPort}/json/list`, 5000);
      const page = targets.find((target) => target.type === 'page' && target.webSocketDebuggerUrl);
      if (page) return page;
    } catch (error) {
      lastError = error;
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw lastError || new Error('Timed out waiting for a debuggable page target.');
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

function flagValues(flags, switchName) {
  const values = [];
  const prefix = `${switchName}=`;
  for (let index = 0; index < flags.length; index += 1) {
    const flag = flags[index];
    if (flag === switchName && index + 1 < flags.length) {
      values.push(flags[index + 1]);
      index += 1;
    } else if (flag.startsWith(prefix)) {
      values.push(flag.slice(prefix.length));
    }
  }
  return values;
}

function flagTokenListIncludes(flags, switchName, token) {
  return flagValues(flags, switchName).some((value) => value.split(',').some((part) => {
    const normalized = part.trim().split(':', 1)[0];
    return normalized === token;
  }));
}

function viewerUrlMetadata(viewerUrl) {
  const url = new URL(viewerUrl);
  return {
    viewer_url: viewerUrl,
    viewer_url_scheme: url.protocol.replace(/:$/, ''),
    viewer_origin: url.origin === 'null' ? null : url.origin,
  };
}

function webGpuBlobCacheMetadata(args, viewerUrl) {
  const launch = viewerUrlMetadata(viewerUrl);
  const originEligible =
    args.renderer === 'webgpu' &&
    (launch.viewer_url_scheme === 'http' || launch.viewer_url_scheme === 'https') &&
    Boolean(launch.viewer_origin);
  const explicitDisable = flagTokenListIncludes(args.browserFlag, '--enable-dawn-features', 'disable_blob_cache');
  const hashValidationDisabled =
    flagTokenListIncludes(args.browserFlag, '--disable-dawn-features', 'blob_cache_hash_validation');
  const expectedAvailable = originEligible && !explicitDisable;
  let reason = 'not-webgpu';
  if (args.renderer === 'webgpu') {
    if (!originEligible) {
      reason = `viewer-url-scheme-${launch.viewer_url_scheme}`;
    } else if (explicitDisable) {
      reason = 'dawn-disable_blob_cache-toggle';
    } else {
      reason = 'local-http-origin';
    }
  }
  return {
    ...launch,
    webgpu_blob_cache_origin_eligible: originEligible,
    webgpu_blob_cache_disabled_by_explicit_toggle: explicitDisable,
    webgpu_blob_cache_expected_available: expectedAvailable,
    webgpu_blob_cache_hash_validation_disabled: hashValidationDisabled,
    webgpu_blob_cache_eligibility_reason: reason,
  };
}

function assertWebGpuBlobCacheExperimentEligible(metadata, args) {
  if (
    args.renderer === 'webgpu' &&
    metadata.webgpu_blob_cache_hash_validation_disabled &&
    !metadata.webgpu_blob_cache_expected_available
  ) {
    throw new Error(
      'WebGPU blob-cache hash-validation experiments require a cache-eligible local HTTP(S) viewer origin and must not enable Dawn disable_blob_cache. ' +
      `Current cache eligibility: ${metadata.webgpu_blob_cache_eligibility_reason}.`
    );
  }
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

function assertFiniteTraceNumber(value, name, { allowZero = false } = {}) {
  if (!Number.isFinite(value) || value < 0 || (!allowZero && value === 0)) {
    const qualifier = allowZero ? 'a non-negative finite number' : 'a positive finite number';
    throw new Error(`--${name} must be ${qualifier}`);
  }
}

function assertNonNegativeIntegerTraceNumber(value, name) {
  if (!Number.isInteger(value) || value < 0) {
    throw new Error(`--${name} must be a non-negative integer`);
  }
}

const webGpuFastPathCoverageFields = [
  'webgpu_queue_write_texture_common_layout_count',
  'webgpu_queue_write_texture_common_extent_count',
  'webgpu_queue_copy_external_image_default_origin_count',
  'webgpu_queue_copy_external_image_common_origin_count',
  'webgpu_queue_copy_external_image_explicit_common_origin_count',
  'webgpu_queue_copy_external_image_srgb_destination_count',
  'webgpu_queue_copy_external_image_full_source_count',
  'webgpu_pipeline_descriptor_stack_fast_path_eligible_count',
  'webgpu_pipeline_descriptor_measured_stack_fast_path_eligible_count',
];

function webGpuFastPathCoverageMetadata(benchmarkResult) {
  const metadata = {};
  for (const field of webGpuFastPathCoverageFields) {
    metadata[field] = Number.isFinite(benchmarkResult?.[field])
      ? benchmarkResult[field]
      : null;
  }
  return metadata;
}

async function main() {
  const args = parseArgs(process.argv);
  assertTrustedViewerExperimentGates(args);
  const browser = path.resolve(args.browser);
  const viewerDir = path.resolve(args.viewerDir);
  const complexity = Number(args.complexity);
  const duration = Number(args.duration);
  const warmup = Number(args.warmup);
  const startDelayMs = Number(args.startDelayMs);
  const prerenderFrames = Number(args.prerenderFrames);
  const pipelineQuietFrames = Number(args.pipelineQuietFrames);
  const pipelineQuietMaxFrames = Number(args.pipelineQuietMaxFrames);
  assertFiniteTraceNumber(complexity, 'complexity');
  assertFiniteTraceNumber(duration, 'duration');
  assertFiniteTraceNumber(warmup, 'warmup', { allowZero: true });
  assertFiniteTraceNumber(startDelayMs, 'startDelayMs', { allowZero: true });
  assertNonNegativeIntegerTraceNumber(prerenderFrames, 'prerenderFrames');
  assertNonNegativeIntegerTraceNumber(pipelineQuietFrames, 'pipelineQuietFrames');
  assertNonNegativeIntegerTraceNumber(pipelineQuietMaxFrames, 'pipelineQuietMaxFrames');
  if (pipelineQuietFrames > 0 && pipelineQuietMaxFrames < pipelineQuietFrames) {
    throw new Error('--pipelineQuietMaxFrames must be greater than or equal to --pipelineQuietFrames when pipeline-quiet warmup is enabled');
  }
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
    complexity: String(complexity),
    duration: String(duration),
    warmup: String(warmup),
    startDelayMs: String(startDelayMs),
    gpuTiming: args.disableGpuTiming ? '0' : '1',
    textureUploadMode: args.textureUploadMode,
    webgpuBundleMode: args.webgpuBundleMode,
    queueInstrumentation: args.queueInstrumentation ? '1' : '0',
    commandEncoderInstrumentation: args.commandEncoderInstrumentation ? '1' : '0',
    bindGroupInstrumentation: args.bindGroupInstrumentation ? '1' : '0',
    pipelineStateInstrumentation: args.pipelineStateInstrumentation ? '1' : '0',
    bufferStateInstrumentation: args.bufferStateInstrumentation ? '1' : '0',
    renderStateInstrumentation: args.renderStateInstrumentation ? '1' : '0',
    immediateInstrumentation: args.immediateInstrumentation ? '1' : '0',
    showHud: args.showHud ? '1' : '0',
    precompile: args.precompile ? '1' : '0',
    prerenderFrames: String(prerenderFrames),
    settleGpuAfterWarmup: args.settleGpuAfterWarmup ? '1' : '0',
    pipelineQuietFrames: String(pipelineQuietFrames),
    pipelineQuietMaxFrames: String(pipelineQuietMaxFrames),
  });
  const viewerUrl = `http://127.0.0.1:${viewerPort}/?${query.toString()}`;
  const launchMetadata = webGpuBlobCacheMetadata(args, viewerUrl);
  assertWebGpuBlobCacheExperimentEligible(launchMetadata, args);
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
  if (!args.unsafeFullSizeWindow) {
    addSafeDesktopFlags(browserArgs, args.browserFlag);
  }
  if (args.viewerMode) {
    browserArgs.push(`--viewer-app-url=${viewerUrl}`);
    browserArgs.push('--viewer-block-external-navigation');
  }
  if (args.viewerTrustedContent) browserArgs.push('--viewer-trusted-content');
  if (args.viewerAggressiveGpu) browserArgs.push('--viewer-aggressive-gpu');
  if (args.viewerRelaxedWebglValidation) browserArgs.push('--viewer-relaxed-webgl-validation');
  if (args.viewerZeroCopy) browserArgs.push('--viewer-zero-copy');
  if (args.viewerInProcessGpu) browserArgs.push('--viewer-in-process-gpu');
  if (args.viewerSingleProcess) browserArgs.push('--viewer-single-process');
  if (args.viewerForceAngleBackend) browserArgs.push(`--viewer-force-angle-backend=${args.viewerForceAngleBackend}`);
  if (args.viewerDisableUnneededBlinkFeatures) browserArgs.push('--viewer-disable-unneeded-blink-features');
  if (args.viewerDirectGpuPresentation) browserArgs.push('--viewer-direct-gpu-presentation');
  if (args.viewerDeferWebgpuPipelineFlush) browserArgs.push('--viewer-defer-webgpu-pipeline-flush');
  if (args.viewerDeferWebgpuQueueFlush) browserArgs.push('--viewer-defer-webgpu-queue-flush');
  if (args.viewerDeferWebgpuSubmitFlush) browserArgs.push('--viewer-defer-webgpu-submit-flush');
  if (args.viewerSkipWebgpuCanvasTextureValidation) browserArgs.push('--viewer-skip-webgpu-canvas-texture-validation');
  if (args.viewerSkipWebgpuCanvasMemoryAccounting) browserArgs.push('--viewer-skip-webgpu-canvas-memory-accounting');
  if (args.viewerSkipWebgpuCopyExternalImageColorConversion) browserArgs.push('--viewer-skip-webgpu-copy-external-image-color-conversion');
  if (args.viewerSkipWebgpuCopyExternalImageColorSpaceValidation) browserArgs.push('--viewer-skip-webgpu-copy-external-image-color-space-validation');
  if (args.viewerSkipWebgpuCopyExternalImageDestValidation) browserArgs.push('--viewer-skip-webgpu-copy-external-image-dest-validation');
  if (args.viewerSkipWebgpuCopyExternalImageSourceValidation) browserArgs.push('--viewer-skip-webgpu-copy-external-image-source-validation');
  if (args.viewerSkipWebgpuCopyExternalImageCopySizeValidation) browserArgs.push('--viewer-skip-webgpu-copy-external-image-copy-size-validation');
  if (args.viewerSkipWebgpuWriteTextureLayoutValidation) browserArgs.push('--viewer-skip-webgpu-write-texture-layout-validation');
  if (args.viewerRejectWebgpuCpuTextureFallback) browserArgs.push('--viewer-reject-webgpu-cpu-texture-fallback');
  if (args.viewerSkipWebgpuUseCounters) browserArgs.push('--viewer-skip-webgpu-use-counters');
  if (args.viewerCacheWebgpuBindGroupLayouts) browserArgs.push('--viewer-cache-webgpu-bind-group-layouts');
  if (args.viewerSkipWebgpuCommandLabels) browserArgs.push('--viewer-skip-webgpu-command-labels');
  if (args.viewerSkipWebgpuResourceLabels) browserArgs.push('--viewer-skip-webgpu-resource-labels');
  if (args.viewerSkipWebgpuShaderSourceNullCheck) browserArgs.push('--viewer-skip-webgpu-shader-source-null-check');
  if (args.viewerSkipWebgpuShaderMemoryAccounting) browserArgs.push('--viewer-skip-webgpu-shader-memory-accounting');
  if (args.viewerSkipWebgpuRedundantPipelineSets) browserArgs.push('--viewer-skip-webgpu-redundant-pipeline-sets');
  if (args.viewerSkipWebgpuRedundantBindGroupSets) browserArgs.push('--viewer-skip-webgpu-redundant-bind-group-sets');
  if (args.viewerSkipWebgpuRedundantBufferSets) browserArgs.push('--viewer-skip-webgpu-redundant-buffer-sets');
  if (args.viewerSkipWebgpuRedundantRenderStateSets) browserArgs.push('--viewer-skip-webgpu-redundant-render-state-sets');
  if (args.viewerTraceWebgpuQueue) browserArgs.push('--viewer-trace-webgpu-queue');
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
    const launchGpuMetadata = gpuMetadataFromSystemInfo(
      await cdp.send('SystemInfo.getInfo').catch(() => null),
      args.viewerForceAngleBackend || null,
    );
    assertNoSoftwareRenderer(
      launchGpuMetadata,
      'Hardware-GPU trace launch preflight',
      args.allowSoftwareRendering,
    );
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

    const timeoutMs = Math.max(60000, (duration + warmup + 45) * 1000);
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
    assertNoSoftwareRenderer(benchmarkResult, 'Trace benchmark result', args.allowSoftwareRendering);

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
      gpu_name: launchGpuMetadata.gpu_name,
      driver_version: launchGpuMetadata.driver_version,
      angle_backend: launchGpuMetadata.angle_backend,
      scene: args.scene,
      renderer: args.renderer,
      complexity,
      duration_seconds: duration,
      warmup_seconds: warmup,
      start_delay_ms: startDelayMs,
      gpu_timing_enabled: !args.disableGpuTiming,
      texture_upload_mode: args.textureUploadMode,
      webgpu_bundle_mode: args.webgpuBundleMode,
      webgpu_bundle_groups: benchmarkResult.webgpu_bundle_groups ?? 0,
      webgpu_queue_instrumentation_enabled: args.queueInstrumentation,
      webgpu_command_encoder_instrumentation_enabled: args.commandEncoderInstrumentation,
      webgpu_bind_group_instrumentation_enabled: args.bindGroupInstrumentation,
      webgpu_pipeline_state_instrumentation_enabled: args.pipelineStateInstrumentation,
      webgpu_buffer_state_instrumentation_enabled: args.bufferStateInstrumentation,
      webgpu_render_state_instrumentation_enabled: args.renderStateInstrumentation,
      webgpu_immediate_instrumentation_enabled: args.immediateInstrumentation,
      benchmark_hud_enabled: args.showHud,
      allow_software_rendering: args.allowSoftwareRendering,
      resource_warmup_enabled: args.precompile || prerenderFrames > 0 || args.settleGpuAfterWarmup || pipelineQuietFrames > 0,
      resource_warmup_precompile: args.precompile,
      resource_warmup_prerender_frames: prerenderFrames,
      resource_warmup_settle_gpu: args.settleGpuAfterWarmup,
      resource_warmup_pipeline_quiet_frames: pipelineQuietFrames,
      resource_warmup_pipeline_quiet_max_frames: pipelineQuietFrames > 0
        ? pipelineQuietMaxFrames
        : 0,
      viewer_mode: args.viewerMode,
      viewer_block_external_navigation: args.viewerMode,
      viewer_trusted_content: args.viewerTrustedContent,
      viewer_aggressive_gpu: args.viewerAggressiveGpu,
      viewer_relaxed_webgl_validation: args.viewerRelaxedWebglValidation,
      viewer_zero_copy: args.viewerZeroCopy,
      viewer_in_process_gpu: args.viewerInProcessGpu,
      viewer_single_process: args.viewerSingleProcess,
      viewer_force_angle_backend: args.viewerForceAngleBackend || null,
      requested_angle_backend: args.viewerForceAngleBackend || null,
      viewer_disable_unneeded_blink_features: args.viewerDisableUnneededBlinkFeatures,
      viewer_direct_gpu_presentation: args.viewerDirectGpuPresentation,
      viewer_defer_webgpu_pipeline_flush: args.viewerDeferWebgpuPipelineFlush,
      viewer_defer_webgpu_queue_flush: args.viewerDeferWebgpuQueueFlush,
      viewer_defer_webgpu_submit_flush: args.viewerDeferWebgpuSubmitFlush,
      viewer_skip_webgpu_canvas_texture_validation: args.viewerSkipWebgpuCanvasTextureValidation,
      viewer_skip_webgpu_canvas_memory_accounting: args.viewerSkipWebgpuCanvasMemoryAccounting,
      viewer_skip_webgpu_copy_external_image_color_conversion: args.viewerSkipWebgpuCopyExternalImageColorConversion,
      viewer_skip_webgpu_copy_external_image_color_space_validation: args.viewerSkipWebgpuCopyExternalImageColorSpaceValidation,
      viewer_skip_webgpu_copy_external_image_dest_validation: args.viewerSkipWebgpuCopyExternalImageDestValidation,
      viewer_skip_webgpu_copy_external_image_source_validation: args.viewerSkipWebgpuCopyExternalImageSourceValidation,
      viewer_skip_webgpu_copy_external_image_copy_size_validation: args.viewerSkipWebgpuCopyExternalImageCopySizeValidation,
      viewer_skip_webgpu_write_texture_layout_validation: args.viewerSkipWebgpuWriteTextureLayoutValidation,
      viewer_reject_webgpu_cpu_texture_fallback: args.viewerRejectWebgpuCpuTextureFallback,
      viewer_skip_webgpu_use_counters: args.viewerSkipWebgpuUseCounters,
      viewer_cache_webgpu_bind_group_layouts: args.viewerCacheWebgpuBindGroupLayouts,
      viewer_skip_webgpu_command_labels: args.viewerSkipWebgpuCommandLabels,
      viewer_skip_webgpu_resource_labels: args.viewerSkipWebgpuResourceLabels,
      viewer_skip_webgpu_shader_source_null_check: args.viewerSkipWebgpuShaderSourceNullCheck,
      viewer_skip_webgpu_shader_memory_accounting: args.viewerSkipWebgpuShaderMemoryAccounting,
      viewer_skip_webgpu_redundant_pipeline_sets: args.viewerSkipWebgpuRedundantPipelineSets,
      viewer_skip_webgpu_redundant_bind_group_sets: args.viewerSkipWebgpuRedundantBindGroupSets,
      viewer_skip_webgpu_redundant_buffer_sets: args.viewerSkipWebgpuRedundantBufferSets,
      viewer_skip_webgpu_redundant_render_state_sets: args.viewerSkipWebgpuRedundantRenderStateSets,
      viewer_trace_webgpu_queue: args.viewerTraceWebgpuQueue,
      ...launchMetadata,
      ...webGpuFastPathCoverageMetadata(benchmarkResult),
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
