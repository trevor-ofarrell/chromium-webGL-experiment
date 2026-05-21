#!/usr/bin/env node
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, '..');

function parseArgs(argv) {
  const args = {
    browser: '',
    output: path.join(rootDir, 'benchmarks', 'raw', 'file-navigation-lock-smoke.json'),
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
    throw new Error('Usage: node scripts/run_file_navigation_lock_tests.mjs --browser <viewer-content-shell.exe>');
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
    child.kill('SIGTERM');
    spawnSync('taskkill', ['/pid', String(child.pid), '/F'], { stdio: 'ignore', timeout: 5000 });
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

async function reservePort() {
  const server = http.createServer();
  const port = await listen(server);
  await new Promise((resolve) => server.close(resolve));
  return port;
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
    this.socket.addEventListener('close', () => {
      for (const { reject } of this.pending.values()) {
        reject(new Error('CDP socket closed before the command completed.'));
      }
      this.pending.clear();
    });
    this.socket.addEventListener('error', () => {
      for (const { reject } of this.pending.values()) {
        reject(new Error('CDP socket errored before the command completed.'));
      }
      this.pending.clear();
    });

    await new Promise((resolve, reject) => {
      this.socket.addEventListener('open', resolve, { once: true });
      this.socket.addEventListener('error', reject, { once: true });
    });
  }

  send(method, params = {}) {
    if (!this.socket || this.socket.readyState !== 1) {
      return Promise.reject(new Error(`CDP socket is not open for ${method}.`));
    }
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

function writePage(file, title, readyName) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, [
    '<!doctype html>',
    '<meta charset="utf-8">',
    `<title>${title}</title>`,
    `<script>window.${readyName} = true;</script>`,
  ].join(''));
}

async function main() {
  const args = parseArgs(process.argv);
  const browser = path.resolve(args.browser);
  ensureFile(browser, 'Browser executable');

  const tmpRoot = path.join(rootDir, 'benchmarks', 'tmp');
  fs.mkdirSync(tmpRoot, { recursive: true });
  const testRoot = fs.mkdtempSync(path.join(tmpRoot, 'file-nav-'));
  const appDir = path.join(testRoot, 'viewer-app');
  const outsideDir = path.join(testRoot, 'outside');
  const viewerIndex = path.join(appDir, 'index.html');
  const allowedFile = path.join(appDir, 'assets', 'allowed.html');
  const blockedFile = path.join(outsideDir, 'blocked.html');
  writePage(viewerIndex, 'viewer index', 'viewerNavigationTestReady');
  writePage(allowedFile, 'allowed file', 'allowedFileNavigationLanded');
  writePage(blockedFile, 'blocked file', 'blockedFileNavigationLanded');

  const debugPort = await reservePort();
  const userDataDir = fs.mkdtempSync(path.join(tmpRoot, 'file-nav-profile-'));
  const allowedUrl = pathToFileURL(allowedFile).href;
  const blockedUrl = pathToFileURL(blockedFile).href;

  const child = spawn(browser, [
    `--remote-debugging-port=${debugPort}`,
    `--user-data-dir=${userDataDir}`,
    '--no-first-run',
    '--disable-default-apps',
    '--disable-background-networking',
    '--disable-component-update',
    '--disable-sync',
    '--disable-extensions',
    `--viewer-app-url=${viewerIndex}`,
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
    if (initialReady && initialUrl === pathToFileURL(viewerIndex).href) {
      tests.push(pass('launches_file_viewer_app_path', { url: initialUrl }));
    } else {
      tests.push(fail('launches_file_viewer_app_path', 'Viewer file path did not load', { url: initialUrl }));
    }

    await evaluate(cdp, `location.href = ${JSON.stringify(allowedUrl)}; true`);
    const allowedLanded = await waitFor(cdp, 'window.allowedFileNavigationLanded === true');
    const afterAllowedUrl = await currentUrl(cdp);
    if (allowedLanded && afterAllowedUrl === allowedUrl) {
      tests.push(pass('allows_viewer_directory_file_navigation', { url: afterAllowedUrl }));
    } else {
      tests.push(fail('allows_viewer_directory_file_navigation', 'Viewer directory file navigation did not land', { url: afterAllowedUrl }));
    }

    await evaluate(cdp, `location.href = ${JSON.stringify(blockedUrl)}; true`);
    await new Promise((resolve) => setTimeout(resolve, 1500));
    const afterBlockedUrl = await currentUrl(cdp);
    if (afterBlockedUrl !== blockedUrl) {
      tests.push(pass('blocks_file_navigation_outside_viewer_directory', {
        url: afterBlockedUrl,
        blocked_url: blockedUrl,
      }));
    } else {
      tests.push(fail('blocks_file_navigation_outside_viewer_directory', 'Outside file navigation was not blocked', {
        url: afterBlockedUrl,
        blocked_url: blockedUrl,
      }));
    }

    const beforeTargets = await waitForJson(`http://127.0.0.1:${debugPort}/json/list`, 5000);
    await evaluate(cdp, `window.open(${JSON.stringify(blockedUrl)}, '_blank'); true`);
    await new Promise((resolve) => setTimeout(resolve, 1500));
    const afterTargets = await waitForJson(`http://127.0.0.1:${debugPort}/json/list`, 5000);
    const beforePages = beforeTargets.filter((target) => target.type === 'page').length;
    const afterPages = afterTargets.filter((target) => target.type === 'page').length;
    if (afterPages <= beforePages) {
      tests.push(pass('blocks_file_window_open_outside_viewer_directory', {
        before_pages: beforePages,
        after_pages: afterPages,
      }));
    } else {
      tests.push(fail('blocks_file_window_open_outside_viewer_directory', 'window.open created an extra page target', {
        before_pages: beforePages,
        after_pages: afterPages,
      }));
    }
  } finally {
    if (cdp) cdp.close();
    killProcessTree(child);

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
    viewer_app_path: viewerIndex,
    viewer_app_url: pathToFileURL(viewerIndex).href,
    allowed_file_url: allowedUrl,
    blocked_file_url: blockedUrl,
    ok: failures.length === 0,
    tests,
  };

  fs.mkdirSync(path.dirname(path.resolve(args.output)), { recursive: true });
  fs.writeFileSync(path.resolve(args.output), `${JSON.stringify(result, null, 2)}\n`);
  console.log(`Wrote ${path.resolve(args.output)}`);
  if (failures.length) {
    console.error(`File navigation-lock failures: ${failures.map((test) => test.name).join(', ')}`);
    process.exit(1);
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
