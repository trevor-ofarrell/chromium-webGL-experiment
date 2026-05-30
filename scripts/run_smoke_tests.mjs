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
    viewerDir: path.join(rootDir, 'viewer', 'dist'),
    output: path.join(rootDir, 'benchmarks', 'raw', 'smoke-tests.json'),
    duration: '2',
    warmup: '1',
    requireWebGPU: false,
    viewerMode: false,
    viewerTrustedContent: false,
    browserFlag: [],
    unsafeFullSizeWindow: false,
    allowSoftwareRendering: false,
  };
  const booleanArgs = new Set([
    'requireWebGPU',
    'viewerMode',
    'viewerTrustedContent',
    'unsafeFullSizeWindow',
    'allowSoftwareRendering',
  ]);

  for (let i = 2; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token.startsWith('--')) {
      throw new Error(`Unexpected positional argument: ${token}`);
    }
    const key = token.slice(2);
    if (key === 'browser-flag') {
      args.browserFlag.push(argv[++i]);
    } else if (key === 'require-webgpu') {
      args.requireWebGPU = true;
    } else if (booleanArgs.has(key)) {
      args[key] = true;
    } else if (key in args) {
      args[key] = argv[++i];
    } else {
      throw new Error(`Unknown argument: ${token}`);
    }
  }

  if (!args.browser) {
    throw new Error('Usage: node scripts/run_smoke_tests.mjs --browser <browser.exe> [--output result.json]');
  }

  return args;
}

function ensureFile(file, label) {
  if (!file || !fs.existsSync(file)) {
    throw new Error(`${label} not found: ${file}`);
  }
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

function gpuMetadataFromSystemInfo(systemInfo) {
  const gpuDevice = systemInfo?.gpu?.devices?.[0] || null;
  return {
    gpu_name: gpuDevice?.deviceString || null,
    driver_version: gpuDevice?.driverVendor || gpuDevice?.driverVersion || null,
    angle_backend: null,
  };
}

function assertNoSoftwareRenderer(metadata, context, allowSoftwareRendering) {
  const reason = softwareRendererReason(metadata);
  if (!reason || allowSoftwareRendering) return;

  throw new Error(
    `${context} reported software-rendered GPU path (${reason}). ` +
    'Smoke evidence must use hardware GPU acceleration; rerun after fixing the driver/GPU path, ' +
    'or pass --allowSoftwareRendering only for diagnostic failure-mode smoke runs.',
  );
}

function commandText(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: options.cwd || rootDir,
    encoding: 'utf8',
    shell: false,
    timeout: options.timeoutMs || 5000,
    windowsHide: true,
  });
  if (result.status !== 0) return '';
  return result.stdout.trim();
}

function getBrowserVersion(browser) {
  return commandText(browser, ['--version'], { timeoutMs: 5000 }) || null;
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

function mimeType(file) {
  const extension = path.extname(file).toLowerCase();
  if (extension === '.html') return 'text/html; charset=utf-8';
  if (extension === '.js') return 'text/javascript; charset=utf-8';
  if (extension === '.css') return 'text/css; charset=utf-8';
  if (extension === '.svg') return 'image/svg+xml';
  if (extension === '.png') return 'image/png';
  if (extension === '.json') return 'application/json; charset=utf-8';
  return 'application/octet-stream';
}

function startSmokeServer(viewerDir) {
  const staticRoot = path.resolve(viewerDir);
  const threeBuildRoot = path.join(rootDir, 'viewer', 'node_modules', 'three', 'build');
  const threeModule = path.join(threeBuildRoot, 'three.module.js');
  ensureFile(path.join(staticRoot, 'index.html'), 'Built viewer index');
  ensureFile(threeModule, 'Three.js module');

  const server = http.createServer((req, res) => {
    const url = new URL(req.url || '/', 'http://127.0.0.1');
    if (url.pathname === '/__smoke.html') {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
      res.end('<!doctype html><meta charset="utf-8"><title>viewer smoke</title><body></body>');
      return;
    }

    if (url.pathname.startsWith('/__three/')) {
      const relative = decodeURIComponent(url.pathname.slice('/__three/'.length));
      const resolved = path.resolve(threeBuildRoot, relative);
      const resolvedRelative = path.relative(threeBuildRoot, resolved);
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
        res.writeHead(200, { 'Content-Type': mimeType(resolved), 'Cache-Control': 'no-store' });
        res.end(data);
      });
      return;
    }

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
      res.writeHead(200, { 'Content-Type': mimeType(resolved), 'Cache-Control': 'no-store' });
      res.end(data);
    });
  });

  return server;
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

async function evaluateTest(cdp, name, source, options = {}) {
  const startedAt = Date.now();
  try {
    const result = await cdp.send('Runtime.evaluate', {
      expression: `(${source})()`,
      awaitPromise: true,
      returnByValue: true,
      timeout: options.timeoutMs || 30000,
    });

    if (result.exceptionDetails) {
      throw new Error(result.exceptionDetails.text || 'Runtime exception');
    }

    const details = result.result?.value || {};
    if (details.smoke_status === 'skip') {
      return {
        name,
        status: options.allowSkip ? 'skip' : 'fail',
        duration_ms: Date.now() - startedAt,
        details,
      };
    }

    return {
      name,
      status: 'pass',
      duration_ms: Date.now() - startedAt,
      details,
    };
  } catch (error) {
    return {
      name,
      status: 'fail',
      duration_ms: Date.now() - startedAt,
      error: error.message,
    };
  }
}

async function runBenchmarkSmoke(cdp, url, child, duration, warmup) {
  const startedAt = Date.now();
  let benchmarkResult = null;
  const consoleErrors = [];

  cdp.on('Runtime.consoleAPICalled', (params) => {
    const values = consoleArgs(params);
    const parsedResult = parseBenchmarkConsoleResult(values);
    if (parsedResult) {
      benchmarkResult = parsedResult;
    } else if (params.type === 'error') {
      consoleErrors.push(values.join(' '));
    }
  });

  const targetUrl = `${url}/?${new URLSearchParams({
    benchmark: '1',
    scene: 'many-draw-calls',
    renderer: 'webgl2',
    duration: String(duration),
    warmup: String(warmup),
  }).toString()}`;

  await cdp.send('Page.navigate', { url: targetUrl });
  const timeoutMs = Math.max(30000, (Number(duration) + Number(warmup) + 20) * 1000);
  const start = Date.now();
  while (!benchmarkResult && Date.now() - start < timeoutMs) {
    if (child.exitCode !== null) {
      return {
        name: 'benchmark_run',
        status: 'fail',
        duration_ms: Date.now() - startedAt,
        error: `Browser exited before benchmark result with code ${child.exitCode}`,
      };
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
  }

  if (!benchmarkResult) {
    return {
      name: 'benchmark_run',
      status: 'fail',
      duration_ms: Date.now() - startedAt,
      error: `Timed out waiting for benchmark result. Console errors: ${consoleErrors.join('\n')}`,
    };
  }

  return {
    name: 'benchmark_run',
    status: 'pass',
    duration_ms: Date.now() - startedAt,
    details: {
      scene_name: benchmarkResult.scene_name,
      renderer_type: benchmarkResult.renderer_type,
      avg_fps: benchmarkResult.avg_fps,
      frame_count: benchmarkResult.frame_times_ms?.length || 0,
      startup_ms_to_first_frame: benchmarkResult.startup_ms_to_first_frame,
    },
  };
}

const smokeTests = [
  {
    name: 'viewer_launch',
    source: async function viewerLaunch() {
      const iframe = document.createElement('iframe');
      iframe.width = '96';
      iframe.height = '96';
      iframe.src = '/';
      document.body.appendChild(iframe);
      await new Promise((resolve, reject) => {
        iframe.addEventListener('load', resolve, { once: true });
        iframe.addEventListener('error', () => reject(new Error('viewer iframe failed to load')), { once: true });
        setTimeout(() => reject(new Error('viewer iframe load timed out')), 10000);
      });
      const canvas = iframe.contentDocument?.querySelector('#viewer');
      const hud = iframe.contentDocument?.querySelector('#hud');
      const scriptCount = iframe.contentDocument?.querySelectorAll('script[type="module"]').length || 0;
      iframe.remove();
      if (!canvas) throw new Error('viewer canvas not found');
      return { canvas: true, hud: Boolean(hud), module_scripts: scriptCount };
    },
  },
  {
    name: 'webgl2_context',
    source: async function webgl2Context() {
      const canvas = document.createElement('canvas');
      const gl = canvas.getContext('webgl2', { antialias: false, alpha: false });
      if (!gl) throw new Error('WebGL2 context creation failed');
      const debugInfo = gl.getExtension('WEBGL_debug_renderer_info');
      return {
        version: gl.getParameter(gl.VERSION),
        vendor: debugInfo ? gl.getParameter(debugInfo.UNMASKED_VENDOR_WEBGL) : null,
        renderer: debugInfo ? gl.getParameter(debugInfo.UNMASKED_RENDERER_WEBGL) : null,
      };
    },
  },
  {
    name: 'web_platform_basics',
    source: async function webPlatformBasics() {
      if (typeof requestAnimationFrame !== 'function') {
        throw new Error('requestAnimationFrame unavailable');
      }
      if (!performance || typeof performance.now !== 'function') {
        throw new Error('performance.now unavailable');
      }

      const canvas = document.createElement('canvas');
      canvas.width = 32;
      canvas.height = 32;
      const context = canvas.getContext('2d');
      if (!context) throw new Error('Canvas 2D context creation failed');
      context.fillStyle = '#0f0';
      context.fillRect(0, 0, 32, 32);

      const before = performance.now();
      const frameTime = await new Promise((resolve) => {
        requestAnimationFrame((timestamp) => resolve(timestamp));
      });
      const after = performance.now();
      if (after < before) throw new Error('performance.now moved backwards');
      if (typeof frameTime !== 'number' || !Number.isFinite(frameTime)) {
        throw new Error('requestAnimationFrame timestamp was not finite');
      }

      const response = await fetch('/assets/checker.svg', { cache: 'no-store' });
      if (!response.ok) throw new Error(`local fetch failed with HTTP ${response.status}`);
      const text = await response.text();
      if (!text.includes('<svg')) throw new Error('local fetch did not return SVG content');

      return {
        canvas_2d: true,
        raf_timestamp_ms: frameTime,
        performance_delta_ms: after - before,
        fetch_content_type: response.headers.get('content-type') || null,
        fetch_bytes: text.length,
      };
    },
  },
  {
    name: 'basic_input_events',
    source: async function basicInputEvents() {
      const canvas = document.createElement('canvas');
      canvas.width = 96;
      canvas.height = 64;
      canvas.tabIndex = 0;
      document.body.appendChild(canvas);

      const seen = [];
      for (const type of ['pointerdown', 'pointermove', 'pointerup', 'wheel', 'keydown']) {
        canvas.addEventListener(type, (event) => {
          seen.push({
            type,
            clientX: 'clientX' in event ? event.clientX : null,
            clientY: 'clientY' in event ? event.clientY : null,
            deltaY: 'deltaY' in event ? event.deltaY : null,
            key: 'key' in event ? event.key : null,
          });
        });
      }

      const PointerEventCtor = typeof PointerEvent === 'function' ? PointerEvent : MouseEvent;
      canvas.dispatchEvent(new PointerEventCtor('pointerdown', {
        bubbles: true,
        clientX: 12,
        clientY: 16,
        pointerId: 1,
        pointerType: 'mouse',
      }));
      canvas.dispatchEvent(new PointerEventCtor('pointermove', {
        bubbles: true,
        clientX: 28,
        clientY: 24,
        pointerId: 1,
        pointerType: 'mouse',
      }));
      canvas.dispatchEvent(new PointerEventCtor('pointerup', {
        bubbles: true,
        clientX: 28,
        clientY: 24,
        pointerId: 1,
        pointerType: 'mouse',
      }));
      canvas.dispatchEvent(new WheelEvent('wheel', {
        bubbles: true,
        cancelable: true,
        deltaY: 42,
      }));
      canvas.dispatchEvent(new KeyboardEvent('keydown', {
        bubbles: true,
        key: 'ArrowLeft',
        code: 'ArrowLeft',
      }));

      canvas.remove();
      const eventTypes = seen.map((event) => event.type);
      for (const type of ['pointerdown', 'pointermove', 'pointerup', 'wheel', 'keydown']) {
        if (!eventTypes.includes(type)) throw new Error(`Missing ${type} event`);
      }
      return {
        events: eventTypes,
        pointer_event_constructor: typeof PointerEvent === 'function',
        wheel_delta_y: seen.find((event) => event.type === 'wheel')?.deltaY ?? null,
        key: seen.find((event) => event.type === 'keydown')?.key ?? null,
      };
    },
  },
  {
    name: 'webgl_context_loss_event',
    source: async function webglContextLossEvent() {
      const canvas = document.createElement('canvas');
      const gl = canvas.getContext('webgl2', { antialias: false, alpha: false });
      if (!gl) throw new Error('WebGL2 context creation failed');
      const loseContext = gl.getExtension('WEBGL_lose_context');
      if (!loseContext) {
        return { smoke_status: 'skip', reason: 'WEBGL_lose_context unavailable' };
      }

      let lost = 0;
      let restored = 0;
      canvas.addEventListener('webglcontextlost', (event) => {
        event.preventDefault();
        lost += 1;
      });
      canvas.addEventListener('webglcontextrestored', () => {
        restored += 1;
      });

      loseContext.loseContext();
      await new Promise((resolve) => setTimeout(resolve, 100));
      loseContext.restoreContext();
      await new Promise((resolve) => setTimeout(resolve, 300));
      if (lost !== 1) throw new Error(`Expected one context lost event, saw ${lost}`);
      return { lost, restored };
    },
    allowSkip: true,
  },
  {
    name: 'webgpu_adapter_device',
    allowSkip: true,
    requiresWebGPU: true,
    source: async function webgpuAdapterDevice() {
      if (!navigator.gpu) {
        return { smoke_status: 'skip', reason: 'navigator.gpu unavailable' };
      }
      const adapter = await navigator.gpu.requestAdapter();
      if (!adapter) {
        return { smoke_status: 'skip', reason: 'requestAdapter returned null' };
      }
      const device = await adapter.requestDevice();
      const details = {
        features: Array.from(adapter.features || []).sort(),
        max_texture_dimension_2d: device.limits?.maxTextureDimension2D || null,
      };
      device.destroy?.();
      return details;
    },
  },
  {
    name: 'webgpu_device_loss_signal',
    allowSkip: true,
    requiresWebGPU: true,
    source: async function webgpuDeviceLossSignal() {
      if (!navigator.gpu) {
        return { smoke_status: 'skip', reason: 'navigator.gpu unavailable' };
      }
      const adapter = await navigator.gpu.requestAdapter();
      if (!adapter) {
        return { smoke_status: 'skip', reason: 'requestAdapter returned null' };
      }
      const device = await adapter.requestDevice();
      const lostPromise = device.lost.then((info) => ({
        reason: info.reason || null,
        message: info.message || null,
      }));
      device.destroy();
      const info = await Promise.race([
        lostPromise,
        new Promise((resolve) => setTimeout(() => resolve(null), 3000)),
      ]);
      if (!info) throw new Error('Timed out waiting for GPUDevice.lost after destroy');
      return info;
    },
  },
  {
    name: 'three_webgpu_render',
    allowSkip: true,
    requiresWebGPU: true,
    source: async function threeWebgpuRender() {
      if (!navigator.gpu) {
        return { smoke_status: 'skip', reason: 'navigator.gpu unavailable' };
      }
      const adapter = await navigator.gpu.requestAdapter();
      if (!adapter) {
        return { smoke_status: 'skip', reason: 'requestAdapter returned null' };
      }

      const THREE = await import('/__three/three.webgpu.js');
      const canvas = document.createElement('canvas');
      canvas.width = 64;
      canvas.height = 64;
      document.body.appendChild(canvas);
      const renderer = new THREE.WebGPURenderer({
        canvas,
        antialias: false,
        alpha: false,
        powerPreference: 'high-performance',
      });
      renderer.setSize(64, 64, false);
      await renderer.init?.();

      const scene = new THREE.Scene();
      const camera = new THREE.PerspectiveCamera(70, 1, 0.1, 10);
      camera.position.z = 2;
      const geometry = new THREE.BoxGeometry(1.4, 1.4, 1.4);
      const material = new THREE.MeshBasicMaterial({ color: 0x00ff00 });
      scene.add(new THREE.Mesh(geometry, material));

      const startedAt = performance.now();
      renderer.render(scene, camera);
      await renderer.backend?.device?.queue?.onSubmittedWorkDone?.();
      await new Promise((resolve) => requestAnimationFrame(resolve));
      const renderMs = performance.now() - startedAt;

      const details = {
        is_webgpu_renderer: renderer.isWebGPURenderer === true,
        backend: renderer.backend?.constructor?.name || null,
        render_ms: renderMs,
        canvas_width: canvas.width,
        canvas_height: canvas.height,
      };
      geometry.dispose();
      material.dispose();
      renderer.dispose();
      canvas.remove();
      if (!details.is_webgpu_renderer) throw new Error('Three.js WebGPURenderer was not created');
      return details;
    },
  },
  {
    name: 'three_cube_render',
    source: async function threeCubeRender() {
      const THREE = await import('/__three/three.module.js');
      const canvas = document.createElement('canvas');
      canvas.width = 64;
      canvas.height = 64;
      document.body.appendChild(canvas);
      const renderer = new THREE.WebGLRenderer({ canvas, antialias: false, alpha: false });
      renderer.setSize(64, 64, false);
      renderer.setClearColor(0x000000, 1);
      const scene = new THREE.Scene();
      const camera = new THREE.PerspectiveCamera(70, 1, 0.1, 10);
      camera.position.z = 2;
      const mesh = new THREE.Mesh(
        new THREE.BoxGeometry(1.4, 1.4, 1.4),
        new THREE.MeshBasicMaterial({ color: 0x00ff00 }),
      );
      scene.add(mesh);
      renderer.render(scene, camera);
      const gl = renderer.getContext();
      const pixel = new Uint8Array(4);
      gl.readPixels(32, 32, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, pixel);
      renderer.dispose();
      canvas.remove();
      const sum = pixel[0] + pixel[1] + pixel[2] + pixel[3];
      if (sum === 0) throw new Error('cube render produced blank center pixel');
      return { center_pixel_rgba: Array.from(pixel) };
    },
  },
  {
    name: 'texture_load',
    source: async function textureLoad() {
      const THREE = await import('/__three/three.module.js');
      const imageBitmapSupported = typeof createImageBitmap === 'function';
      if (imageBitmapSupported) {
        const imageData = new ImageData(new Uint8ClampedArray([255, 0, 0, 255]), 1, 1);
        const bitmap = await createImageBitmap(imageData);
        bitmap.close?.();
      }

      const texture = await new Promise((resolve, reject) => {
        new THREE.TextureLoader().load('/assets/checker.svg', resolve, undefined, reject);
      });
      const canvas = document.createElement('canvas');
      canvas.width = 64;
      canvas.height = 64;
      document.body.appendChild(canvas);
      const renderer = new THREE.WebGLRenderer({ canvas, antialias: false, alpha: false });
      renderer.setSize(64, 64, false);
      const scene = new THREE.Scene();
      const camera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0.1, 10);
      camera.position.z = 1;
      scene.add(new THREE.Mesh(
        new THREE.PlaneGeometry(2, 2),
        new THREE.MeshBasicMaterial({ map: texture }),
      ));
      renderer.render(scene, camera);
      const gl = renderer.getContext();
      const pixel = new Uint8Array(4);
      gl.readPixels(16, 16, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, pixel);
      texture.dispose();
      renderer.dispose();
      canvas.remove();
      if (pixel[3] === 0) throw new Error('texture render produced transparent pixel');
      return { image_bitmap_supported: imageBitmapSupported, sample_pixel_rgba: Array.from(pixel) };
    },
  },
  {
    name: 'shader_material',
    source: async function shaderMaterial() {
      const THREE = await import('/__three/three.module.js');
      const canvas = document.createElement('canvas');
      canvas.width = 64;
      canvas.height = 64;
      document.body.appendChild(canvas);
      const renderer = new THREE.WebGLRenderer({ canvas, antialias: false, alpha: false });
      renderer.setSize(64, 64, false);
      const scene = new THREE.Scene();
      const camera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0.1, 10);
      camera.position.z = 1;
      const material = new THREE.ShaderMaterial({
        vertexShader: 'varying vec2 vUv; void main() { vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }',
        fragmentShader: 'precision highp float; varying vec2 vUv; void main() { gl_FragColor = vec4(vUv.x, 0.25 + vUv.y * 0.5, 1.0, 1.0); }',
      });
      scene.add(new THREE.Mesh(new THREE.PlaneGeometry(2, 2), material));
      renderer.render(scene, camera);
      const gl = renderer.getContext();
      const pixel = new Uint8Array(4);
      gl.readPixels(32, 32, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, pixel);
      material.dispose();
      renderer.dispose();
      canvas.remove();
      if (pixel[2] < 32) throw new Error('shader material render did not produce expected blue channel');
      return { center_pixel_rgba: Array.from(pixel) };
    },
  },
];

async function main() {
  const args = parseArgs(process.argv);
  const browser = path.resolve(args.browser);
  const viewerDir = path.resolve(args.viewerDir);
  ensureFile(browser, 'Browser executable');
  ensureFile(path.join(viewerDir, 'index.html'), 'Built viewer index');

  const smokeServer = startSmokeServer(viewerDir);
  const smokePort = await listen(smokeServer);
  const debugServer = http.createServer();
  const debugPort = await listen(debugServer);
  debugServer.close();

  const tmpRoot = path.join(rootDir, 'benchmarks', 'tmp');
  fs.mkdirSync(tmpRoot, { recursive: true });
  const userDataDir = fs.mkdtempSync(path.join(tmpRoot, 'smoke-profile-'));
  const baseUrl = `http://127.0.0.1:${smokePort}`;
  const startupUrl = `${baseUrl}/__smoke.html`;

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
    browserArgs.push(`--viewer-app-url=${startupUrl}`);
    browserArgs.push('--viewer-block-external-navigation');
  }
  if (args.viewerTrustedContent) {
    browserArgs.push('--viewer-trusted-content');
  }
  browserArgs.push(...args.browserFlag);
  if (!args.viewerMode) {
    browserArgs.push(startupUrl);
  }

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
  const tests = [];
  let launchGpuMetadata = { gpu_name: null, driver_version: null, angle_backend: null };
  try {
    const page = await waitForPageTarget(debugPort, 30000);
    cdp = new CdpClient(page.webSocketDebuggerUrl);
    await cdp.connect();
    launchGpuMetadata = gpuMetadataFromSystemInfo(await cdp.send('SystemInfo.getInfo').catch(() => null));
    assertNoSoftwareRenderer(
      launchGpuMetadata,
      'Hardware-GPU smoke launch preflight',
      args.allowSoftwareRendering,
    );
    await cdp.send('Runtime.enable');
    await cdp.send('Page.enable');
    await cdp.send('Page.bringToFront').catch(() => {});

    for (const test of smokeTests) {
      const requireThisTest = args.requireWebGPU && test.requiresWebGPU;
      const result = await evaluateTest(cdp, test.name, test.source.toString(), {
        allowSkip: test.allowSkip && !requireThisTest,
      });
      tests.push(result);
    }

    tests.push(await runBenchmarkSmoke(cdp, baseUrl, child, args.duration, args.warmup));
  } finally {
    if (cdp) cdp.close();
    killProcessTree(child);
    smokeServer.close();

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

  const failures = tests.filter((test) => test.status === 'fail');
  const result = {
    generated_at: new Date().toISOString(),
    platform: `${os.type()} ${os.release()} ${os.arch()}`,
    browser_executable: browser,
    browser_version: getBrowserVersion(browser),
    gpu_name: launchGpuMetadata.gpu_name,
    driver_version: launchGpuMetadata.driver_version,
    angle_backend: launchGpuMetadata.angle_backend,
    browser_flags: browserArgs,
    browser_extra_flags: args.browserFlag,
    allow_software_rendering: args.allowSoftwareRendering,
    viewer_dir: viewerDir,
    viewer_mode: args.viewerMode,
    viewer_trusted_content: args.viewerTrustedContent,
    viewer_app_url: args.viewerMode ? startupUrl : null,
    ok: failures.length === 0,
    tests,
  };

  fs.writeFileSync(path.resolve(args.output), `${JSON.stringify(result, null, 2)}\n`);
  console.log(`Wrote ${path.resolve(args.output)}`);
  if (failures.length) {
    console.error(`Smoke failures: ${failures.map((test) => test.name).join(', ')}`);
    process.exit(1);
  }
}

main().catch((error) => {
  console.error(error.stack || error.message);
  process.exit(1);
});
