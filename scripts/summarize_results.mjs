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
    files: [],
    output: '',
    strictEvidence: false,
  };
  for (let i = 2; i < argv.length; i += 1) {
    if (argv[i] === '--output') {
      args.output = argv[++i];
    } else if (argv[i] === '--strictEvidence') {
      args.strictEvidence = true;
    } else {
      args.files.push(...expandFileArg(argv[i]));
    }
  }
  if (!args.files.length) {
    throw new Error('Usage: node scripts/summarize_results.mjs <result.json...> [--output report.md] [--strictEvidence]');
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

function variantOf(result) {
  return result.benchmark_variant || 'unknown';
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

function validateStrictEvidence(results) {
  const invalid = results
    .map((result) => ({ result, reason: requiredBenchmarkEvidenceInvalidReason(result) }))
    .filter((entry) => entry.reason)
    .map((entry) => `${variantOf(entry.result)} ${entry.result.scene_name || 'missing-scene'}/${entry.result.renderer_type || 'missing-renderer'} (${entry.reason})`);

  if (invalid.length) {
    throw new Error(`Summary input validation failed:\n- Strict summaries require complete benchmark metric and positive package-size evidence. Missing/invalid: ${invalid.join(', ')}`);
  }

  const attributionRuns = results
    .map((result) => ({ result, reason: attributionInstrumentationReason(result) }))
    .filter((entry) => entry.reason)
    .map((entry) => `${variantOf(entry.result)} ${entry.result.scene_name || 'missing-scene'}/${entry.result.renderer_type || 'missing-renderer'} (${entry.reason})`);

  if (attributionRuns.length) {
    throw new Error(`Summary input validation failed:\n- Strict summaries cannot use attribution-instrumented results as clean speed evidence. Disallowed: ${attributionRuns.join(', ')}`);
  }
}

function row(result) {
  return [
    result.scene_name,
    result.renderer_type,
    variantOf(result),
    round(result.avg_fps, 1),
    round(result.one_percent_low_fps, 1),
    round(result.point_one_percent_low_fps, 1),
    round(result.p50_frame_ms, 2),
    round(result.p95_frame_ms, 2),
    round(result.p99_frame_ms, 2),
    round(result.max_frame_ms, 2),
    round(result.avg_cpu_frame_ms, 2),
    round(result.avg_gpu_frame_ms, 3),
    round(result.avg_js_frame_ms, 3),
    round(result.avg_render_submission_ms, 2),
    round(result.avg_compositor_latency_ms, 2),
    round(result.avg_presentation_latency_ms, 2),
    result.dropped_frames ?? '',
    result.draw_calls ?? '',
    result.triangles ?? '',
    round(result.texture_upload_mb, 1),
    round(result.buffer_upload_mb, 1),
    result.shader_compile_events ?? '',
    round(result.js_heap_mb, 1),
    round(result.gpu_memory_mb, 1),
    round(result.process_rss_mb, 0),
    round(result.startup_ms_to_first_frame, 0),
    round(result.browser_binary_size_mb, 1),
    round(result.viewer_bundle_size_mb, 1),
    round(result.package_size_mb, 1),
  ].join(' | ');
}

function hasFastPathCoverage(result) {
  return [
    'webgpu_queue_write_texture_common_layout_count',
    'webgpu_queue_write_texture_common_extent_count',
    'webgpu_queue_copy_external_image_default_origin_count',
    'webgpu_queue_copy_external_image_common_origin_count',
    'webgpu_queue_copy_external_image_explicit_common_origin_count',
    'webgpu_queue_copy_external_image_full_source_count',
    'webgpu_pipeline_descriptor_stack_fast_path_eligible_count',
    'webgpu_pipeline_descriptor_measured_stack_fast_path_eligible_count',
  ].some((field) => Object.prototype.hasOwnProperty.call(result, field));
}

function integerMetric(result, field) {
  return Number.isFinite(result[field]) ? String(Math.round(result[field])) : '';
}

function fastPathCoverageRow(result) {
  return [
    result.scene_name,
    result.renderer_type,
    variantOf(result),
    integerMetric(result, 'webgpu_queue_write_texture_count'),
    integerMetric(result, 'webgpu_queue_write_texture_common_layout_count'),
    integerMetric(result, 'webgpu_queue_write_texture_common_extent_count'),
    integerMetric(result, 'webgpu_queue_copy_external_image_count'),
    integerMetric(result, 'webgpu_queue_copy_external_image_default_origin_count'),
    integerMetric(result, 'webgpu_queue_copy_external_image_common_origin_count'),
    integerMetric(result, 'webgpu_queue_copy_external_image_explicit_common_origin_count'),
    integerMetric(result, 'webgpu_queue_copy_external_image_srgb_destination_count'),
    integerMetric(result, 'webgpu_queue_copy_external_image_full_source_count'),
    integerMetric(result, 'webgpu_pipeline_descriptor_stack_fast_path_eligible_count'),
    integerMetric(result, 'webgpu_pipeline_descriptor_measured_stack_fast_path_eligible_count'),
  ].join(' | ');
}

const { files, output, strictEvidence } = parseArgs(process.argv);
const results = files.map((file) => readJson(file));
const digest = inputDigest(files);
if (strictEvidence) validateStrictEvidence(results);
results.sort((a, b) => `${a.renderer_type}:${a.scene_name}:${variantOf(a)}`.localeCompare(`${b.renderer_type}:${b.scene_name}:${variantOf(b)}`));
const fastPathCoverageResults = results.filter(hasFastPathCoverage);

const lines = [
  '# Benchmark Summary',
  '',
  `Generated from ${results.length} result file(s).`,
  `Input file digest: \`${digest}\``,
  strictEvidence ? 'Strict summary evidence validation was enabled: all rows must include complete benchmark metric evidence, explicit GPU timing mode, positive package-size evidence, and no attribution instrumentation before this report is written.' : '',
  '',
  '| Scene | Renderer | Variant | Avg FPS | 1% Low FPS | 0.1% Low FPS | P50 ms | P95 ms | P99 ms | Max ms | CPU ms | GPU ms | JS ms | Submit ms | Compositor ms | Present ms | Dropped | Draw calls | Triangles | Texture MB | Buffer MB | Shader events | JS heap MB | GPU memory MB | RSS MB | Startup ms | Binary MB | Viewer MB | Package MB |',
  '| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |',
  ...results.map(row).map((line) => `| ${line} |`),
  '',
  ...(fastPathCoverageResults.length > 0 ? [
    '## WebGPU Fast-Path Coverage',
    '',
    'These counters are diagnostic attribution only. They show whether WebGPU queue and pipeline descriptors match source fast paths; they are not standalone speed evidence.',
    '',
    '| Scene | Renderer | Variant | WriteTexture calls | Common writeTexture layout | Common writeTexture extent | CopyExternal calls | Default source origin | Common source origin | Explicit common source origin | sRGB destination | Full-source copy | Pipeline stack-eligible descriptors | Measured stack-eligible descriptors |',
    '| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |',
    ...fastPathCoverageResults.map(fastPathCoverageRow).map((line) => `| ${line} |`),
    '',
  ] : []),
  'Unavailable metrics are intentionally blank.',
  '',
];

const markdown = lines.join('\n');
if (output) {
  fs.mkdirSync(path.dirname(output), { recursive: true });
  fs.writeFileSync(output, markdown);
  console.log(`Wrote ${output}`);
} else {
  console.log(markdown);
}
