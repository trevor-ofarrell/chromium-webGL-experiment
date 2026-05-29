#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const seriesDefinitions = [
  { key: 'frame_times_ms', label: 'Frame' },
  { key: 'cpu_frame_times_ms', label: 'CPU frame' },
  { key: 'js_frame_times_ms', label: 'JS/update' },
  { key: 'render_submission_times_ms', label: 'Render submission' },
  { key: 'gpu_frame_times_ms', label: 'GPU frame' },
];

function usage() {
  return [
    'Usage: node scripts/analyze_tail_breakdown.mjs --baseline base.json --candidate fork.json [--output report.md] [--json report.json]',
    '       node scripts/analyze_tail_breakdown.mjs base.json fork.json',
  ].join('\n');
}

function parseArgs(argv) {
  const args = {
    baseline: null,
    candidate: null,
    output: null,
    json: null,
    positional: [],
  };
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (token === '--baseline') {
      args.baseline = argv[++i];
    } else if (token === '--candidate') {
      args.candidate = argv[++i];
    } else if (token === '--output') {
      args.output = argv[++i];
    } else if (token === '--json') {
      args.json = argv[++i];
    } else if (token === '--help' || token === '-h') {
      console.log(usage());
      process.exit(0);
    } else if (token.startsWith('--')) {
      throw new Error(`Unknown option: ${token}\n${usage()}`);
    } else {
      args.positional.push(token);
    }
  }
  if (!args.baseline && args.positional.length >= 1) args.baseline = args.positional[0];
  if (!args.candidate && args.positional.length >= 2) args.candidate = args.positional[1];
  if (!args.baseline || !args.candidate) {
    throw new Error(usage());
  }
  return args;
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
}

function finiteSeries(value) {
  if (!Array.isArray(value)) return null;
  const values = value.filter((entry) => Number.isFinite(entry));
  return values.length ? values : null;
}

function percentile(sortedValues, fraction) {
  if (!sortedValues.length) return null;
  const index = Math.min(
    sortedValues.length - 1,
    Math.max(0, Math.floor((sortedValues.length - 1) * fraction)),
  );
  return sortedValues[index];
}

function average(values) {
  if (!values.length) return null;
  return values.reduce((sum, value) => sum + value, 0) / values.length;
}

function stats(values) {
  if (!values) return null;
  const sorted = [...values].sort((a, b) => a - b);
  return {
    count: values.length,
    avg_ms: average(values),
    p50_ms: percentile(sorted, 0.50),
    p95_ms: percentile(sorted, 0.95),
    p99_ms: percentile(sorted, 0.99),
    max_ms: sorted[sorted.length - 1],
  };
}

function delta(candidate, baseline) {
  if (!candidate || !baseline) return null;
  const result = {};
  for (const key of ['count', 'avg_ms', 'p50_ms', 'p95_ms', 'p99_ms', 'max_ms']) {
    const candidateValue = candidate[key];
    const baselineValue = baseline[key];
    result[key] = Number.isFinite(candidateValue) && Number.isFinite(baselineValue)
      ? candidateValue - baselineValue
      : null;
  }
  return result;
}

function round(value, digits = 3) {
  return Number.isFinite(value) ? Number(value.toFixed(digits)) : null;
}

function format(value, digits = 3) {
  return Number.isFinite(value) ? value.toFixed(digits) : 'n/a';
}

function compactStats(value) {
  if (!value) return null;
  return Object.fromEntries(Object.entries(value).map(([key, entry]) => [key, round(entry)]));
}

function buildReport(baselineFile, candidateFile, baseline, candidate) {
  const rows = seriesDefinitions.map(({ key, label }) => {
    const baselineStats = stats(finiteSeries(baseline[key]));
    const candidateStats = stats(finiteSeries(candidate[key]));
    const deltaStats = delta(candidateStats, baselineStats);
    return {
      key,
      label,
      baseline: compactStats(baselineStats),
      candidate: compactStats(candidateStats),
      delta: compactStats(deltaStats),
      available: Boolean(baselineStats && candidateStats),
    };
  });
  const p99Rows = rows
    .filter((row) => Number.isFinite(row.delta?.p99_ms))
    .sort((a, b) => b.delta.p99_ms - a.delta.p99_ms);
  return {
    baseline_file: baselineFile,
    candidate_file: candidateFile,
    scene_name: candidate.scene_name || baseline.scene_name || null,
    renderer_type: candidate.renderer_type || baseline.renderer_type || null,
    baseline_variant: baseline.benchmark_variant || null,
    candidate_variant: candidate.benchmark_variant || null,
    baseline_avg_fps: round(baseline.avg_fps),
    candidate_avg_fps: round(candidate.avg_fps),
    avg_fps_delta_pct: Number.isFinite(baseline.avg_fps) && baseline.avg_fps > 0 && Number.isFinite(candidate.avg_fps)
      ? round(((candidate.avg_fps - baseline.avg_fps) / baseline.avg_fps) * 100)
      : null,
    worst_p99_delta_series: p99Rows[0]?.key || null,
    worst_p99_delta_ms: p99Rows[0]?.delta?.p99_ms ?? null,
    rows,
  };
}

function renderMarkdown(report) {
  const lines = [
    `# Tail Breakdown: ${report.scene_name || 'unknown scene'} / ${report.renderer_type || 'unknown renderer'}`,
    '',
    `Baseline: \`${path.normalize(report.baseline_file)}\``,
    `Candidate: \`${path.normalize(report.candidate_file)}\``,
    '',
    `Average FPS delta: ${format(report.avg_fps_delta_pct, 3)}%`,
    `Worst p99 delta series: ${report.worst_p99_delta_series || 'n/a'} (${format(report.worst_p99_delta_ms, 3)} ms)`,
    '',
    '| Series | Samples | Avg delta ms | p50 delta ms | p95 delta ms | p99 delta ms | Max delta ms |',
    '| --- | ---: | ---: | ---: | ---: | ---: | ---: |',
  ];
  for (const row of report.rows) {
    const sampleText = row.available
      ? `${row.baseline.count} -> ${row.candidate.count}`
      : 'n/a';
    lines.push([
      `| ${row.label}`,
      sampleText,
      format(row.delta?.avg_ms),
      format(row.delta?.p50_ms),
      format(row.delta?.p95_ms),
      format(row.delta?.p99_ms),
      `${format(row.delta?.max_ms)} |`,
    ].join(' | '));
  }
  lines.push('');
  lines.push('Positive millisecond deltas mean the candidate is slower for that timing series.');
  return `${lines.join('\n')}\n`;
}

try {
  const args = parseArgs(process.argv.slice(2));
  const baseline = readJson(args.baseline);
  const candidate = readJson(args.candidate);
  const report = buildReport(args.baseline, args.candidate, baseline, candidate);
  const markdown = renderMarkdown(report);
  if (args.output) fs.writeFileSync(args.output, markdown);
  if (args.json) fs.writeFileSync(args.json, `${JSON.stringify(report, null, 2)}\n`);
  if (!args.output) process.stdout.write(markdown);
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
