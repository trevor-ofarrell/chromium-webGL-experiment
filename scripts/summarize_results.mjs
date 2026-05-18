#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

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
  const files = [];
  let output = '';
  for (let i = 2; i < argv.length; i += 1) {
    if (argv[i] === '--output') {
      output = argv[++i];
    } else {
      files.push(...expandFileArg(argv[i]));
    }
  }
  if (!files.length) {
    throw new Error('Usage: node scripts/summarize_results.mjs <result.json...> [--output report.md]');
  }
  return { files, output };
}

function round(value, digits = 2) {
  return Number.isFinite(value) ? value.toFixed(digits) : '';
}

function variantOf(result) {
  return result.benchmark_variant || 'unknown';
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

const { files, output } = parseArgs(process.argv);
const results = files.map((file) => JSON.parse(fs.readFileSync(file, 'utf8')));
results.sort((a, b) => `${a.renderer_type}:${a.scene_name}:${variantOf(a)}`.localeCompare(`${b.renderer_type}:${b.scene_name}:${variantOf(b)}`));

const lines = [
  '# Benchmark Summary',
  '',
  `Generated from ${results.length} result file(s).`,
  '',
  '| Scene | Renderer | Variant | Avg FPS | 1% Low FPS | 0.1% Low FPS | P50 ms | P95 ms | P99 ms | Max ms | CPU ms | GPU ms | JS ms | Submit ms | Compositor ms | Present ms | Dropped | Draw calls | Triangles | Texture MB | Buffer MB | Shader events | JS heap MB | GPU memory MB | RSS MB | Startup ms | Binary MB | Viewer MB | Package MB |',
  '| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |',
  ...results.map(row).map((line) => `| ${line} |`),
  '',
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
