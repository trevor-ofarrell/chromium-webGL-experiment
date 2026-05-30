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
const viewerPatchSeries = [
  'chromium_patches/0001-draft-minimal-three-viewer-entrypoint.patch',
  'chromium_patches/0002-draft-webgpu-queue-trace-attribution.patch',
];

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
  'complexity',
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
    settleGpuAfterWarmup: false,
    pipelineQuietFrames: '0',
    pipelineQuietMaxFrames: '30',
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
    viewerDir: path.join(rootDir, 'viewer', 'dist'),
    output: path.join(rootDir, 'benchmarks', 'raw', 'result.json'),
    buildArgs: '',
    packageDir: '',
    forkRevision: '',
    userDataDir: '',
    profileCacheKey: '',
    viewerFileMode: false,
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
    angleBackend: '',
    unsafeFullSizeWindow: false,
    allowSoftwareRendering: false,
  };
  const booleanArgs = new Set([
    'viewerMode',
    'viewerFileMode',
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

function isPathInside(child, parent) {
  const relative = path.relative(parent, child);
  return relative.length > 0 && !relative.startsWith('..') && !path.isAbsolute(relative);
}

function planUserDataProfile(args) {
  const tmpRoot = path.resolve(rootDir, 'benchmarks', 'tmp');
  const requestedUserDataDir = String(args.userDataDir || '').trim();
  const requestedCacheKey = String(args.profileCacheKey || '').trim();

  if (!requestedUserDataDir) {
    if (requestedCacheKey) {
      throw new Error('--profileCacheKey requires --userDataDir.');
    }
    return {
      tmpRoot,
      userDataDir: '',
      profile_cache_mode: 'fresh-temp',
      profile_cache_key: null,
      profile_reuse_enabled: false,
      profile_dir_created_by_runner: true,
    };
  }

  const resolvedUserDataDir = path.resolve(requestedUserDataDir);
  if (!isPathInside(resolvedUserDataDir, tmpRoot)) {
    throw new Error(`--userDataDir must resolve under ${tmpRoot} so benchmark profile reuse cannot touch unrelated browser profiles.`);
  }
  if (!requestedCacheKey) {
    throw new Error('--userDataDir requires --profileCacheKey so warmed-profile comparisons are labeled and cannot mix with cold baselines.');
  }

  return {
    tmpRoot,
    userDataDir: resolvedUserDataDir,
    profile_cache_mode: 'explicit-reuse',
    profile_cache_key: requestedCacheKey,
    profile_reuse_enabled: true,
    profile_dir_created_by_runner: !fs.existsSync(resolvedUserDataDir),
  };
}

function materializeUserDataProfile(profilePlan) {
  fs.mkdirSync(profilePlan.tmpRoot, { recursive: true });
  if (profilePlan.userDataDir) {
    fs.mkdirSync(profilePlan.userDataDir, { recursive: true });
    return profilePlan.userDataDir;
  }
  return fs.mkdtempSync(path.join(profilePlan.tmpRoot, 'profile-'));
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
  ].filter(([, enabled]) => enabled).map(([name]) => `--${name}`);
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

  if (unsafeFlags.length && (!args.viewerMode || !args.viewerTrustedContent)) {
    throw new Error(
      `Unsafe viewer/browser experiment flags require --viewerMode and --viewerTrustedContent: ${unsafeFlags.join(', ')}`,
    );
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
    'Benchmark evidence must use hardware GPU acceleration; rerun after fixing the driver/GPU path, ' +
    'or pass --allowSoftwareRendering only for diagnostic failure-mode runs that will not be retained as speed evidence.',
  );
}

function ensureFile(file, label) {
  if (!file || !fs.existsSync(file)) {
    throw new Error(`${label} not found: ${file}`);
  }
}

function readTextIfExists(file) {
  return fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : '';
}

function hostEnvironmentMetadata() {
  const kernelRelease = readTextIfExists('/proc/sys/kernel/osrelease').trim();
  const procVersion = readTextIfExists('/proc/version').trim();
  const isWsl = /microsoft|wsl/i.test(`${kernelRelease} ${procVersion}`);
  const osRelease = readTextIfExists('/etc/os-release');
  const prettyName = osRelease.split('\n')
    .find((line) => line.startsWith('PRETTY_NAME='))
    ?.split('=')[1]
    ?.replace(/^"|"$/g, '') || null;

  return {
    host_platform: isWsl ? 'wsl-linux' : process.platform,
    host_is_wsl: isWsl,
    host_kernel_release: kernelRelease || os.release(),
    host_distro: prettyName,
    host_repo_filesystem_policy: rootDir.startsWith('/mnt/') ? 'windows-mount-unsupported' : 'linux-filesystem',
  };
}

function sha256Text(text) {
  return crypto.createHash('sha256').update(text).digest('hex');
}

function getViewerPatchRevision(chromiumRevision) {
  if (!chromiumRevision) return null;
  const entries = [];
  for (const patchRelativePath of viewerPatchSeries) {
    const patchPath = path.join(rootDir, patchRelativePath);
    if (!fs.existsSync(patchPath)) return null;
    entries.push(`${patchRelativePath}=${sha256Text(fs.readFileSync(patchPath))}`);
  }
  const patchHash = sha256Text(entries.join('\n')).slice(0, 12);
  return `${chromiumRevision}+viewerpatch-${patchHash}`;
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
    timeout: options.timeoutMs || 5000,
    windowsHide: true,
  });
  if (result.status !== 0) return '';
  return result.stdout.trim();
}

function getGitRevision(dir) {
  if (!fs.existsSync(path.join(dir, '.git'))) return null;
  return commandText('git', ['rev-parse', 'HEAD'], { cwd: dir }) || null;
}

function getBrowserVersion(browser) {
  return commandText(browser, ['--version'], { timeoutMs: 5000 }) || null;
}

function getProcessTreeRssMb(pid) {
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
  let lastError = null;
  while (Date.now() - start < timeoutMs) {
    try {
      const targets = await waitForJson(`http://127.0.0.1:${debugPort}/json/list`, 5000);
      const page = targets.find((target) => target.type === 'page' && target.webSocketDebuggerUrl);
      if (page && (!expectedUrl || page.url.startsWith(expectedUrl))) return page;
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

function formatRuntimeException(exceptionDetails = {}) {
  const parts = [];
  if (exceptionDetails.text) parts.push(exceptionDetails.text);
  const exception = exceptionDetails.exception || {};
  if (exception.description) {
    parts.push(exception.description);
  } else if (exception.value !== undefined) {
    parts.push(String(exception.value));
  }
  const location = [
    exceptionDetails.url || '',
    Number.isFinite(exceptionDetails.lineNumber) ? exceptionDetails.lineNumber + 1 : '',
    Number.isFinite(exceptionDetails.columnNumber) ? exceptionDetails.columnNumber + 1 : '',
  ].filter((value) => value !== '').join(':');
  if (location) parts.push(`at ${location}`);
  const frames = exceptionDetails.stackTrace?.callFrames || [];
  if (frames.length) {
    const frame = frames[0];
    const frameLocation = [
      frame.url || frame.functionName || '<anonymous>',
      Number.isFinite(frame.lineNumber) ? frame.lineNumber + 1 : '',
      Number.isFinite(frame.columnNumber) ? frame.columnNumber + 1 : '',
    ].filter((value) => value !== '').join(':');
    if (frameLocation) parts.push(`top frame ${frameLocation}`);
  }
  return parts.join('\n') || 'Runtime exception';
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

function assertFiniteBenchmarkNumber(value, name, { allowZero = false } = {}) {
  if (!Number.isFinite(value) || value < 0 || (!allowZero && value === 0)) {
    const qualifier = allowZero ? 'a non-negative finite number' : 'a positive finite number';
    throw new Error(`--${name} must be ${qualifier}`);
  }
}

function assertNonNegativeIntegerBenchmarkNumber(value, name) {
  if (!Number.isInteger(value) || value < 0) {
    throw new Error(`--${name} must be a non-negative integer`);
  }
}

async function main() {
  const args = parseArgs(process.argv);
  assertTrustedViewerExperimentGates(args);
  const browser = path.resolve(args.browser || '');
  const viewerDir = path.resolve(args.viewerDir);
  const duration = Number(args.duration);
  const warmup = Number(args.warmup);
  const complexity = Number(args.complexity);
  const prerenderFrames = Number(args.prerenderFrames);
  const pipelineQuietFrames = Number(args.pipelineQuietFrames);
  const pipelineQuietMaxFrames = Number(args.pipelineQuietMaxFrames);
  assertFiniteBenchmarkNumber(duration, 'duration');
  assertFiniteBenchmarkNumber(warmup, 'warmup', { allowZero: true });
  assertFiniteBenchmarkNumber(complexity, 'complexity');
  assertNonNegativeIntegerBenchmarkNumber(prerenderFrames, 'prerenderFrames');
  assertNonNegativeIntegerBenchmarkNumber(pipelineQuietFrames, 'pipelineQuietFrames');
  assertNonNegativeIntegerBenchmarkNumber(pipelineQuietMaxFrames, 'pipelineQuietMaxFrames');
  if (pipelineQuietFrames > 0 && pipelineQuietMaxFrames < pipelineQuietFrames) {
    throw new Error('--pipelineQuietMaxFrames must be greater than or equal to --pipelineQuietFrames when pipeline-quiet warmup is enabled');
  }
  const profilePlan = planUserDataProfile(args);

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
    prerenderFrames: String(prerenderFrames),
    settleGpuAfterWarmup: args.settleGpuAfterWarmup ? '1' : '0',
    pipelineQuietFrames: String(pipelineQuietFrames),
    pipelineQuietMaxFrames: String(pipelineQuietMaxFrames),
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
  });
  const viewerIndex = path.join(viewerDir, 'index.html');
  const viewerUrl = args.viewerFileMode
    ? `${pathToFileURL(viewerIndex).href}?${query.toString()}`
    : `http://127.0.0.1:${viewerPort}/?${query.toString()}`;
  const expectedPageUrl = args.viewerFileMode ? pathToFileURL(viewerIndex).href : `http://127.0.0.1:${viewerPort}/`;
  const launchMetadata = webGpuBlobCacheMetadata(args, viewerUrl);
  assertWebGpuBlobCacheExperimentEligible(launchMetadata, args);
  const userDataDir = materializeUserDataProfile(profilePlan);
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
  const forkRevision = args.forkRevision ||
    (browserIsFromCheckout && isForkVariant ? getViewerPatchRevision(chromiumRevision) : null);
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

  if (!args.unsafeFullSizeWindow) {
    addSafeDesktopFlags(browserArgs, args.browserFlag);
  }

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
  if (args.viewerZeroCopy) {
    browserArgs.push('--viewer-zero-copy');
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
  if (args.viewerDeferWebgpuPipelineFlush) {
    browserArgs.push('--viewer-defer-webgpu-pipeline-flush');
  }
  if (args.viewerDeferWebgpuQueueFlush) {
    browserArgs.push('--viewer-defer-webgpu-queue-flush');
  }
  if (args.viewerDeferWebgpuSubmitFlush) {
    browserArgs.push('--viewer-defer-webgpu-submit-flush');
  }
  if (args.viewerSkipWebgpuCanvasTextureValidation) {
    browserArgs.push('--viewer-skip-webgpu-canvas-texture-validation');
  }
  if (args.viewerSkipWebgpuCanvasMemoryAccounting) {
    browserArgs.push('--viewer-skip-webgpu-canvas-memory-accounting');
  }
  if (args.viewerSkipWebgpuCopyExternalImageColorConversion) {
    browserArgs.push('--viewer-skip-webgpu-copy-external-image-color-conversion');
  }
  if (args.viewerSkipWebgpuCopyExternalImageColorSpaceValidation) {
    browserArgs.push('--viewer-skip-webgpu-copy-external-image-color-space-validation');
  }
  if (args.viewerSkipWebgpuCopyExternalImageDestValidation) {
    browserArgs.push('--viewer-skip-webgpu-copy-external-image-dest-validation');
  }
  if (args.viewerSkipWebgpuCopyExternalImageSourceValidation) {
    browserArgs.push('--viewer-skip-webgpu-copy-external-image-source-validation');
  }
  if (args.viewerSkipWebgpuCopyExternalImageCopySizeValidation) {
    browserArgs.push('--viewer-skip-webgpu-copy-external-image-copy-size-validation');
  }
  if (args.viewerSkipWebgpuWriteTextureLayoutValidation) {
    browserArgs.push('--viewer-skip-webgpu-write-texture-layout-validation');
  }
  if (args.viewerRejectWebgpuCpuTextureFallback) {
    browserArgs.push('--viewer-reject-webgpu-cpu-texture-fallback');
  }
  if (args.viewerSkipWebgpuUseCounters) {
    browserArgs.push('--viewer-skip-webgpu-use-counters');
  }
  if (args.viewerCacheWebgpuBindGroupLayouts) {
    browserArgs.push('--viewer-cache-webgpu-bind-group-layouts');
  }
  if (args.viewerSkipWebgpuCommandLabels) {
    browserArgs.push('--viewer-skip-webgpu-command-labels');
  }
  if (args.viewerSkipWebgpuResourceLabels) {
    browserArgs.push('--viewer-skip-webgpu-resource-labels');
  }
  if (args.viewerSkipWebgpuShaderSourceNullCheck) {
    browserArgs.push('--viewer-skip-webgpu-shader-source-null-check');
  }
  if (args.viewerSkipWebgpuShaderMemoryAccounting) {
    browserArgs.push('--viewer-skip-webgpu-shader-memory-accounting');
  }
  if (args.viewerSkipWebgpuRedundantPipelineSets) {
    browserArgs.push('--viewer-skip-webgpu-redundant-pipeline-sets');
  }
  if (args.viewerSkipWebgpuRedundantBindGroupSets) {
    browserArgs.push('--viewer-skip-webgpu-redundant-bind-group-sets');
  }
  if (args.viewerSkipWebgpuRedundantBufferSets) {
    browserArgs.push('--viewer-skip-webgpu-redundant-buffer-sets');
  }
  if (args.viewerSkipWebgpuRedundantRenderStateSets) {
    browserArgs.push('--viewer-skip-webgpu-redundant-render-state-sets');
  }
  if (args.viewerTraceWebgpuQueue) {
    browserArgs.push('--viewer-trace-webgpu-queue');
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
    const launchSystemInfo = await cdp.send('SystemInfo.getInfo').catch(() => null);
    assertNoSoftwareRenderer(
      gpuMetadataFromSystemInfo(launchSystemInfo, requestedAngleBackend),
      'Hardware-GPU launch preflight',
      args.allowSoftwareRendering,
    );

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
      consoleErrors.push(formatRuntimeException(params.exceptionDetails));
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
    const systemInfo = launchSystemInfo || await cdp.send('SystemInfo.getInfo').catch(() => null);
    const jsHeap = perfMetrics?.metrics?.find((metric) => metric.name === 'JSHeapUsedSize')?.value;
    const gpuDevice = systemInfo?.gpu?.devices?.[0] || null;

    result.chromium_revision = result.chromium_revision || chromiumRevision || null;
    result.fork_revision = result.fork_revision || forkRevision || null;
    result.build_args_hash = result.build_args_hash || (buildArgsText ? sha256Text(buildArgsText) : null);
    result.complexity = result.complexity ?? complexity;
    result.benchmark_variant = args.variant;
    result.viewer_mode = args.viewerMode;
    result.viewer_block_external_navigation = args.viewerMode;
    result.viewer_file_mode = args.viewerFileMode;
    result.viewer_trusted_content = args.viewerTrustedContent;
    result.viewer_aggressive_gpu = args.viewerAggressiveGpu;
    result.viewer_relaxed_webgl_validation = args.viewerRelaxedWebglValidation;
    result.viewer_zero_copy = args.viewerZeroCopy;
    result.viewer_in_process_gpu = args.viewerInProcessGpu;
    result.viewer_single_process = args.viewerSingleProcess;
    result.viewer_force_angle_backend = args.viewerForceAngleBackend || null;
    result.viewer_disable_unneeded_blink_features = args.viewerDisableUnneededBlinkFeatures;
    result.viewer_direct_gpu_presentation = args.viewerDirectGpuPresentation;
    result.viewer_defer_webgpu_pipeline_flush = args.viewerDeferWebgpuPipelineFlush;
    result.viewer_defer_webgpu_queue_flush = args.viewerDeferWebgpuQueueFlush;
    result.viewer_defer_webgpu_submit_flush = args.viewerDeferWebgpuSubmitFlush;
    result.viewer_skip_webgpu_canvas_texture_validation = args.viewerSkipWebgpuCanvasTextureValidation;
    result.viewer_skip_webgpu_canvas_memory_accounting = args.viewerSkipWebgpuCanvasMemoryAccounting;
    result.viewer_skip_webgpu_copy_external_image_color_conversion =
      args.viewerSkipWebgpuCopyExternalImageColorConversion;
    result.viewer_skip_webgpu_copy_external_image_color_space_validation =
      args.viewerSkipWebgpuCopyExternalImageColorSpaceValidation;
    result.viewer_skip_webgpu_copy_external_image_dest_validation =
      args.viewerSkipWebgpuCopyExternalImageDestValidation;
    result.viewer_skip_webgpu_copy_external_image_source_validation =
      args.viewerSkipWebgpuCopyExternalImageSourceValidation;
    result.viewer_skip_webgpu_copy_external_image_copy_size_validation =
      args.viewerSkipWebgpuCopyExternalImageCopySizeValidation;
    result.viewer_skip_webgpu_write_texture_layout_validation =
      args.viewerSkipWebgpuWriteTextureLayoutValidation;
    result.viewer_reject_webgpu_cpu_texture_fallback = args.viewerRejectWebgpuCpuTextureFallback;
    result.viewer_skip_webgpu_use_counters = args.viewerSkipWebgpuUseCounters;
    result.viewer_cache_webgpu_bind_group_layouts = args.viewerCacheWebgpuBindGroupLayouts;
    result.viewer_skip_webgpu_command_labels = args.viewerSkipWebgpuCommandLabels;
    result.viewer_skip_webgpu_resource_labels = args.viewerSkipWebgpuResourceLabels;
    result.viewer_skip_webgpu_shader_source_null_check =
      args.viewerSkipWebgpuShaderSourceNullCheck;
    result.viewer_skip_webgpu_shader_memory_accounting =
      args.viewerSkipWebgpuShaderMemoryAccounting;
    result.viewer_skip_webgpu_redundant_pipeline_sets =
      args.viewerSkipWebgpuRedundantPipelineSets;
    result.viewer_skip_webgpu_redundant_bind_group_sets =
      args.viewerSkipWebgpuRedundantBindGroupSets;
    result.viewer_skip_webgpu_redundant_buffer_sets =
      args.viewerSkipWebgpuRedundantBufferSets;
    result.viewer_skip_webgpu_redundant_render_state_sets =
      args.viewerSkipWebgpuRedundantRenderStateSets;
    result.viewer_trace_webgpu_queue = args.viewerTraceWebgpuQueue;
    result.resource_warmup_settle_gpu = result.resource_warmup_settle_gpu ?? args.settleGpuAfterWarmup;
    result.resource_warmup_pipeline_quiet_frames =
      result.resource_warmup_pipeline_quiet_frames ?? pipelineQuietFrames;
    result.resource_warmup_pipeline_quiet_max_frames =
      result.resource_warmup_pipeline_quiet_max_frames ?? pipelineQuietMaxFrames;
    result.texture_upload_mode = result.texture_upload_mode || args.textureUploadMode;
    result.webgpu_bundle_mode = result.webgpu_bundle_mode || args.webgpuBundleMode;
    result.webgpu_bundle_groups = result.webgpu_bundle_groups ?? 0;
    result.benchmark_hud_enabled = result.benchmark_hud_enabled ?? args.showHud;
    result.webgpu_queue_instrumentation_enabled =
      result.webgpu_queue_instrumentation_enabled ?? args.queueInstrumentation;
    result.webgpu_command_encoder_instrumentation_enabled =
      result.webgpu_command_encoder_instrumentation_enabled ?? args.commandEncoderInstrumentation;
    result.webgpu_bind_group_instrumentation_enabled =
      result.webgpu_bind_group_instrumentation_enabled ?? args.bindGroupInstrumentation;
    result.webgpu_pipeline_state_instrumentation_enabled =
      result.webgpu_pipeline_state_instrumentation_enabled ?? args.pipelineStateInstrumentation;
    result.webgpu_buffer_state_instrumentation_enabled =
      result.webgpu_buffer_state_instrumentation_enabled ?? args.bufferStateInstrumentation;
    result.webgpu_render_state_instrumentation_enabled =
      result.webgpu_render_state_instrumentation_enabled ?? args.renderStateInstrumentation;
    result.webgpu_immediate_instrumentation_enabled =
      result.webgpu_immediate_instrumentation_enabled ?? args.immediateInstrumentation;
    result.profile_cache_mode = profilePlan.profile_cache_mode;
    result.profile_cache_key = profilePlan.profile_cache_key;
    result.profile_reuse_enabled = profilePlan.profile_reuse_enabled;
    result.profile_dir = userDataDir;
    result.profile_dir_created_by_runner = profilePlan.profile_dir_created_by_runner;
    Object.assign(result, launchMetadata);
    result.requested_angle_backend = requestedAngleBackend;
    result.browser_flags = browserArgs;
    result.browser_extra_flags = args.browserFlag;
    result.allow_software_rendering = args.allowSoftwareRendering;
    result.browser_executable = browser;
    result.browser_version = browserVersion;
    result.browser_is_from_checkout = browserIsFromCheckout;
    result.platform = result.platform || `${os.type()} ${os.release()} ${os.arch()}`;
    Object.assign(result, hostEnvironmentMetadata());
    result.gpu_name = result.gpu_name || gpuDevice?.deviceString || null;
    result.driver_version = result.driver_version || gpuDevice?.driverVendor || gpuDevice?.driverVersion || null;
    result.angle_backend = result.angle_backend || requestedAngleBackend;
    assertNoSoftwareRenderer(result, 'Benchmark result', args.allowSoftwareRendering);
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
