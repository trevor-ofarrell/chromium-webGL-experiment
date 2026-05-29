#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
}

function wildcardToRegExp(pattern) {
  const escaped = pattern.replace(/[.+^${}()|[\]\\]/g, '\\$&');
  return new RegExp(`^${escaped.replace(/\*/g, '.*').replace(/\?/g, '.')}$`, 'i');
}

function expandFileArg(fileArg) {
  if (!/[*?]/.test(fileArg)) return [fileArg];

  const dir = path.dirname(fileArg);
  const base = path.basename(fileArg);
  const resolvedDir = path.resolve(dir === '.' ? process.cwd() : dir);
  const matcher = wildcardToRegExp(base);
  if (!fs.existsSync(resolvedDir)) return [fileArg];

  return fs.readdirSync(resolvedDir)
    .filter((entry) => matcher.test(entry))
    .map((entry) => path.join(resolvedDir, entry));
}

function parseArgs(argv) {
  const args = {
    output: '',
    files: [],
    strictSameRevision: false,
    strictOfficial: false,
    strictEvidence: false,
  };
  for (let i = 2; i < argv.length; i += 1) {
    if (argv[i] === '--output') {
      args.output = argv[++i];
    } else if (argv[i] === '--strictSameRevision') {
      args.strictSameRevision = true;
    } else if (argv[i] === '--strictOfficial') {
      args.strictOfficial = true;
    } else if (argv[i] === '--strictEvidence') {
      args.strictEvidence = true;
    } else {
      args.files.push(...expandFileArg(argv[i]));
    }
  }
  if (!args.files.length) {
    throw new Error('Usage: node scripts/compare_results.mjs <result.json...> [--output report.md] [--strictSameRevision] [--strictOfficial] [--strictEvidence]');
  }
  if (args.strictOfficial) {
    args.strictSameRevision = true;
    args.strictEvidence = true;
  }
  return args;
}

function round(value, digits = 2) {
  return Number.isFinite(value) ? value.toFixed(digits) : '';
}

function normalizeInputPath(file) {
  const resolved = path.resolve(file);
  const relative = path.relative(process.cwd(), resolved);
  const displayPath = relative && !relative.startsWith('..') && !path.isAbsolute(relative)
    ? relative
    : resolved;
  return displayPath.split(path.sep).join('/');
}

function inputDigest(files) {
  const entries = files
    .map((file) => {
      const content = fs.readFileSync(file);
      return {
        path: normalizeInputPath(file),
        sha256: crypto.createHash('sha256').update(content).digest('hex'),
        size: content.length,
      };
    })
    .sort((a, b) => a.path.localeCompare(b.path));
  const manifest = entries
    .map((entry) => `${entry.path}\t${entry.sha256}\t${entry.size}`)
    .join('\n');
  return crypto.createHash('sha256').update(manifest).digest('hex');
}

function pct(delta, baseline) {
  if (!Number.isFinite(delta) || !Number.isFinite(baseline) || baseline === 0) return '';
  return `${((delta / baseline) * 100).toFixed(1)}%`;
}

function delta(value, baseline) {
  return Number.isFinite(value) && Number.isFinite(baseline) ? value - baseline : null;
}

function keyOf(result) {
  return `${result.scene_name}|${result.renderer_type}`;
}

function variantOf(result) {
  return result.benchmark_variant || 'unknown';
}

function profileCacheModeOf(result) {
  const mode = typeof result.profile_cache_mode === 'string' ? result.profile_cache_mode.trim() : '';
  return mode || 'fresh-temp';
}

function profileCacheKeyOf(result) {
  const mode = profileCacheModeOf(result);
  if (mode === 'fresh-temp') return 'fresh-temp';
  const key = typeof result.profile_cache_key === 'string' ? result.profile_cache_key.trim() : '';
  return key || 'missing-profile-cache-key';
}

function evidenceClassOf(result) {
  return profileCacheModeOf(result) === 'explicit-reuse'
    ? 'cache-attribution'
    : 'fresh-profile-evidence';
}

function compareRows(results) {
  const byCase = new Map();
  for (const result of results) {
    const key = keyOf(result);
    if (!byCase.has(key)) byCase.set(key, []);
    byCase.get(key).push(result);
  }

  const rows = [];
  for (const [key, caseResults] of [...byCase.entries()].sort()) {
    const [scene, renderer] = key.split('|');
    const baseline =
      caseResults.find((item) => /stock|baseline/i.test(variantOf(item))) ||
      caseResults[0];
    for (const result of caseResults.sort((a, b) => variantOf(a).localeCompare(variantOf(b)))) {
      rows.push({
        scene,
        renderer,
        variant: variantOf(result),
        evidenceClass: evidenceClassOf(result),
        profileCacheMode: profileCacheModeOf(result),
        profileCacheKey: profileCacheKeyOf(result),
        avgFps: result.avg_fps,
        avgFpsDelta: delta(result.avg_fps, baseline.avg_fps),
        oneLowFps: result.one_percent_low_fps,
        oneLowFpsDelta: delta(result.one_percent_low_fps, baseline.one_percent_low_fps),
        pointOneLowFps: result.point_one_percent_low_fps,
        pointOneLowFpsDelta: delta(result.point_one_percent_low_fps, baseline.point_one_percent_low_fps),
        p50: result.p50_frame_ms,
        p50Delta: delta(result.p50_frame_ms, baseline.p50_frame_ms),
        p95: result.p95_frame_ms,
        p95Delta: delta(result.p95_frame_ms, baseline.p95_frame_ms),
        p99: result.p99_frame_ms,
        p99Delta: delta(result.p99_frame_ms, baseline.p99_frame_ms),
        max: result.max_frame_ms,
        maxDelta: delta(result.max_frame_ms, baseline.max_frame_ms),
        cpu: result.avg_cpu_frame_ms,
        cpuDelta: delta(result.avg_cpu_frame_ms, baseline.avg_cpu_frame_ms),
        js: result.avg_js_frame_ms,
        jsDelta: delta(result.avg_js_frame_ms, baseline.avg_js_frame_ms),
        submit: result.avg_render_submission_ms,
        submitDelta: delta(result.avg_render_submission_ms, baseline.avg_render_submission_ms),
        compositor: result.avg_compositor_latency_ms,
        compositorDelta: delta(result.avg_compositor_latency_ms, baseline.avg_compositor_latency_ms),
        presentation: result.avg_presentation_latency_ms,
        presentationDelta: delta(result.avg_presentation_latency_ms, baseline.avg_presentation_latency_ms),
        gpu: result.avg_gpu_frame_ms,
        gpuDelta: delta(result.avg_gpu_frame_ms, baseline.avg_gpu_frame_ms),
        droppedFrames: result.dropped_frames,
        droppedFramesDelta: delta(result.dropped_frames, baseline.dropped_frames),
        startup: result.startup_ms_to_first_frame,
        startupDelta: delta(result.startup_ms_to_first_frame, baseline.startup_ms_to_first_frame),
        rss: result.process_rss_mb,
        rssDelta: delta(result.process_rss_mb, baseline.process_rss_mb),
        jsHeap: result.js_heap_mb,
        jsHeapDelta: delta(result.js_heap_mb, baseline.js_heap_mb),
        gpuMemory: result.gpu_memory_mb,
        gpuMemoryDelta: delta(result.gpu_memory_mb, baseline.gpu_memory_mb),
        drawCalls: result.draw_calls,
        drawCallsDelta: delta(result.draw_calls, baseline.draw_calls),
        triangles: result.triangles,
        trianglesDelta: delta(result.triangles, baseline.triangles),
        textureUpload: result.texture_upload_mb,
        textureUploadDelta: delta(result.texture_upload_mb, baseline.texture_upload_mb),
        bufferUpload: result.buffer_upload_mb,
        bufferUploadDelta: delta(result.buffer_upload_mb, baseline.buffer_upload_mb),
        shaderEvents: result.shader_compile_events,
        shaderEventsDelta: delta(result.shader_compile_events, baseline.shader_compile_events),
        binarySize: result.browser_binary_size_mb,
        binarySizeDelta: delta(result.browser_binary_size_mb, baseline.browser_binary_size_mb),
        viewerBundleSize: result.viewer_bundle_size_mb,
        viewerBundleSizeDelta: delta(result.viewer_bundle_size_mb, baseline.viewer_bundle_size_mb),
        packageSize: result.package_size_mb,
        packageSizeDelta: delta(result.package_size_mb, baseline.package_size_mb),
      });
    }
  }
  return rows;
}

function average(values) {
  const finite = values.filter((value) => Number.isFinite(value));
  if (!finite.length) return null;
  return finite.reduce((sum, value) => sum + value, 0) / finite.length;
}

function variantFamilyOf(row) {
  const suffix = `-${row.scene}-${row.renderer}`;
  return row.variant.endsWith(suffix) ? row.variant.slice(0, -suffix.length) : row.variant;
}

function aggregateRows(rows) {
  const byVariant = new Map();
  for (const row of rows) {
    const key = `${row.renderer}|${variantFamilyOf(row)}|${row.evidenceClass}|${row.profileCacheMode}|${row.profileCacheKey}`;
    if (!byVariant.has(key)) byVariant.set(key, []);
    byVariant.get(key).push(row);
  }

  return [...byVariant.entries()]
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([key, variantRows]) => {
      const [renderer, variant, evidenceClass, profileCacheMode, profileCacheKey] = key.split('|');
      const avgFps = average(variantRows.map((row) => row.avgFps));
      const avgFpsDelta = average(variantRows.map((row) => row.avgFpsDelta));
      return {
        renderer,
        variant,
        evidenceClass,
        profileCacheMode,
        profileCacheKey,
        scenes: variantRows.length,
        avgFps,
        avgFpsDelta,
        avgFpsDeltaPct: avgFps !== null && avgFpsDelta !== null ? pct(avgFpsDelta, avgFps - avgFpsDelta) : '',
        oneLowFpsDelta: average(variantRows.map((row) => row.oneLowFpsDelta)),
        pointOneLowFpsDelta: average(variantRows.map((row) => row.pointOneLowFpsDelta)),
        p95Delta: average(variantRows.map((row) => row.p95Delta)),
        p99Delta: average(variantRows.map((row) => row.p99Delta)),
        maxDelta: average(variantRows.map((row) => row.maxDelta)),
        cpuDelta: average(variantRows.map((row) => row.cpuDelta)),
        jsDelta: average(variantRows.map((row) => row.jsDelta)),
        submitDelta: average(variantRows.map((row) => row.submitDelta)),
        droppedFramesDelta: average(variantRows.map((row) => row.droppedFramesDelta)),
        startupDelta: average(variantRows.map((row) => row.startupDelta)),
        rssDelta: average(variantRows.map((row) => row.rssDelta)),
      };
    });
}

function unique(values) {
  return [...new Set(values)];
}

function hasBaselineVariant(results) {
  return results.some((item) => /stock|baseline/i.test(variantOf(item)));
}

function hasForkVariant(results) {
  return results.some((item) => /fork/i.test(variantOf(item)));
}

function hasExplicitProfileReuse(results) {
  return results.some((item) => profileCacheModeOf(item) === 'explicit-reuse');
}

function softwareRendererReason(result) {
  const haystack = [
    result.gpu_name,
    result.driver_version,
    result.angle_backend,
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

function softwareRenderingDiagnosticOptIn(result) {
  return result.allow_software_rendering === true || result.allowSoftwareRendering === true;
}

function hasGpuMetadata(result) {
  return [result.gpu_name, result.driver_version, result.angle_backend]
    .some((value) => typeof value === 'string' && value.trim().length > 0);
}

const requiredTextEvidenceFields = [
  'chromium_revision',
  'build_args_hash',
  'platform',
  'gpu_name',
  'driver_version',
  'angle_backend',
  'renderer_type',
  'scene_name',
];

const requiredFiniteEvidenceFields = [
  'warmup_seconds',
  'measured_seconds',
  'avg_fps',
  'p50_frame_ms',
  'p95_frame_ms',
  'p99_frame_ms',
  'one_percent_low_fps',
  'point_one_percent_low_fps',
  'avg_cpu_frame_ms',
  'avg_js_frame_ms',
  'avg_render_submission_ms',
  'max_frame_ms',
  'dropped_frames',
  'draw_calls',
  'triangles',
  'texture_upload_mb',
  'buffer_upload_mb',
  'shader_compile_events',
  'process_rss_mb',
  'startup_ms_to_first_frame',
  'browser_binary_size_mb',
  'viewer_bundle_size_mb',
];

const requiredNullableEvidenceFields = [
  'avg_gpu_frame_ms',
  'avg_compositor_latency_ms',
  'avg_presentation_latency_ms',
  'js_heap_mb',
  'gpu_memory_mb',
];

function requiredBenchmarkEvidenceInvalidReason(result) {
  for (const field of requiredTextEvidenceFields) {
    if (typeof result[field] !== 'string' || result[field].trim().length === 0) {
      return `missing evidence ${field}`;
    }
  }
  for (const field of requiredFiniteEvidenceFields) {
    if (!Number.isFinite(result[field])) {
      return `missing evidence ${field}`;
    }
    if (result[field] < 0) {
      return `negative evidence ${field}`;
    }
  }
  for (const field of requiredNullableEvidenceFields) {
    if (!Object.prototype.hasOwnProperty.call(result, field)) {
      return `missing evidence ${field}`;
    }
    if (result[field] !== null && !Number.isFinite(result[field])) {
      return `invalid evidence ${field}`;
    }
    if (Number.isFinite(result[field]) && result[field] < 0) {
      return `negative evidence ${field}`;
    }
  }
  if (!Number.isFinite(result.package_size_mb) || result.package_size_mb <= 0) {
    return 'package_size_mb missing or non-positive';
  }
  if (typeof result.gpu_timing_enabled !== 'boolean') {
    return 'missing evidence gpu_timing_enabled';
  }
  if (!['webgl2', 'webgpu'].includes(result.renderer_type)) {
    return `unsupported renderer_type ${result.renderer_type}`;
  }
  return '';
}

function gpuInstabilityReason(result) {
  if (typeof result.webgpu_device_lost !== 'boolean') return 'missing webgpu_device_lost';
  if (typeof result.webgl_context_currently_lost !== 'boolean') return 'missing webgl_context_currently_lost';
  if (typeof result.webgl_context_lost_count !== 'number' || !Number.isFinite(result.webgl_context_lost_count)) {
    return 'missing webgl_context_lost_count';
  }
  if (typeof result.render_error_count !== 'number' || !Number.isFinite(result.render_error_count)) {
    return 'missing render_error_count';
  }
  if (result.webgpu_device_lost === true) return 'WebGPU device loss';
  if (result.webgl_context_currently_lost === true) return 'WebGL context is currently lost';
  if (result.webgl_context_lost_count > 0) {
    return `WebGL context loss count ${result.webgl_context_lost_count}`;
  }
  if (result.render_error_count > 0) {
    return `render_error_count ${result.render_error_count}`;
  }
  return '';
}

function attributionInstrumentationReason(result) {
  if (result.webgpu_queue_instrumentation_enabled === true) {
    return 'WebGPU queue instrumentation attribution run';
  }
  if (result.webgpu_bind_group_instrumentation_enabled === true) {
    return 'WebGPU bind-group instrumentation attribution run';
  }
  if (result.webgpu_pipeline_state_instrumentation_enabled === true) {
    return 'WebGPU pipeline-state instrumentation attribution run';
  }
  if (result.webgpu_buffer_state_instrumentation_enabled === true) {
    return 'WebGPU buffer-state instrumentation attribution run';
  }
  if (result.webgpu_render_state_instrumentation_enabled === true) {
    return 'WebGPU render-state instrumentation attribution run';
  }
  if (result.webgpu_immediate_instrumentation_enabled === true) {
    return 'WebGPU immediate instrumentation attribution run';
  }
  if (result.viewer_trace_webgpu_queue === true) {
    return 'source WebGPU queue trace attribution run';
  }
  return '';
}

const webGpuCpuFallbackCountFields = [
  'webgpu_cpu_texture_fallback_count',
  'webgpu_cpu_texture_readback_count',
  'webgpu_forced_texture_readback_count',
  'webgpu_copy_external_image_cpu_fallback_count',
  'webgpu_copy_external_image_cpu_readback_count',
  'webgpu_copy_external_image_forced_readback_count',
];

const copyExternalImageExperimentFields = [
  'viewer_skip_webgpu_copy_external_image_color_conversion',
  'viewer_skip_webgpu_copy_external_image_color_space_validation',
  'viewer_skip_webgpu_copy_external_image_dest_validation',
  'viewer_skip_webgpu_copy_external_image_source_validation',
  'viewer_skip_webgpu_copy_external_image_copy_size_validation',
];

function isCopyExternalImageUploadExperiment(result) {
  if (result.renderer_type !== 'webgpu') return false;
  if (copyExternalImageExperimentFields.some((field) => result[field] === true)) return true;
  const variant = variantOf(result).toLowerCase();
  return variant.includes('copy-external-image') ||
    variant.includes('copy-ext-image') ||
    variant.includes('aggressive-upload-fast-path');
}

function webGpuCpuFallbackReason(result) {
  if (result.renderer_type !== 'webgpu') return '';
  if (isCopyExternalImageUploadExperiment(result) &&
      result.viewer_reject_webgpu_cpu_texture_fallback !== true) {
    return 'WebGPU copyExternalImage upload experiment missing CPU texture fallback rejection';
  }
  if (result.webgpu_cpu_texture_fallback_detected === true) {
    return 'WebGPU CPU texture fallback/readback detected';
  }
  const verdict = typeof result.webgpu_texture_copy_path_verdict === 'string'
    ? result.webgpu_texture_copy_path_verdict.trim().toLowerCase()
    : '';
  if (verdict === 'cpu-fallback-detected' || verdict === 'cpu-fallback-rejected' || verdict === 'forced-readback-detected') {
    return `WebGPU CPU texture fallback/readback verdict ${result.webgpu_texture_copy_path_verdict}`;
  }
  for (const field of webGpuCpuFallbackCountFields) {
    if (Number.isFinite(result[field]) && result[field] > 0) {
      return `WebGPU CPU texture fallback/readback ${field}=${result[field]}`;
    }
  }
  return '';
}

const trustedViewerExperimentFields = [
  'viewer_aggressive_gpu',
  'viewer_relaxed_webgl_validation',
  'viewer_zero_copy',
  'viewer_in_process_gpu',
  'viewer_single_process',
  'viewer_disable_unneeded_blink_features',
  'viewer_direct_gpu_presentation',
  'viewer_defer_webgpu_pipeline_flush',
  'viewer_defer_webgpu_queue_flush',
  'viewer_defer_webgpu_submit_flush',
  'viewer_skip_webgpu_canvas_texture_validation',
  'viewer_skip_webgpu_canvas_memory_accounting',
  'viewer_skip_webgpu_copy_external_image_color_conversion',
  'viewer_skip_webgpu_copy_external_image_color_space_validation',
  'viewer_skip_webgpu_copy_external_image_dest_validation',
  'viewer_skip_webgpu_copy_external_image_source_validation',
  'viewer_skip_webgpu_copy_external_image_copy_size_validation',
  'viewer_skip_webgpu_write_texture_layout_validation',
  'viewer_reject_webgpu_cpu_texture_fallback',
  'viewer_skip_webgpu_use_counters',
  'viewer_cache_webgpu_bind_group_layouts',
  'viewer_skip_webgpu_command_labels',
  'viewer_skip_webgpu_resource_labels',
  'viewer_skip_webgpu_shader_source_null_check',
  'viewer_skip_webgpu_shader_memory_accounting',
  'viewer_skip_webgpu_redundant_pipeline_sets',
  'viewer_skip_webgpu_redundant_bind_group_sets',
  'viewer_skip_webgpu_redundant_buffer_sets',
  'viewer_skip_webgpu_redundant_render_state_sets',
  'viewer_trace_webgpu_queue',
];

const webGpuOnlyTrustedViewerExperimentFields = [
  'viewer_defer_webgpu_pipeline_flush',
  'viewer_defer_webgpu_queue_flush',
  'viewer_defer_webgpu_submit_flush',
  'viewer_skip_webgpu_canvas_texture_validation',
  'viewer_skip_webgpu_canvas_memory_accounting',
  'viewer_skip_webgpu_copy_external_image_color_conversion',
  'viewer_skip_webgpu_copy_external_image_color_space_validation',
  'viewer_skip_webgpu_copy_external_image_dest_validation',
  'viewer_skip_webgpu_copy_external_image_source_validation',
  'viewer_skip_webgpu_copy_external_image_copy_size_validation',
  'viewer_skip_webgpu_write_texture_layout_validation',
  'viewer_reject_webgpu_cpu_texture_fallback',
  'viewer_skip_webgpu_use_counters',
  'viewer_cache_webgpu_bind_group_layouts',
  'viewer_skip_webgpu_command_labels',
  'viewer_skip_webgpu_resource_labels',
  'viewer_skip_webgpu_shader_source_null_check',
  'viewer_skip_webgpu_shader_memory_accounting',
  'viewer_skip_webgpu_redundant_pipeline_sets',
  'viewer_skip_webgpu_redundant_bind_group_sets',
  'viewer_skip_webgpu_redundant_buffer_sets',
  'viewer_skip_webgpu_redundant_render_state_sets',
  'viewer_trace_webgpu_queue',
];

const webGl2OnlyTrustedViewerExperimentFields = [
  'viewer_relaxed_webgl_validation',
  'viewer_zero_copy',
];

const trustedBrowserExperimentSwitches = [
  '--use-webgpu-adapter',
  '--enable-dawn-features',
  '--disable-dawn-features',
  '--enable-features',
  '--disable-features',
  '--enable-gpu-memory-buffer-compositor-resources',
  '--ui-enable-zero-copy',
  '--enable-gpu-rasterization',
  '--disable-frame-rate-limit',
  '--disable-gpu-vsync',
];

const defaultBenchmarkDisabledFeatures = new Set([
  'translate',
  'optimizationhints',
  'autofillservercommunication',
]);

function hasSwitchValue(result, field) {
  const value = result[field];
  if (typeof value !== 'string') return false;
  const normalized = value.trim().toLowerCase();
  return normalized.length > 0 && normalized !== 'default' && normalized !== 'null';
}

function splitFeatureList(value) {
  return String(value ?? '')
    .split(',')
    .map((feature) => feature.trim().toLowerCase())
    .filter(Boolean);
}

function isDefaultBenchmarkDisableFeaturesValue(value) {
  const features = splitFeatureList(value);
  return features.length > 0 && features.every((feature) => defaultBenchmarkDisabledFeatures.has(feature));
}

function trustedBrowserExperimentFlags(result) {
  if (!Array.isArray(result.browser_flags)) return [];
  const flags = [];
  for (let index = 0; index < result.browser_flags.length; index += 1) {
    const rawFlag = result.browser_flags[index];
    const flag = String(rawFlag);
    if (flag === '--disable-features') {
      const value = index + 1 < result.browser_flags.length ? String(result.browser_flags[index + 1]) : '';
      if (isDefaultBenchmarkDisableFeaturesValue(value)) {
        index += 1;
        continue;
      }
      flags.push(value ? `${flag}=${value}` : flag);
      if (value) index += 1;
      continue;
    }
    if (flag.startsWith('--disable-features=')) {
      if (!isDefaultBenchmarkDisableFeaturesValue(flag.slice('--disable-features='.length))) {
        flags.push(flag);
      }
      continue;
    }
    if (trustedBrowserExperimentSwitches.some((switchName) => flag === switchName || flag.startsWith(`${switchName}=`))) {
      flags.push(flag);
    }
  }
  return flags;
}

function trustedExperimentInvalidReason(result) {
  const enabledMetadata = trustedViewerExperimentFields.filter((field) => result[field] === true);
  if (hasSwitchValue(result, 'viewer_force_angle_backend')) {
    enabledMetadata.push('viewer_force_angle_backend');
  }
  const enabledBrowserFlags = trustedBrowserExperimentFlags(result);
  if (!enabledMetadata.length && !enabledBrowserFlags.length) return '';

  const enabled = [...enabledMetadata, ...enabledBrowserFlags];
  if (result.viewer_mode !== true || result.viewer_trusted_content !== true) {
    return `trusted experiment requires viewer_mode=true and viewer_trusted_content=true (${enabled.join(', ')})`;
  }

  const webGpuOnly = webGpuOnlyTrustedViewerExperimentFields.find((field) => result[field] === true);
  if (webGpuOnly && result.renderer_type !== 'webgpu') {
    return `WebGPU trusted experiment ${webGpuOnly} used with renderer_type=${result.renderer_type}`;
  }
  const webGl2Only = webGl2OnlyTrustedViewerExperimentFields.find((field) => result[field] === true);
  if (webGl2Only && result.renderer_type !== 'webgl2') {
    return `WebGL2 trusted experiment ${webGl2Only} used with renderer_type=${result.renderer_type}`;
  }
  return '';
}

function flagValues(flags, switchName) {
  if (!Array.isArray(flags)) return [];
  const values = [];
  const prefix = `${switchName}=`;
  for (let index = 0; index < flags.length; index += 1) {
    const flag = String(flags[index]);
    if (flag === switchName && index + 1 < flags.length) {
      values.push(String(flags[index + 1]));
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

function isWebGpuBlobCacheHashValidationExperiment(result) {
  if (result.renderer_type !== 'webgpu') return false;
  if (result.webgpu_blob_cache_hash_validation_disabled === true) return true;
  if (/blob-cache-hash-validation/i.test(variantOf(result))) return true;
  return flagTokenListIncludes(result.browser_flags, '--disable-dawn-features', 'blob_cache_hash_validation');
}

function webGpuBlobCacheInvalidReason(result) {
  if (!isWebGpuBlobCacheHashValidationExperiment(result)) return '';
  if (result.webgpu_blob_cache_expected_available !== true) {
    return 'missing webgpu_blob_cache_expected_available=true';
  }
  if (result.webgpu_blob_cache_origin_eligible !== true) {
    return 'missing webgpu_blob_cache_origin_eligible=true';
  }
  if (result.webgpu_blob_cache_disabled_by_explicit_toggle === true ||
      flagTokenListIncludes(result.browser_flags, '--enable-dawn-features', 'disable_blob_cache')) {
    return 'Dawn disable_blob_cache enabled';
  }
  if (!['http', 'https'].includes(result.viewer_url_scheme)) {
    return 'missing HTTP(S) viewer_url_scheme';
  }
  if (typeof result.viewer_origin !== 'string' || result.viewer_origin.trim().length === 0) {
    return 'missing viewer_origin';
  }
  return '';
}

function numericEquals(left, right) {
  return typeof left === 'number' &&
    Number.isFinite(left) &&
    typeof right === 'number' &&
    Number.isFinite(right) &&
    Math.abs(left - right) < 0.001;
}

function validateComparisonInputs(results, args) {
  const errors = [];
  const revisions = unique(results.map((result) => result.chromium_revision).filter(Boolean));

  const cacheIneligibleWebGpu = results
    .map((result) => ({ result, reason: webGpuBlobCacheInvalidReason(result) }))
    .filter((entry) => entry.reason)
    .map((entry) => `${variantOf(entry.result)} ${entry.result.scene_name}/${entry.result.renderer_type} (${entry.reason})`);
  if (cacheIneligibleWebGpu.length) {
    errors.push(`Comparison inputs cannot use cache-ineligible WebGPU blob-cache hash-validation results. Disallowed: ${cacheIneligibleWebGpu.join(', ')}`);
  }

  const webGpuCpuFallbackResults = results
    .map((result) => ({ result, reason: webGpuCpuFallbackReason(result) }))
    .filter((entry) => entry.reason)
    .map((entry) => `${variantOf(entry.result)} ${entry.result.scene_name}/${entry.result.renderer_type} (${entry.reason})`);
  if (webGpuCpuFallbackResults.length) {
    errors.push(`Comparison inputs cannot use WebGPU CPU texture fallback/readback results. Disallowed: ${webGpuCpuFallbackResults.join(', ')}`);
  }

  const untrustedExperiments = results
    .map((result) => ({ result, reason: trustedExperimentInvalidReason(result) }))
    .filter((entry) => entry.reason)
    .map((entry) => `${variantOf(entry.result)} ${entry.result.scene_name}/${entry.result.renderer_type} (${entry.reason})`);
  if (untrustedExperiments.length) {
    errors.push(`Comparison inputs cannot use trusted-only experiment metadata or browser flags without trusted viewer provenance. Disallowed: ${untrustedExperiments.join(', ')}`);
  }

  if (args.strictSameRevision) {
    if (revisions.length !== 1) {
      errors.push(`Expected exactly one chromium_revision across comparison inputs, found ${revisions.length || 0}: ${revisions.join(', ') || 'none'}`);
    }
  }

  if (args.strictEvidence) {
    const missingRequiredEvidence = results
      .map((result) => ({ result, reason: requiredBenchmarkEvidenceInvalidReason(result) }))
      .filter((entry) => entry.reason)
      .map((entry) => `${variantOf(entry.result)} ${entry.result.scene_name || 'missing-scene'}/${entry.result.renderer_type || 'missing-renderer'} (${entry.reason})`);
    if (missingRequiredEvidence.length) {
      const label = args.strictOfficial ? 'Official comparisons' : 'Strict comparison reports';
      errors.push(`${label} require complete benchmark metric and positive package-size evidence on every result. Missing/invalid: ${missingRequiredEvidence.join(', ')}`);
    }

    const attributionRuns = results
      .map((result) => ({ result, reason: attributionInstrumentationReason(result) }))
      .filter((entry) => entry.reason)
      .map((entry) => `${variantOf(entry.result)} ${entry.result.scene_name || 'missing-scene'}/${entry.result.renderer_type || 'missing-renderer'} (${entry.reason})`);
    if (attributionRuns.length) {
      const label = args.strictOfficial ? 'Official comparisons' : 'Strict comparison reports';
      errors.push(`${label} cannot use attribution-instrumented results as clean speed evidence. Disallowed: ${attributionRuns.join(', ')}`);
    }
  }

  if (args.strictOfficial) {
    const checkoutStates = unique(results.map((result) => result.browser_is_from_checkout));
    if (checkoutStates.length !== 1 || checkoutStates[0] !== true) {
      errors.push('Official comparisons require all results to come from checkout-built browser binaries (browser_is_from_checkout=true).');
    }

    const missingBuildArgs = results
      .filter((result) => !result.build_args_hash)
      .map((result) => `${variantOf(result)} ${result.scene_name}/${result.renderer_type}`);
    if (missingBuildArgs.length) {
      errors.push(`Official comparisons require build_args_hash on every result. Missing: ${missingBuildArgs.join(', ')}`);
    }

    const smokeVariants = results
      .filter((result) => /smoke|installed/i.test(variantOf(result)))
      .map((result) => variantOf(result));
    if (smokeVariants.length) {
      errors.push(`Official comparisons cannot include smoke or installed-browser variants: ${unique(smokeVariants).join(', ')}`);
    }

    const softwareRendered = results
      .map((result) => ({ result, reason: softwareRendererReason(result) }))
      .filter((entry) => entry.reason)
      .map((entry) => `${variantOf(entry.result)} ${entry.result.scene_name}/${entry.result.renderer_type} (${entry.reason})`);
    if (softwareRendered.length) {
      errors.push(`Official comparisons cannot use known software-rendered GPU paths. Disallowed: ${softwareRendered.join(', ')}`);
    }

    const softwareRenderingOptIns = results
      .filter((result) => softwareRenderingDiagnosticOptIn(result))
      .map((result) => `${variantOf(result)} ${result.scene_name}/${result.renderer_type}`);
    if (softwareRenderingOptIns.length) {
      errors.push(`Official comparisons cannot use diagnostic software-rendering opt-in results. Disallowed: ${softwareRenderingOptIns.join(', ')}`);
    }

    const missingGpuMetadata = results
      .filter((result) => !hasGpuMetadata(result))
      .map((result) => `${variantOf(result)} ${result.scene_name}/${result.renderer_type}`);
    if (missingGpuMetadata.length) {
      errors.push(`Official comparisons require GPU/backend metadata on every result. Missing: ${missingGpuMetadata.join(', ')}`);
    }

    const unstableGpuResults = results
      .map((result) => ({ result, reason: gpuInstabilityReason(result) }))
      .filter((entry) => entry.reason)
      .map((entry) => `${variantOf(entry.result)} ${entry.result.scene_name}/${entry.result.renderer_type} (${entry.reason})`);
    if (unstableGpuResults.length) {
      errors.push(`Official comparisons cannot use GPU-unstable results. Disallowed: ${unstableGpuResults.join(', ')}`);
    }

    const forkResults = results.filter((result) => /fork/i.test(variantOf(result)));
    const nonForkWithForkRevision = results
      .filter((result) => !/fork/i.test(variantOf(result)) && result.fork_revision)
      .map((result) => `${variantOf(result)} ${result.scene_name}/${result.renderer_type}`);
    if (nonForkWithForkRevision.length) {
      errors.push(`Official comparisons require fork_revision only on fork variants. Unexpected: ${nonForkWithForkRevision.join(', ')}`);
    }

    const missingForkRevision = forkResults
      .filter((result) => !result.fork_revision)
      .map((result) => `${variantOf(result)} ${result.scene_name}/${result.renderer_type}`);
    if (missingForkRevision.length) {
      errors.push(`Official comparisons require fork_revision on every fork result. Missing: ${missingForkRevision.join(', ')}`);
    }

    const forkRevisions = unique(forkResults.map((result) => result.fork_revision).filter(Boolean));
    if (forkRevisions.length > 1) {
      errors.push(`Official comparisons require one fork_revision across fork results. Found: ${forkRevisions.join(', ')}`);
    }
    if (revisions.length === 1) {
      const chromiumRevision = revisions[0];
      const mismatchedForkRevisions = forkRevisions.filter((revision) => !revision.startsWith(`${chromiumRevision}+viewerpatch-`));
      if (mismatchedForkRevisions.length) {
        errors.push(`Official fork_revision values must be derived from chromium_revision ${chromiumRevision} and the viewer patch-series hash. Mismatched: ${mismatchedForkRevisions.join(', ')}`);
      }
    }

    const byCase = new Map();
    for (const result of results) {
      const key = keyOf(result);
      if (!byCase.has(key)) byCase.set(key, []);
      byCase.get(key).push(result);
    }

    for (const [key, caseResults] of byCase) {
      if (!hasBaselineVariant(caseResults)) {
        errors.push(`Missing baseline/stock variant for ${key}.`);
      }
      if (!hasForkVariant(caseResults)) {
        errors.push(`Missing fork variant for ${key}.`);
      }
      const first = caseResults[0];
      const mismatchedDuration = caseResults.filter((result) => !numericEquals(result.measured_seconds, first.measured_seconds));
      if (mismatchedDuration.length) {
        errors.push(`Official comparison inputs for ${key} must use the same measured_seconds. Values: ${unique(caseResults.map((result) => result.measured_seconds)).join(', ')}`);
      }
      const mismatchedWarmup = caseResults.filter((result) => !numericEquals(result.warmup_seconds, first.warmup_seconds));
      if (mismatchedWarmup.length) {
        errors.push(`Official comparison inputs for ${key} must use the same warmup_seconds. Values: ${unique(caseResults.map((result) => result.warmup_seconds)).join(', ')}`);
      }
      const profileCacheModes = unique(caseResults.map(profileCacheModeOf));
      if (profileCacheModes.length > 1) {
        errors.push(`Official comparison inputs for ${key} must use the same profile_cache_mode. Values: ${profileCacheModes.join(', ')}`);
      }
      const profileCacheKeys = unique(caseResults.map(profileCacheKeyOf));
      if (profileCacheKeys.length > 1) {
        errors.push(`Official comparison inputs for ${key} must use the same profile_cache_key. Values: ${profileCacheKeys.join(', ')}`);
      }
      if (profileCacheModeOf(first) === 'explicit-reuse' && profileCacheKeyOf(first) === 'missing-profile-cache-key') {
        errors.push(`Official comparison inputs for ${key} using explicit profile reuse must include profile_cache_key.`);
      }
    }
  }

  if (errors.length) {
    throw new Error(`Comparison input validation failed:\n- ${errors.join('\n- ')}`);
  }
}

const args = parseArgs(process.argv);
const results = args.files.map((file) => readJson(file));
const digest = inputDigest(args.files);
validateComparisonInputs(results, args);
const rows = compareRows(results);
const aggregates = aggregateRows(rows);

const lines = [
  '# Benchmark Comparison',
  '',
  `Generated from ${results.length} result file(s). Baseline per scene/renderer is the first variant whose name contains stock or baseline, falling back to the first result.`,
  `Input file digest: \`${digest}\``,
  args.strictOfficial ? 'Strict official input validation was enabled: all inputs must come from checkout-built binaries, share one Chromium revision, include complete benchmark metric evidence with explicit GPU timing mode and positive package-size evidence, include build-args hashes, include patch-series-derived fork revisions for fork variants, contain baseline plus fork variants for every scene/renderer, use matching measured/warmup seconds and profile-cache mode/key per case, include GPU/backend metadata, reject cache-ineligible WebGPU blob-cache experiments, reject explicit WebGPU CPU texture fallback/readback metadata or copyExternalImage upload experiments missing CPU-fallback rejection, reject trusted-only experiment metadata or browser flags without trusted viewer provenance, and avoid known software-rendered GPU paths.' : '',
  args.strictEvidence && !args.strictOfficial ? 'Strict comparison evidence validation was enabled: all rows must include complete benchmark metric evidence, explicit GPU timing mode, and positive package-size evidence before this report is written.' : '',
  hasExplicitProfileReuse(results) ? 'Profile-cache note: this report includes explicit profile-reuse results. Treat these rows as cache-attribution only; retained speed claims still require a matching fresh-profile candidate-analysis gate.' : '',
  '',
  '| Scene | Renderer | Variant | Evidence | Profile Cache | Avg FPS | FPS Delta | FPS Delta % | 1% Low | 1% Low Delta | 0.1% Low | 0.1% Low Delta | P50 ms | P50 Delta | P95 ms | P95 Delta | P99 ms | P99 Delta | Max ms | Max Delta | CPU ms | CPU Delta | JS ms | JS Delta | Submit ms | Submit Delta | Compositor ms | Compositor Delta | Present ms | Present Delta | GPU ms | GPU Delta | Dropped | Dropped Delta | Startup ms | Startup Delta | RSS MB | RSS Delta | JS heap MB | JS heap Delta | GPU memory MB | GPU memory Delta | Draw calls | Draw calls Delta | Triangles | Triangles Delta | Texture MB | Texture Delta | Buffer MB | Buffer Delta | Shader events | Shader events Delta | Binary MB | Binary Delta | Viewer MB | Viewer Delta | Package MB | Package Delta |',
  '| --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |',
  ...rows.map((row) => [
    row.scene,
    row.renderer,
    row.variant,
    row.evidenceClass,
    `${row.profileCacheMode}/${row.profileCacheKey}`,
    round(row.avgFps, 1),
    round(row.avgFpsDelta, 1),
    pct(row.avgFpsDelta, row.avgFps - row.avgFpsDelta),
    round(row.oneLowFps, 1),
    round(row.oneLowFpsDelta, 1),
    round(row.pointOneLowFps, 1),
    round(row.pointOneLowFpsDelta, 1),
    round(row.p50, 2),
    round(row.p50Delta, 2),
    round(row.p95, 2),
    round(row.p95Delta, 2),
    round(row.p99, 2),
    round(row.p99Delta, 2),
    round(row.max, 2),
    round(row.maxDelta, 2),
    round(row.cpu, 2),
    round(row.cpuDelta, 2),
    round(row.js, 2),
    round(row.jsDelta, 2),
    round(row.submit, 2),
    round(row.submitDelta, 2),
    round(row.compositor, 2),
    round(row.compositorDelta, 2),
    round(row.presentation, 2),
    round(row.presentationDelta, 2),
    round(row.gpu, 3),
    round(row.gpuDelta, 3),
    round(row.droppedFrames, 0),
    round(row.droppedFramesDelta, 0),
    round(row.startup, 0),
    round(row.startupDelta, 0),
    round(row.rss, 1),
    round(row.rssDelta, 1),
    round(row.jsHeap, 1),
    round(row.jsHeapDelta, 1),
    round(row.gpuMemory, 1),
    round(row.gpuMemoryDelta, 1),
    round(row.drawCalls, 0),
    round(row.drawCallsDelta, 0),
    round(row.triangles, 0),
    round(row.trianglesDelta, 0),
    round(row.textureUpload, 1),
    round(row.textureUploadDelta, 1),
    round(row.bufferUpload, 1),
    round(row.bufferUploadDelta, 1),
    round(row.shaderEvents, 0),
    round(row.shaderEventsDelta, 0),
    round(row.binarySize, 1),
    round(row.binarySizeDelta, 1),
    round(row.viewerBundleSize, 1),
    round(row.viewerBundleSizeDelta, 1),
    round(row.packageSize, 1),
    round(row.packageSizeDelta, 1),
  ].join(' | ')).map((line) => `| ${line} |`),
  '',
  '## Aggregate Averages',
  '',
  'Averages are arithmetic means across the scene rows included in this report. Delta columns are relative to each scene/renderer baseline before averaging.',
  '',
  '| Renderer | Variant | Evidence | Profile Cache | Scenes | Avg FPS | Avg FPS Delta | Avg FPS Delta % | Avg 1% Low Delta | Avg 0.1% Low Delta | Avg P95 Delta ms | Avg P99 Delta ms | Avg Max Delta ms | Avg CPU Delta ms | Avg JS Delta ms | Avg Submit Delta ms | Avg Dropped Delta | Avg Startup Delta ms | Avg RSS Delta MB |',
  '| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |',
  ...aggregates.map((row) => [
    row.renderer,
    row.variant,
    row.evidenceClass,
    `${row.profileCacheMode}/${row.profileCacheKey}`,
    row.scenes,
    round(row.avgFps, 2),
    round(row.avgFpsDelta, 2),
    row.avgFpsDeltaPct,
    round(row.oneLowFpsDelta, 2),
    round(row.pointOneLowFpsDelta, 2),
    round(row.p95Delta, 2),
    round(row.p99Delta, 2),
    round(row.maxDelta, 2),
    round(row.cpuDelta, 2),
    round(row.jsDelta, 2),
    round(row.submitDelta, 2),
    round(row.droppedFramesDelta, 2),
    round(row.startupDelta, 2),
    round(row.rssDelta, 2),
  ].join(' | ')).map((line) => `| ${line} |`),
  '',
];

const markdown = lines.join('\n');
if (args.output) {
  fs.mkdirSync(path.dirname(args.output), { recursive: true });
  fs.writeFileSync(args.output, markdown);
  console.log(`Wrote ${args.output}`);
} else {
  console.log(markdown);
}
