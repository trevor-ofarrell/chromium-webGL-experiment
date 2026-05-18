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
  const args = {
    output: '',
    files: [],
    strictSameRevision: false,
    strictOfficial: false,
  };
  for (let i = 2; i < argv.length; i += 1) {
    if (argv[i] === '--output') {
      args.output = argv[++i];
    } else if (argv[i] === '--strictSameRevision') {
      args.strictSameRevision = true;
    } else if (argv[i] === '--strictOfficial') {
      args.strictOfficial = true;
    } else {
      args.files.push(...expandFileArg(argv[i]));
    }
  }
  if (!args.files.length) {
    throw new Error('Usage: node scripts/compare_results.mjs <result.json...> [--output report.md] [--strictSameRevision] [--strictOfficial]');
  }
  if (args.strictOfficial) args.strictSameRevision = true;
  return args;
}

function round(value, digits = 2) {
  return Number.isFinite(value) ? value.toFixed(digits) : '';
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

function unique(values) {
  return [...new Set(values)];
}

function hasBaselineVariant(results) {
  return results.some((item) => /stock|baseline/i.test(variantOf(item)));
}

function hasForkVariant(results) {
  return results.some((item) => /fork/i.test(variantOf(item)));
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

function hasGpuMetadata(result) {
  return [result.gpu_name, result.driver_version, result.angle_backend]
    .some((value) => typeof value === 'string' && value.trim().length > 0);
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

  if (args.strictSameRevision) {
    if (revisions.length !== 1) {
      errors.push(`Expected exactly one chromium_revision across comparison inputs, found ${revisions.length || 0}: ${revisions.join(', ') || 'none'}`);
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

    const missingGpuMetadata = results
      .filter((result) => !hasGpuMetadata(result))
      .map((result) => `${variantOf(result)} ${result.scene_name}/${result.renderer_type}`);
    if (missingGpuMetadata.length) {
      errors.push(`Official comparisons require GPU/backend metadata on every result. Missing: ${missingGpuMetadata.join(', ')}`);
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
        errors.push(`Official fork_revision values must be derived from chromium_revision ${chromiumRevision} and the viewer patch hash. Mismatched: ${mismatchedForkRevisions.join(', ')}`);
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
    }
  }

  if (errors.length) {
    throw new Error(`Comparison input validation failed:\n- ${errors.join('\n- ')}`);
  }
}

const args = parseArgs(process.argv);
const results = args.files.map((file) => JSON.parse(fs.readFileSync(file, 'utf8')));
validateComparisonInputs(results, args);
const rows = compareRows(results);

const lines = [
  '# Benchmark Comparison',
  '',
  `Generated from ${results.length} result file(s). Baseline per scene/renderer is the first variant whose name contains stock or baseline, falling back to the first result.`,
  args.strictOfficial ? 'Strict official input validation was enabled: all inputs must come from checkout-built binaries, share one Chromium revision, include build-args hashes, include patch-derived fork revisions for fork variants, contain baseline plus fork variants for every scene/renderer, use matching measured/warmup seconds per case, include GPU/backend metadata, and avoid known software-rendered GPU paths.' : '',
  '',
  '| Scene | Renderer | Variant | Avg FPS | FPS Delta | FPS Delta % | 1% Low | 1% Low Delta | 0.1% Low | 0.1% Low Delta | P50 ms | P50 Delta | P95 ms | P95 Delta | P99 ms | P99 Delta | Max ms | Max Delta | CPU ms | CPU Delta | JS ms | JS Delta | Submit ms | Submit Delta | Compositor ms | Compositor Delta | Present ms | Present Delta | GPU ms | GPU Delta | Dropped | Dropped Delta | Startup ms | Startup Delta | RSS MB | RSS Delta | JS heap MB | JS heap Delta | GPU memory MB | GPU memory Delta | Draw calls | Draw calls Delta | Triangles | Triangles Delta | Texture MB | Texture Delta | Buffer MB | Buffer Delta | Shader events | Shader events Delta | Binary MB | Binary Delta | Viewer MB | Viewer Delta | Package MB | Package Delta |',
  '| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |',
  ...rows.map((row) => [
    row.scene,
    row.renderer,
    row.variant,
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
];

const markdown = lines.join('\n');
if (args.output) {
  fs.mkdirSync(path.dirname(args.output), { recursive: true });
  fs.writeFileSync(args.output, markdown);
  console.log(`Wrote ${args.output}`);
} else {
  console.log(markdown);
}
