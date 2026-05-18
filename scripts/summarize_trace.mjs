#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

function parseArgs(argv) {
  const args = { trace: '', output: '', limit: 30 };
  for (let i = 2; i < argv.length; i += 1) {
    if (argv[i] === '--output') {
      args.output = argv[++i];
    } else if (argv[i] === '--limit') {
      args.limit = Number(argv[++i]);
    } else if (!args.trace) {
      args.trace = argv[i];
    } else {
      throw new Error(`Unexpected argument: ${argv[i]}`);
    }
  }
  if (!args.trace) {
    throw new Error('Usage: node scripts/summarize_trace.mjs <trace.json> [--output report.md] [--limit 30]');
  }
  return args;
}

function round(value, digits = 2) {
  return Number.isFinite(value) ? value.toFixed(digits) : '';
}

function eventDurationMs(event) {
  return Number.isFinite(event.dur) ? event.dur / 1000 : 0;
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
const trace = JSON.parse(fs.readFileSync(args.trace, 'utf8'));
const events = Array.isArray(trace.traceEvents) ? trace.traceEvents : [];

const groups = new Map();
const classes = new Map();
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
}

const top = [...groups.values()]
  .sort((a, b) => b.totalMs - a.totalMs)
  .slice(0, args.limit);

const classRows = [...classes.values()].sort((a, b) => b.totalMs - a.totalMs);

const lines = [
  '# Trace Summary',
  '',
  `Trace: \`${args.trace}\``,
  '',
  `Total events: ${events.length}`,
  '',
  '## Classified Events',
  '',
  '| Class | Count | Total Duration ms |',
  '| --- | ---: | ---: |',
  ...classRows.map((row) => `| ${row.className} | ${row.count} | ${round(row.totalMs, 2)} |`),
  '',
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
