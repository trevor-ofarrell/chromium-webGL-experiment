#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

function parseArgs(argv) {
  const args = {
    trace: '',
    output: '',
    limit: 30,
    rejectWebGpuCpuFallback: false,
  };
  for (let i = 2; i < argv.length; i += 1) {
    if (argv[i] === '--output') {
      args.output = argv[++i];
    } else if (argv[i] === '--limit') {
      args.limit = Number(argv[++i]);
    } else if (argv[i] === '--rejectWebGpuCpuFallback') {
      args.rejectWebGpuCpuFallback = true;
    } else if (!args.trace) {
      args.trace = argv[i];
    } else {
      throw new Error(`Unexpected argument: ${argv[i]}`);
    }
  }
  if (!args.trace) {
    throw new Error('Usage: node scripts/summarize_trace.mjs <trace.json> [--output report.md] [--limit 30] [--rejectWebGpuCpuFallback]');
  }
  return args;
}

function round(value, digits = 2) {
  return Number.isFinite(value) ? value.toFixed(digits) : '';
}

function eventDurationMs(event) {
  return Number.isFinite(event.dur) ? event.dur / 1000 : 0;
}

function numericArg(event, name) {
  const value = event?.args?.[name];
  return Number.isFinite(value) ? value : 0;
}

function formatMiB(bytes) {
  return bytes > 0 ? round(bytes / (1024 * 1024), 2) : '';
}

function sidecarPathForTrace(tracePath) {
  return path.resolve(tracePath).replace(/\.json$/i, '.result.json');
}

function readJsonIfExists(file) {
  if (!fs.existsSync(file)) return null;
  return JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
}

function coverageMetric(record, field) {
  if (Number.isFinite(record?.[field])) return String(Math.round(record[field]));
  if (Number.isFinite(record?.benchmark_result?.[field])) {
    return String(Math.round(record.benchmark_result[field]));
  }
  return '';
}

function hasFastPathCoverage(record) {
  return [
    'webgpu_queue_write_texture_common_layout_count',
    'webgpu_queue_write_texture_common_extent_count',
    'webgpu_queue_copy_external_image_default_origin_count',
    'webgpu_queue_copy_external_image_common_origin_count',
    'webgpu_queue_copy_external_image_explicit_common_origin_count',
    'webgpu_queue_copy_external_image_srgb_destination_count',
    'webgpu_queue_copy_external_image_full_source_count',
    'webgpu_pipeline_descriptor_stack_fast_path_eligible_count',
    'webgpu_pipeline_descriptor_measured_stack_fast_path_eligible_count',
  ].some((field) => coverageMetric(record, field) !== '');
}

function classify(name) {
  if (/shader|compile|link|program|pipeline/i.test(name)) return 'shader_or_pipeline';
  if (/texture|upload|teximage|texsubimage|copytexture/i.test(name)) return 'texture_upload';
  if (/webgpu|dawn|gpu|gles|command.?buffer/i.test(name)) return 'gpu_command';
  if (/swap|present|submit|compositor|surface|viz/i.test(name)) return 'presentation';
  if (/v8|script|function|evaluate/i.test(name)) return 'javascript';
  return 'other';
}

const args = parseArgs(process.argv);
const trace = JSON.parse(fs.readFileSync(args.trace, 'utf8').replace(/^\uFEFF/, ''));
const sidecarPath = sidecarPathForTrace(args.trace);
const sidecar = readJsonIfExists(sidecarPath);
const events = Array.isArray(trace.traceEvents) ? trace.traceEvents : [];

const focusedWebGpuQueueEvents = new Set([
  'GPUQueue::submit',
  'GPUQueue::WriteBufferImpl',
  'GPUQueue::WriteTextureImpl',
  'GPUQueue::copyExternalImageToTexture',
  'GPUQueue::CopyFromCanvasSourceImage',
  'GPUQueue::CopyFromCanvasSourceImage::ExistingSharedImage',
  'GPUQueue::CopyFromCanvasSourceImage::StaticBitmapMailbox',
  'GPUQueue::CopyFromCanvasSourceImage::ForcedReadback',
  'GPUQueue::CopyFromCanvasSourceImage::CPUFallback',
  'GPUQueue::CopyFromCanvasSourceImage::CPUFallbackReadPixels',
  'GPUQueue::CopyFromCanvasSourceImage::CPUFallbackRejected',
  'GPUQueue::CopyFromCanvasSourceImage::SubmitIntermediate',
]);

const webGpuResidentTextureCopyEvents = new Set([
  'GPUQueue::CopyFromCanvasSourceImage::ExistingSharedImage',
  'GPUQueue::CopyFromCanvasSourceImage::StaticBitmapMailbox',
]);

const webGpuCpuTextureFallbackEvents = new Set([
  'GPUQueue::CopyFromCanvasSourceImage::ForcedReadback',
  'GPUQueue::CopyFromCanvasSourceImage::CPUFallback',
  'GPUQueue::CopyFromCanvasSourceImage::CPUFallbackReadPixels',
]);

const webGpuRejectedTextureFallbackEvents = new Set([
  'GPUQueue::CopyFromCanvasSourceImage::CPUFallbackRejected',
]);

function addPathStats(stats, event) {
  stats.count += 1;
  stats.bytes += numericArg(event, 'bytes');
  stats.pixels += numericArg(event, 'pixels');
}

function verdictLabel(stats) {
  if (stats.cpu.count > 0) return 'cpu-fallback-detected';
  if (stats.rejected.count > 0) return 'cpu-fallback-rejected';
  if (stats.gpuResident.count > 0) return 'gpu-resident-copy-observed';
  return 'no-webgpu-texture-copy-path-observed';
}

const groups = new Map();
const classes = new Map();
const webGpuQueueGroups = new Map();
const webGpuTexturePathStats = {
  gpuResident: { count: 0, bytes: 0, pixels: 0 },
  cpu: { count: 0, bytes: 0, pixels: 0 },
  rejected: { count: 0, bytes: 0, pixels: 0 },
};
for (const event of events) {
  const name = event.name || '(unnamed)';
  const durationMs = eventDurationMs(event);
  if (durationMs > 0) {
    if (!groups.has(name)) groups.set(name, { name, count: 0, totalMs: 0, maxMs: 0 });
    const group = groups.get(name);
    group.count += 1;
    group.totalMs += durationMs;
    group.maxMs = Math.max(group.maxMs, durationMs);
  }

  const className = classify(name);
  if (!classes.has(className)) classes.set(className, { className, count: 0, totalMs: 0 });
  const klass = classes.get(className);
  klass.count += 1;
  klass.totalMs += durationMs;

  if (focusedWebGpuQueueEvents.has(name)) {
    if (!webGpuQueueGroups.has(name)) {
      webGpuQueueGroups.set(name, {
        name,
        count: 0,
        totalMs: 0,
        maxMs: 0,
        bytes: 0,
        pixels: 0,
        commandBuffers: 0,
      });
    }
    const group = webGpuQueueGroups.get(name);
    group.count += 1;
    group.totalMs += durationMs;
    group.maxMs = Math.max(group.maxMs, durationMs);
    group.bytes += numericArg(event, 'bytes');
    group.pixels += numericArg(event, 'pixels');
    group.commandBuffers += numericArg(event, 'command_buffers');
  }
  if (webGpuResidentTextureCopyEvents.has(name)) {
    addPathStats(webGpuTexturePathStats.gpuResident, event);
  } else if (webGpuCpuTextureFallbackEvents.has(name)) {
    addPathStats(webGpuTexturePathStats.cpu, event);
  } else if (webGpuRejectedTextureFallbackEvents.has(name)) {
    addPathStats(webGpuTexturePathStats.rejected, event);
  }
}

const top = [...groups.values()]
  .sort((a, b) => b.totalMs - a.totalMs)
  .slice(0, args.limit);

const classRows = [...classes.values()].sort((a, b) => b.totalMs - a.totalMs);
const webGpuQueueRows = [...webGpuQueueGroups.values()].sort((a, b) => b.totalMs - a.totalMs || b.count - a.count);
const webGpuTextureVerdict = verdictLabel(webGpuTexturePathStats);
const hasSidecarFastPathCoverage = hasFastPathCoverage(sidecar);

const lines = [
  '# Trace Summary',
  '',
  `Trace: \`${args.trace}\``,
  sidecar ? `Sidecar: \`${sidecarPath}\`` : '',
  '',
  `Total events: ${events.length}`,
  '',
  '## Classified Events',
  '',
  '| Class | Count | Total Duration ms |',
  '| --- | ---: | ---: |',
  ...classRows.map((row) => `| ${row.className} | ${row.count} | ${round(row.totalMs, 2)} |`),
  '',
  '## Focused WebGPU Queue Events',
  '',
  '| Event | Count | Total ms | Max ms | Bytes MiB | Pixels | Command buffers |',
  '| --- | ---: | ---: | ---: | ---: | ---: | ---: |',
  ...(webGpuQueueRows.length > 0
    ? webGpuQueueRows.map((row) => `| ${row.name.replaceAll('|', '\\|')} | ${row.count} | ${round(row.totalMs, 2)} | ${round(row.maxMs, 2)} | ${formatMiB(row.bytes)} | ${row.pixels || ''} | ${row.commandBuffers || ''} |`)
    : ['| No focused WebGPU queue events found | 0 | 0.00 | 0.00 |  |  |  |']),
  '',
  '## WebGPU Texture Copy Path Verdict',
  '',
  `Status: \`${webGpuTextureVerdict}\``,
  '',
  '| Path | Events | Bytes MiB | Pixels |',
  '| --- | ---: | ---: | ---: |',
  `| GPU-resident shared image/mailbox copy | ${webGpuTexturePathStats.gpuResident.count} | ${formatMiB(webGpuTexturePathStats.gpuResident.bytes)} | ${webGpuTexturePathStats.gpuResident.pixels || ''} |`,
  `| CPU fallback/readback copy | ${webGpuTexturePathStats.cpu.count} | ${formatMiB(webGpuTexturePathStats.cpu.bytes)} | ${webGpuTexturePathStats.cpu.pixels || ''} |`,
  `| Rejected CPU fallback attempt | ${webGpuTexturePathStats.rejected.count} | ${formatMiB(webGpuTexturePathStats.rejected.bytes)} | ${webGpuTexturePathStats.rejected.pixels || ''} |`,
  '',
  ...(hasSidecarFastPathCoverage ? [
    '## WebGPU Fast-Path Coverage',
    '',
    'These sidecar counters are viewer-side diagnostic attribution. They show whether queue and pipeline descriptors matched source fast paths during the traced benchmark.',
    '',
    '| WriteTexture calls | Common writeTexture layout | Common writeTexture extent | CopyExternal calls | Default source origin | Common source origin | Explicit common source origin | sRGB destination | Full-source copy | Pipeline stack-eligible descriptors | Measured stack-eligible descriptors |',
    '| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |',
    `| ${coverageMetric(sidecar, 'webgpu_queue_write_texture_count')} | ${coverageMetric(sidecar, 'webgpu_queue_write_texture_common_layout_count')} | ${coverageMetric(sidecar, 'webgpu_queue_write_texture_common_extent_count')} | ${coverageMetric(sidecar, 'webgpu_queue_copy_external_image_count')} | ${coverageMetric(sidecar, 'webgpu_queue_copy_external_image_default_origin_count')} | ${coverageMetric(sidecar, 'webgpu_queue_copy_external_image_common_origin_count')} | ${coverageMetric(sidecar, 'webgpu_queue_copy_external_image_explicit_common_origin_count')} | ${coverageMetric(sidecar, 'webgpu_queue_copy_external_image_srgb_destination_count')} | ${coverageMetric(sidecar, 'webgpu_queue_copy_external_image_full_source_count')} | ${coverageMetric(sidecar, 'webgpu_pipeline_descriptor_stack_fast_path_eligible_count')} | ${coverageMetric(sidecar, 'webgpu_pipeline_descriptor_measured_stack_fast_path_eligible_count')} |`,
    '',
  ] : []),
  '## Top Duration Events',
  '',
  '| Event | Count | Total ms | Max ms |',
  '| --- | ---: | ---: | ---: |',
  ...top.map((row) => `| ${row.name.replaceAll('|', '\\|')} | ${row.count} | ${round(row.totalMs, 2)} | ${round(row.maxMs, 2)} |`),
  '',
  'Classification is name-based and intended for triage. Confirm important findings against the raw trace.',
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

if (args.rejectWebGpuCpuFallback &&
    (webGpuTexturePathStats.cpu.count > 0 ||
     webGpuTexturePathStats.rejected.count > 0)) {
  console.error(
    `FAIL: WebGPU CPU texture fallback/readback path detected: ${webGpuTextureVerdict}`,
  );
  process.exit(1);
}
