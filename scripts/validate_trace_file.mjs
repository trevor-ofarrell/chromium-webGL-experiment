#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

function parseArgs(argv) {
  const args = {
    files: [],
    minEvents: 1,
  };

  for (let i = 2; i < argv.length; i += 1) {
    const token = argv[i];
    if (token === '--minEvents') {
      args.minEvents = Number(argv[++i]);
    } else if (token.startsWith('--')) {
      throw new Error(`Unknown argument: ${token}`);
    } else {
      args.files.push(token);
    }
  }

  if (!args.files.length) {
    throw new Error('Usage: node scripts/validate_trace_file.mjs [--minEvents 1] <trace.json...>');
  }
  if (!Number.isInteger(args.minEvents) || args.minEvents < 1) {
    throw new Error('--minEvents must be a positive integer');
  }
  return args;
}

function isObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function validateTrace(trace, file, args) {
  const label = path.basename(file);
  const errors = [];
  if (!isObject(trace)) {
    return [`${label}: trace root must be an object`];
  }
  if (!Array.isArray(trace.traceEvents)) {
    return [`${label}: traceEvents must be an array`];
  }
  if (trace.traceEvents.length < args.minEvents) {
    errors.push(`${label}: traceEvents length ${trace.traceEvents.length} is below required minimum ${args.minEvents}`);
  }

  let namedEvents = 0;
  let phaseEvents = 0;
  let timedEvents = 0;
  for (let index = 0; index < trace.traceEvents.length; index += 1) {
    const event = trace.traceEvents[index];
    if (!isObject(event)) {
      errors.push(`${label}: traceEvents[${index}] must be an object`);
      continue;
    }
    if (typeof event.name === 'string' && event.name.length > 0) {
      namedEvents += 1;
    }
    if (typeof event.ph === 'string' && event.ph.length > 0) {
      phaseEvents += 1;
    }
    if (typeof event.ts === 'number' && Number.isFinite(event.ts)) {
      timedEvents += 1;
    }
  }

  if (namedEvents === 0) {
    errors.push(`${label}: traceEvents must contain at least one named event`);
  }
  if (phaseEvents === 0) {
    errors.push(`${label}: traceEvents must contain at least one event phase`);
  }
  if (timedEvents === 0) {
    errors.push(`${label}: traceEvents must contain at least one timestamped event`);
  }
  return errors;
}

const args = parseArgs(process.argv);
const allErrors = [];
for (const file of args.files) {
  const resolved = path.resolve(file);
  let trace = null;
  try {
    trace = JSON.parse(fs.readFileSync(resolved, 'utf8').replace(/^\uFEFF/, ''));
  } catch (error) {
    allErrors.push(`${path.basename(file)}: invalid JSON (${error.message})`);
    continue;
  }
  allErrors.push(...validateTrace(trace, resolved, args));
}

if (allErrors.length) {
  console.error('FAIL: trace file validation failed');
  for (const error of allErrors) {
    console.error(`  ${error}`);
  }
  process.exit(1);
}

console.log(`OK: ${args.files.length} trace file(s) validated.`);
