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
    output: path.join(rootDir, 'benchmarks', 'raw', 'navigation-lock-smoke.json'),
    browserFlag: [],
  };

  for (let i = 2; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token.startsWith('--')) {
      throw new Error(`Unexpected positional argument: ${token}`);
    }
    const key = token.slice(2);
    if (key === 'browser-flag') {
      args.browserFlag.push(argv[++i]);
    } else if (key in args) {
      args[key] = argv[++i];
    } else {
      throw new Error(`Unknown argument: ${token}`);
    }
  }

  if (!args.browser) {
    throw new Error('Usage: node scripts/run_navigation_lock_tests.mjs --browser <viewer-content-shell.exe>');
  }
  return args;
}

function ensureFile(file, label) {
  if (!file || !fs.existsSync(file)) {
    throw new Error(`${label} not found: ${file}`);
  }
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
  if (process.platform === 'win32') {
    const literalPath = browser.replaceAll("'", "''");
    const out = commandText('powershell', [
      '-NoProfile',
      '-Command',
      `(Get-Item -LiteralPath '${literalPath}').VersionInfo.ProductVersion`,
    ]);
    return out || null;
  }
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

async function listen(server, host = '127.0.0.1') {
  return new Promise((resolve, reject) => {
    server.on('error', reject);
    server.listen(0, host, () => resolve(server.address().port));
  });
}

function getNonLoopbackIPv4Address() {
  const interfaces = os.networkInterfaces();
  for (const entries of Object.values(interfaces)) {
    for (const entry of entries || []) {
      if (entry.family === 'IPv4' && !entry.internal && entry.address) {
        return entry.address;
      }
    }
  }
  return '';
}

function page(title, body = '') {
  return `<!doctype html><meta charset="utf-8"><title>${title}</title><body>${body}</body>`;
}

function startServer(name) {
  const hits = [];
  const server = http.createServer((req, res) => {
    const url = new URL(req.url || '/', 'http://127.0.0.1');
    hits.push({ path: url.pathname, at: Date.now() });

    if (url.pathname === '/' || url.pathname === '/index.html') {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
      res.end(page(`${name} index`, '<script>window.viewerNavigationTestReady = true;</script>'));
      return;
    }

    if (url.pathname === '/allowed.html') {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
      res.end(page(`${name} allowed`, '<script>window.allowedNavigationLanded = true;</script>'));
      return;
    }

    if (url.pathname === '/blocked.html') {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
      res.end(page(`${name} blocked`, '<script>window.blockedNavigationLanded = true;</script>'));
      return;
    }

    res.writeHead(404);
    res.end('Not found');
  });

  return { server, hits };
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
      const pageTarget = targets.find((target) => target.type === 'page' && target.webSocketDebuggerUrl);
      if (pageTarget) return pageTarget;
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
      }
    });

    await new Promise((resolve, reject) => {
      this.socket.addEventListener('open', resolve, { once: true });
      this.socket.addEventListener('error', reject, { once: true });
    });
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

async function evaluate(cdp, expression) {
  const result = await cdp.send('Runtime.evaluate', {
    expression,
    awaitPromise: true,
    returnByValue: true,
  });
  if (result.exceptionDetails) {
    throw new Error(result.exceptionDetails.text || 'Runtime exception');
  }
  return result.result?.value;
}

async function waitFor(cdp, expression, timeoutMs = 5000) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const value = await evaluate(cdp, expression);
    if (value) return value;
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  return null;
}

async function currentUrl(cdp) {
  const result = await cdp.send('Runtime.evaluate', {
    expression: 'location.href',
    returnByValue: true,
  });
  return result.result?.value || '';
}

function pass(name, details = {}) {
  return { name, status: 'pass', details };
}

function fail(name, error, details = {}) {
  return { name, status: 'fail', error, details };
}

async function main() {
  const args = parseArgs(process.argv);
  const browser = path.resolve(args.browser);
  ensureFile(browser, 'Browser executable');

  const externalHost = getNonLoopbackIPv4Address();
  if (!externalHost) {
    throw new Error('No non-loopback IPv4 address is available for external HTTP navigation-lock smoke coverage.');
  }

  const allowed = startServer('allowed-origin');
  const blocked = startServer('blocked-origin');
  const external = startServer('external-origin');
  const allowedPort = await listen(allowed.server);
  const blockedPort = await listen(blocked.server);
  const externalPort = await listen(external.server, externalHost);
  const allowedOrigin = `http://127.0.0.1:${allowedPort}`;
  const blockedOrigin = `http://127.0.0.1:${blockedPort}`;
  const externalOrigin = `http://${externalHost}:${externalPort}`;
  const debugServer = http.createServer();
  const debugPort = await listen(debugServer);
  debugServer.close();

  const tmpRoot = path.join(rootDir, 'benchmarks', 'tmp');
  fs.mkdirSync(tmpRoot, { recursive: true });
  const userDataDir = fs.mkdtempSync(path.join(tmpRoot, 'nav-profile-'));
  const viewerAppUrl = `${allowedOrigin}/index.html`;
  const externalBlockedUrl = `${externalOrigin}/blocked.html`;

  const child = spawn(browser, [
    `--remote-debugging-port=${debugPort}`,
    `--user-data-dir=${userDataDir}`,
    '--no-first-run',
    '--disable-default-apps',
    '--disable-background-networking',
    '--disable-component-update',
    '--disable-sync',
    '--disable-extensions',
    `--viewer-app-url=${viewerAppUrl}`,
    '--viewer-block-external-navigation',
    ...args.browserFlag,
  ], {
    cwd: rootDir,
    stdio: ['ignore', 'pipe', 'pipe'],
    windowsHide: true,
  });

  let stdout = '';
  let stderr = '';
  child.stdout.on('data', (chunk) => { stdout += chunk.toString(); });
  child.stderr.on('data', (chunk) => { stderr += chunk.toString(); });

  const tests = [];
  let cdp = null;
  try {
    const pageTarget = await waitForPageTarget(debugPort, 30000);
    cdp = new CdpClient(pageTarget.webSocketDebuggerUrl);
    await cdp.connect();
    await cdp.send('Runtime.enable');
    await cdp.send('Page.enable');

    const initialReady = await waitFor(cdp, 'window.viewerNavigationTestReady === true');
    const initialUrl = await currentUrl(cdp);
    if (initialReady && initialUrl === viewerAppUrl) {
      tests.push(pass('launches_viewer_app_url', { url: initialUrl }));
    } else {
      tests.push(fail('launches_viewer_app_url', 'Viewer app URL did not load', { url: initialUrl }));
    }

    await evaluate(cdp, `location.href = '${allowedOrigin}/allowed.html'; true`);
    const allowedLanded = await waitFor(cdp, 'window.allowedNavigationLanded === true');
    const afterAllowedUrl = await currentUrl(cdp);
    if (allowedLanded && afterAllowedUrl === `${allowedOrigin}/allowed.html`) {
      tests.push(pass('allows_same_origin_navigation', { url: afterAllowedUrl }));
    } else {
      tests.push(fail('allows_same_origin_navigation', 'Same-origin navigation did not land', { url: afterAllowedUrl }));
    }

    await evaluate(cdp, `location.href = '${blockedOrigin}/blocked.html'; true`);
    await new Promise((resolve) => setTimeout(resolve, 1500));
    const afterBlockedUrl = await currentUrl(cdp);
    const blockedHits = blocked.hits.filter((hit) => hit.path === '/blocked.html').length;
    if (!afterBlockedUrl.startsWith(`${blockedOrigin}/blocked.html`)) {
      tests.push(pass('blocks_cross_origin_navigation', {
        url: afterBlockedUrl,
        blocked_origin_hits: blockedHits,
      }));
    } else {
      tests.push(fail('blocks_cross_origin_navigation', 'Cross-origin navigation was not blocked', {
        url: afterBlockedUrl,
        blocked_origin_hits: blockedHits,
      }));
    }

    await evaluate(cdp, `location.href = '${externalBlockedUrl}'; true`);
    await new Promise((resolve) => setTimeout(resolve, 1500));
    const afterExternalBlockedUrl = await currentUrl(cdp);
    const externalHits = external.hits.filter((hit) => hit.path === '/blocked.html').length;
    if (afterExternalBlockedUrl !== externalBlockedUrl && externalHits === 0) {
      tests.push(pass('blocks_external_http_navigation', {
        url: afterExternalBlockedUrl,
        blocked_url: externalBlockedUrl,
        external_blocked_hits: externalHits,
      }));
    } else {
      tests.push(fail('blocks_external_http_navigation', 'External HTTP navigation was not blocked before request dispatch', {
        url: afterExternalBlockedUrl,
        blocked_url: externalBlockedUrl,
        external_blocked_hits: externalHits,
      }));
    }

    const beforeTargets = await waitForJson(`http://127.0.0.1:${debugPort}/json/list`, 5000);
    await evaluate(cdp, `window.open('${blockedOrigin}/blocked.html', '_blank'); true`);
    await new Promise((resolve) => setTimeout(resolve, 1500));
    const afterTargets = await waitForJson(`http://127.0.0.1:${debugPort}/json/list`, 5000);
    const beforePages = beforeTargets.filter((target) => target.type === 'page').length;
    const afterPages = afterTargets.filter((target) => target.type === 'page').length;
    if (afterPages <= beforePages) {
      tests.push(pass('blocks_window_open', { before_pages: beforePages, after_pages: afterPages }));
    } else {
      tests.push(fail('blocks_window_open', 'window.open created an extra page target', {
        before_pages: beforePages,
        after_pages: afterPages,
      }));
    }
  } finally {
    if (cdp) cdp.close();
    killProcessTree(child);
    allowed.server.close();
    blocked.server.close();
    external.server.close();

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
    viewer_app_url: viewerAppUrl,
    blocked_origin: blockedOrigin,
    external_blocked_url: externalBlockedUrl,
    external_blocked_host: externalHost,
    ok: failures.length === 0,
    tests,
  };

  fs.mkdirSync(path.dirname(path.resolve(args.output)), { recursive: true });
  fs.writeFileSync(path.resolve(args.output), `${JSON.stringify(result, null, 2)}\n`);
  console.log(`Wrote ${path.resolve(args.output)}`);
  if (failures.length) {
    console.error(`Navigation-lock failures: ${failures.map((test) => test.name).join(', ')}`);
    process.exit(1);
  }
}

main().catch((error) => {
  console.error(error.stack || error.message);
  process.exit(1);
});
