#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
}

const expectedByType = {
  runtime: {
    requiredPass: [
      'viewer_launch',
      'webgl2_context',
      'web_platform_basics',
      'basic_input_events',
      'three_cube_render',
      'texture_load',
      'shader_material',
      'benchmark_run',
    ],
    allowedSkip: [
      'webgl_context_loss_event',
      'webgpu_adapter_device',
      'webgpu_device_loss_signal',
      'three_webgpu_render',
    ],
  },
  navigation: {
    requiredPass: [
      'launches_viewer_app_url',
      'allows_same_origin_navigation',
      'blocks_cross_origin_navigation',
      'blocks_external_http_navigation',
      'blocks_window_open',
    ],
    allowedSkip: [],
  },
  'file-navigation': {
    requiredPass: [
      'launches_file_viewer_app_path',
      'allows_viewer_directory_file_navigation',
      'blocks_file_navigation_outside_viewer_directory',
      'blocks_file_window_open_outside_viewer_directory',
    ],
    allowedSkip: [],
  },
};

function parseArgs(argv) {
  const args = {
    type: 'runtime',
    expectBrowserMode: false,
    expectViewerMode: false,
    expectViewerTrustedContent: false,
    expectedBrowser: '',
    requireWebGPU: false,
    requiredBrowserFlag: [],
    files: [],
  };

  for (let i = 2; i < argv.length; i += 1) {
    const token = argv[i];
    if (token === '--type') {
      args.type = argv[++i];
    } else if (token === '--expect-browser-mode') {
      args.expectBrowserMode = true;
    } else if (token === '--expect-viewer-mode') {
      args.expectViewerMode = true;
    } else if (token === '--expect-viewer-trusted-content') {
      args.expectViewerTrustedContent = true;
    } else if (token === '--expected-browser') {
      args.expectedBrowser = argv[++i];
    } else if (token === '--require-webgpu') {
      args.requireWebGPU = true;
    } else if (token === '--required-browser-flag') {
      args.requiredBrowserFlag.push(argv[++i]);
    } else {
      args.files.push(token);
    }
  }

  if (!expectedByType[args.type]) {
    throw new Error(`Unknown smoke result type: ${args.type}`);
  }
  if (!args.files.length) {
    throw new Error('Usage: node scripts/validate_smoke_result.mjs [--type runtime|navigation|file-navigation] [--require-webgpu] <smoke.json...>');
  }

  return args;
}

function validateOptionalStringArray(errors, data, key) {
  if (!(key in data)) {
    return;
  }
  if (!Array.isArray(data[key])) {
    errors.push(`${key} must be an array when present`);
    return;
  }
  data[key].forEach((value, index) => {
    if (typeof value !== 'string') {
      errors.push(`${key}[${index}] must be a string`);
    }
  });
}

function validateRequiredBrowserFlags(errors, data, requiredFlags) {
  if (!requiredFlags.length) {
    return;
  }
  if (!Array.isArray(data.browser_flags)) {
    errors.push('browser_flags must be an array when --required-browser-flag is set');
    return;
  }
  for (const flag of requiredFlags) {
    if (!data.browser_flags.includes(flag)) {
      errors.push(`browser_flags must include ${flag}`);
    }
  }
}

function validate(data, type, options = {}) {
  const errors = [];
  const config = expectedByType[type];

  if (data.ok !== true) {
    errors.push('ok must be true');
  }
  if (typeof data.generated_at !== 'string' || data.generated_at.length === 0) {
    errors.push('generated_at must be a non-empty string');
  }
  if (typeof data.platform !== 'string' || data.platform.length === 0) {
    errors.push('platform must be a non-empty string');
  }
  if (typeof data.browser_executable !== 'string' || data.browser_executable.length === 0) {
    errors.push('browser_executable must be a non-empty string');
  } else if (options.expectedBrowser && !sameBrowserPath(data.browser_executable, options.expectedBrowser)) {
    errors.push(`browser_executable must match expected browser ${options.expectedBrowser}, got ${data.browser_executable}`);
  }
  validateOptionalStringArray(errors, data, 'browser_flags');
  validateOptionalStringArray(errors, data, 'browser_extra_flags');
  validateRequiredBrowserFlags(errors, data, options.requiredBrowserFlag || []);
  if (!Array.isArray(data.tests) || data.tests.length === 0) {
    errors.push('tests must be a non-empty array');
    return errors;
  }

  const byName = new Map();
  for (const test of data.tests) {
    if (!test || typeof test !== 'object') {
      errors.push('every test must be an object');
      continue;
    }
    if (typeof test.name !== 'string' || test.name.length === 0) {
      errors.push('every test must have a non-empty name');
      continue;
    }
    if (byName.has(test.name)) {
      errors.push(`duplicate test name: ${test.name}`);
    }
    byName.set(test.name, test);
    if (!['pass', 'skip', 'fail'].includes(test.status)) {
      errors.push(`${test.name} has invalid status ${test.status}`);
    }
    if (test.status === 'fail') {
      errors.push(`${test.name} failed: ${test.error || 'no error detail'}`);
    }
    if ('duration_ms' in test && (typeof test.duration_ms !== 'number' || !Number.isFinite(test.duration_ms) || test.duration_ms < 0)) {
      errors.push(`${test.name} has invalid duration_ms`);
    }
  }

  for (const name of config.requiredPass) {
    const test = byName.get(name);
    if (!test) {
      errors.push(`missing required test: ${name}`);
    } else if (test.status !== 'pass') {
      errors.push(`${name} must pass, got ${test.status}`);
    }
  }

  for (const test of data.tests) {
    if (test.status === 'skip' && !config.allowedSkip.includes(test.name)) {
      errors.push(`${test.name} skipped but skip is not allowed for ${type} smoke results`);
    }
  }

  if (type === 'runtime') {
    validateRuntimeLaunchMetadata(errors, data, options);
    validateRuntimeWebPlatformDetails(errors, byName.get('web_platform_basics'));
    validateRuntimeInputDetails(errors, byName.get('basic_input_events'));
    validateRuntimeWebGpuAdapterDetails(errors, byName.get('webgpu_adapter_device'));
    validateRuntimeWebGpuDeviceLossDetails(errors, byName.get('webgpu_device_loss_signal'));
    validateRuntimeThreeWebgpuDetails(errors, byName.get('three_webgpu_render'));
    if (options.requireWebGPU) {
      validateRuntimeRequiredWebGpuSmoke(errors, byName);
    }
    const benchmarkRun = byName.get('benchmark_run');
    if (benchmarkRun) {
      validateRuntimeBenchmarkDetails(errors, benchmarkRun);
    }
  } else if (type === 'navigation') {
    validateNavigationDetails(errors, data, byName);
  } else if (type === 'file-navigation') {
    validateFileNavigationDetails(errors, data, byName);
  }

  return errors;
}

function validateRuntimeLaunchMetadata(errors, data, options) {
  if (options.expectBrowserMode) {
    if (data.viewer_mode !== false) {
      errors.push(`viewer_mode must be false for browser-mode runtime smoke, got ${data.viewer_mode}`);
    }
    if (data.viewer_trusted_content !== false) {
      errors.push(`viewer_trusted_content must be false for browser-mode runtime smoke, got ${data.viewer_trusted_content}`);
    }
    if (data.viewer_app_url !== null) {
      errors.push(`viewer_app_url must be null for browser-mode runtime smoke, got ${data.viewer_app_url}`);
    }
  }
  if (options.expectViewerMode && data.viewer_mode !== true) {
    errors.push(`viewer_mode must be true for viewer-mode runtime smoke, got ${data.viewer_mode}`);
  }
  if (options.expectViewerTrustedContent && data.viewer_trusted_content !== true) {
    errors.push(`viewer_trusted_content must be true for trusted runtime smoke, got ${data.viewer_trusted_content}`);
  }
  if (options.expectViewerMode) {
    const viewerAppUrl = parseUrl(data.viewer_app_url);
    if (!viewerAppUrl || !['http:', 'https:'].includes(viewerAppUrl.protocol)) {
      errors.push('viewer_app_url must be a valid http(s) URL for viewer-mode runtime smoke');
    }
  }
}

function isFiniteNumber(value) {
  return typeof value === 'number' && Number.isFinite(value);
}

function isNonEmptyString(value) {
  return typeof value === 'string' && value.length > 0;
}

function normalizeBrowserPath(value) {
  const normalized = path.resolve(String(value));
  return process.platform === 'win32' ? normalized.toLowerCase() : normalized;
}

function sameBrowserPath(actual, expected) {
  return normalizeBrowserPath(actual) === normalizeBrowserPath(expected);
}

function parseUrl(value) {
  if (!isNonEmptyString(value)) return null;
  try {
    return new URL(value);
  } catch {
    return null;
  }
}

function isLoopbackHost(hostname) {
  return hostname === 'localhost' ||
    hostname === '127.0.0.1' ||
    hostname === '::1' ||
    hostname === '[::1]';
}

function getDetails(errors, test, name) {
  if (!test?.details || typeof test.details !== 'object' || Array.isArray(test.details)) {
    errors.push(`${name}.details must be a non-empty object`);
    return null;
  }
  if (Object.keys(test.details).length === 0) {
    errors.push(`${name}.details must be a non-empty object`);
  }
  return test.details;
}

function validateRuntimeWebPlatformDetails(errors, test) {
  const details = getDetails(errors, test, 'web_platform_basics');
  if (!details) return;
  if (details.canvas_2d !== true) {
    errors.push(`web_platform_basics.details.canvas_2d must be true, got ${details.canvas_2d}`);
  }
  if (!isFiniteNumber(details.raf_timestamp_ms) || details.raf_timestamp_ms < 0) {
    errors.push('web_platform_basics.details.raf_timestamp_ms must be a finite non-negative number');
  }
  if (!isFiniteNumber(details.performance_delta_ms) || details.performance_delta_ms < 0) {
    errors.push('web_platform_basics.details.performance_delta_ms must be a finite non-negative number');
  }
  if (!isNonEmptyString(details.fetch_content_type) || !details.fetch_content_type.includes('svg')) {
    errors.push(`web_platform_basics.details.fetch_content_type must identify SVG content, got ${details.fetch_content_type}`);
  }
  if (!Number.isInteger(details.fetch_bytes) || details.fetch_bytes <= 0) {
    errors.push('web_platform_basics.details.fetch_bytes must be a positive integer');
  }
}

function validateRuntimeInputDetails(errors, test) {
  const details = getDetails(errors, test, 'basic_input_events');
  if (!details) return;
  if (!Array.isArray(details.events)) {
    errors.push('basic_input_events.details.events must be an array');
  } else {
    for (const eventName of ['pointerdown', 'pointermove', 'pointerup', 'wheel', 'keydown']) {
      if (!details.events.includes(eventName)) {
        errors.push(`basic_input_events.details.events must include ${eventName}`);
      }
    }
  }
  if (typeof details.pointer_event_constructor !== 'boolean') {
    errors.push('basic_input_events.details.pointer_event_constructor must be boolean');
  }
  if (!isFiniteNumber(details.wheel_delta_y)) {
    errors.push('basic_input_events.details.wheel_delta_y must be finite');
  }
  if (details.key !== 'ArrowLeft') {
    errors.push(`basic_input_events.details.key must be ArrowLeft, got ${details.key}`);
  }
}

function validateRuntimeRequiredWebGpuSmoke(errors, byName) {
  for (const name of ['webgpu_adapter_device', 'webgpu_device_loss_signal', 'three_webgpu_render']) {
    const test = byName.get(name);
    if (!test) {
      errors.push(`missing required WebGPU test: ${name}`);
    } else if (test.status !== 'pass') {
      errors.push(`${name} must pass when --require-webgpu is set, got ${test.status}`);
    }
  }
}

function validateRuntimeWebGpuAdapterDetails(errors, test) {
  if (!test || test.status !== 'pass') return;
  const details = getDetails(errors, test, 'webgpu_adapter_device');
  if (!details) return;
  if (!Array.isArray(details.features)) {
    errors.push('webgpu_adapter_device.details.features must be an array');
  } else {
    for (const feature of details.features) {
      if (!isNonEmptyString(feature)) {
        errors.push(`webgpu_adapter_device.details.features entries must be non-empty strings, got ${feature}`);
      }
    }
  }
  if (!Number.isInteger(details.max_texture_dimension_2d) || details.max_texture_dimension_2d <= 0) {
    errors.push('webgpu_adapter_device.details.max_texture_dimension_2d must be a positive integer');
  }
}

function validateRuntimeWebGpuDeviceLossDetails(errors, test) {
  if (!test || test.status !== 'pass') return;
  const details = getDetails(errors, test, 'webgpu_device_loss_signal');
  if (!details) return;
  if (details.reason !== 'destroyed') {
    errors.push(`webgpu_device_loss_signal.details.reason must be destroyed, got ${details.reason}`);
  }
  if (typeof details.message !== 'string') {
    errors.push('webgpu_device_loss_signal.details.message must be a string');
  }
}

function validateRuntimeThreeWebgpuDetails(errors, test) {
  if (!test || test.status !== 'pass') return;
  const details = getDetails(errors, test, 'three_webgpu_render');
  if (!details) return;
  if (details.is_webgpu_renderer !== true) {
    errors.push(`three_webgpu_render.details.is_webgpu_renderer must be true, got ${details.is_webgpu_renderer}`);
  }
  if ('backend' in details && details.backend !== null && !isNonEmptyString(details.backend)) {
    errors.push(`three_webgpu_render.details.backend must be null or a non-empty string, got ${details.backend}`);
  }
  if (!isFiniteNumber(details.render_ms) || details.render_ms < 0) {
    errors.push('three_webgpu_render.details.render_ms must be a finite non-negative number');
  }
  if (!Number.isInteger(details.canvas_width) || details.canvas_width <= 0) {
    errors.push('three_webgpu_render.details.canvas_width must be a positive integer');
  }
  if (!Number.isInteger(details.canvas_height) || details.canvas_height <= 0) {
    errors.push('three_webgpu_render.details.canvas_height must be a positive integer');
  }
}

function validateRuntimeBenchmarkDetails(errors, benchmarkRun) {
  if (!benchmarkRun.details || typeof benchmarkRun.details !== 'object' || Array.isArray(benchmarkRun.details)) {
    errors.push('benchmark_run.details must be a non-empty object');
    return;
  }

  const { details } = benchmarkRun;
  if (Object.keys(details).length === 0) {
    errors.push('benchmark_run.details must be a non-empty object');
  }
  if (details.scene_name !== 'many-draw-calls') {
    errors.push(`benchmark_run.details.scene_name must be many-draw-calls, got ${details.scene_name}`);
  }
  if (details.renderer_type !== 'webgl2') {
    errors.push(`benchmark_run.details.renderer_type must be webgl2, got ${details.renderer_type}`);
  }
  if (!isFiniteNumber(details.avg_fps) || details.avg_fps <= 0) {
    errors.push('benchmark_run.details.avg_fps must be a finite positive number');
  }
  if (!Number.isInteger(details.frame_count) || details.frame_count <= 0) {
    errors.push('benchmark_run.details.frame_count must be a positive integer');
  }
  if (!isFiniteNumber(details.startup_ms_to_first_frame) || details.startup_ms_to_first_frame < 0) {
    errors.push('benchmark_run.details.startup_ms_to_first_frame must be a finite non-negative number');
  }
}

function validateNavigationDetails(errors, data, byName) {
  const viewerAppUrl = parseUrl(data.viewer_app_url);
  const blockedOrigin = parseUrl(data.blocked_origin);
  const externalBlockedUrl = parseUrl(data.external_blocked_url);
  if (!viewerAppUrl || !['http:', 'https:'].includes(viewerAppUrl.protocol)) {
    errors.push('viewer_app_url must be a valid http(s) URL');
  }
  if (!blockedOrigin || !['http:', 'https:'].includes(blockedOrigin.protocol)) {
    errors.push('blocked_origin must be a valid http(s) URL');
  }
  if (!externalBlockedUrl || !['http:', 'https:'].includes(externalBlockedUrl.protocol)) {
    errors.push('external_blocked_url must be a valid http(s) URL');
  } else if (isLoopbackHost(externalBlockedUrl.hostname)) {
    errors.push('external_blocked_url must use a non-loopback host');
  }

  const launchDetails = getDetails(errors, byName.get('launches_viewer_app_url'), 'launches_viewer_app_url');
  if (launchDetails && launchDetails.url !== data.viewer_app_url) {
    errors.push(`launches_viewer_app_url.details.url must equal viewer_app_url, got ${launchDetails.url}`);
  }

  const allowedDetails = getDetails(errors, byName.get('allows_same_origin_navigation'), 'allows_same_origin_navigation');
  const allowedUrl = parseUrl(allowedDetails?.url);
  if (allowedDetails && (!allowedUrl || !viewerAppUrl || allowedUrl.origin !== viewerAppUrl.origin || allowedUrl.pathname !== '/allowed.html')) {
    errors.push(`allows_same_origin_navigation.details.url must be same-origin /allowed.html, got ${allowedDetails.url}`);
  }

  const blockedDetails = getDetails(errors, byName.get('blocks_cross_origin_navigation'), 'blocks_cross_origin_navigation');
  const blockedUrl = parseUrl(blockedDetails?.url);
  if (blockedDetails) {
    if (!blockedUrl) {
      errors.push(`blocks_cross_origin_navigation.details.url must be a valid URL, got ${blockedDetails.url}`);
    } else if (blockedOrigin && blockedUrl.origin === blockedOrigin.origin && blockedUrl.pathname === '/blocked.html') {
      errors.push(`blocks_cross_origin_navigation.details.url must not land on blocked origin, got ${blockedDetails.url}`);
    }
  }
  if (blockedDetails && (!Number.isInteger(blockedDetails.blocked_origin_hits) || blockedDetails.blocked_origin_hits < 0)) {
    errors.push('blocks_cross_origin_navigation.details.blocked_origin_hits must be a non-negative integer');
  }

  const externalDetails = getDetails(errors, byName.get('blocks_external_http_navigation'), 'blocks_external_http_navigation');
  const externalLandingUrl = parseUrl(externalDetails?.url);
  if (externalDetails) {
    if (!externalLandingUrl) {
      errors.push(`blocks_external_http_navigation.details.url must be a valid URL, got ${externalDetails.url}`);
    } else if (externalBlockedUrl && externalLandingUrl.href === externalBlockedUrl.href) {
      errors.push(`blocks_external_http_navigation.details.url must not equal external_blocked_url, got ${externalDetails.url}`);
    }
    if (externalDetails.blocked_url !== data.external_blocked_url) {
      errors.push(`blocks_external_http_navigation.details.blocked_url must equal external_blocked_url, got ${externalDetails.blocked_url}`);
    }
    if (externalDetails.external_blocked_hits !== 0) {
      errors.push(`blocks_external_http_navigation.details.external_blocked_hits must be 0, got ${externalDetails.external_blocked_hits}`);
    }
  }

  validateWindowOpenDetails(errors, byName.get('blocks_window_open'), 'blocks_window_open');
}

function validateFileNavigationDetails(errors, data, byName) {
  if (!isNonEmptyString(data.viewer_app_path)) {
    errors.push('viewer_app_path must be a non-empty string');
  }
  const viewerAppUrl = parseUrl(data.viewer_app_url);
  const allowedFileUrl = parseUrl(data.allowed_file_url);
  const blockedFileUrl = parseUrl(data.blocked_file_url);
  if (!viewerAppUrl || viewerAppUrl.protocol !== 'file:') {
    errors.push('viewer_app_url must be a valid file URL');
  }
  if (!allowedFileUrl || allowedFileUrl.protocol !== 'file:') {
    errors.push('allowed_file_url must be a valid file URL');
  }
  if (!blockedFileUrl || blockedFileUrl.protocol !== 'file:') {
    errors.push('blocked_file_url must be a valid file URL');
  }

  const launchDetails = getDetails(errors, byName.get('launches_file_viewer_app_path'), 'launches_file_viewer_app_path');
  if (launchDetails && launchDetails.url !== data.viewer_app_url) {
    errors.push(`launches_file_viewer_app_path.details.url must equal viewer_app_url, got ${launchDetails.url}`);
  }

  const allowedDetails = getDetails(errors, byName.get('allows_viewer_directory_file_navigation'), 'allows_viewer_directory_file_navigation');
  if (allowedDetails && allowedDetails.url !== data.allowed_file_url) {
    errors.push(`allows_viewer_directory_file_navigation.details.url must equal allowed_file_url, got ${allowedDetails.url}`);
  }

  const blockedDetails = getDetails(errors, byName.get('blocks_file_navigation_outside_viewer_directory'), 'blocks_file_navigation_outside_viewer_directory');
  const blockedLandingUrl = parseUrl(blockedDetails?.url);
  if (blockedDetails && !blockedLandingUrl) {
    errors.push(`blocks_file_navigation_outside_viewer_directory.details.url must be a valid URL, got ${blockedDetails.url}`);
  }
  if (blockedDetails && blockedDetails.blocked_url !== data.blocked_file_url) {
    errors.push(`blocks_file_navigation_outside_viewer_directory.details.blocked_url must equal blocked_file_url, got ${blockedDetails.blocked_url}`);
  }
  if (blockedDetails && blockedDetails.url === data.blocked_file_url) {
    errors.push(`blocks_file_navigation_outside_viewer_directory.details.url must not equal blocked_file_url, got ${blockedDetails.url}`);
  }

  validateWindowOpenDetails(errors, byName.get('blocks_file_window_open_outside_viewer_directory'), 'blocks_file_window_open_outside_viewer_directory');
}

function validateWindowOpenDetails(errors, test, name) {
  const details = getDetails(errors, test, name);
  if (!details) return;
  if (!Number.isInteger(details.before_pages) || details.before_pages < 1) {
    errors.push(`${name}.details.before_pages must be a positive integer`);
  }
  if (!Number.isInteger(details.after_pages) || details.after_pages < 0) {
    errors.push(`${name}.details.after_pages must be a non-negative integer`);
  }
  if (Number.isInteger(details.before_pages) && Number.isInteger(details.after_pages) && details.after_pages > details.before_pages) {
    errors.push(`${name}.details.after_pages must be less than or equal to before_pages`);
  }
}

const args = parseArgs(process.argv);
let failed = false;

for (const file of args.files) {
  let data;
  try {
    data = readJson(file);
  } catch (error) {
    console.error(`FAIL: ${file}`);
    console.error(`  ${error.message}`);
    failed = true;
    continue;
  }

  const errors = validate(data, args.type, args);
  if (errors.length) {
    console.error(`FAIL: ${file}`);
    for (const error of errors) {
      console.error(`  ${error}`);
    }
    failed = true;
  } else {
    console.log(`OK: ${file} is a valid ${args.type} smoke result.`);
  }
}

if (failed) process.exit(1);
