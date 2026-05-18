#!/usr/bin/env node
import fs from 'node:fs';

const required = [
  'chromium_revision',
  'fork_revision',
  'build_args_hash',
  'platform',
  'gpu_name',
  'driver_version',
  'angle_backend',
  'renderer_type',
  'scene_name',
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

const scenes = new Set([
  'many-draw-calls',
  'instancing',
  'shader-heavy',
  'texture-streaming',
  'postprocessing',
  'large-static',
  'gltf-loader-stress',
]);

const renderers = new Set(['webgl2', 'webgpu']);

const nullableStrings = new Set([
  'chromium_revision',
  'fork_revision',
  'build_args_hash',
  'gpu_name',
  'driver_version',
  'angle_backend',
]);

const requiredFiniteNumbers = new Set([
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
  'startup_ms_to_first_frame',
  'browser_binary_size_mb',
  'viewer_bundle_size_mb',
]);

const nullableNumbers = new Set([
  'avg_gpu_frame_ms',
  'avg_compositor_latency_ms',
  'avg_presentation_latency_ms',
  'js_heap_mb',
  'gpu_memory_mb',
  'process_rss_mb',
  'package_size_mb',
]);

const optionalNumbers = new Set([
  'avg_frame_ms',
  'process_rss_start_mb',
  'process_rss_peak_mb',
  'process_rss_end_mb',
  'process_rss_delta_mb',
  'resource_warmup_ms',
  'resource_warmup_precompile_ms',
  'resource_warmup_prerender_ms',
  'resource_warmup_prerender_frames',
  'renderer_memory_geometries_start',
  'renderer_memory_geometries_end',
  'renderer_memory_geometries_peak',
  'renderer_memory_geometries_delta',
  'renderer_memory_textures_start',
  'renderer_memory_textures_end',
  'renderer_memory_textures_peak',
  'renderer_memory_textures_delta',
  'renderer_programs_start',
  'renderer_programs_end',
  'renderer_programs_peak',
  'renderer_programs_delta',
  'webgl_context_lost_count',
  'webgl_context_restored_count',
  'webgl_last_context_loss_ms',
  'render_error_count',
  'gpu_timer_error_count',
]);

const optionalBooleans = new Set([
  'viewer_mode',
  'viewer_block_external_navigation',
  'viewer_file_mode',
  'viewer_trusted_content',
  'viewer_aggressive_gpu',
  'viewer_relaxed_webgl_validation',
  'viewer_in_process_gpu',
  'viewer_single_process',
  'viewer_disable_unneeded_blink_features',
  'viewer_direct_gpu_presentation',
  'browser_is_from_checkout',
  'resource_warmup_enabled',
  'resource_warmup_precompile',
  'webgl_context_currently_lost',
  'webgpu_device_lost',
  'gpu_timing_enabled',
  'gpu_timer_available',
]);

function isFiniteNumber(value) {
  return typeof value === 'number' && Number.isFinite(value);
}

function validateOptionalStringArray(data, key, errors) {
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

function validateStringOrNull(data, key, errors) {
  const value = data[key];
  if (value !== null && typeof value !== 'string') {
    errors.push(`${key} must be a string or null`);
  }
}

function validateFiniteNumber(data, key, errors) {
  const value = data[key];
  if (!isFiniteNumber(value)) {
    errors.push(`${key} must be a finite number`);
  }
}

function validateNullableNumber(data, key, errors) {
  const value = data[key];
  if (value !== null && !isFiniteNumber(value)) {
    errors.push(`${key} must be a finite number or null`);
  }
}

function validateNonNegative(data, key, errors) {
  const value = data[key];
  if (isFiniteNumber(value) && value < 0) {
    errors.push(`${key} must be non-negative`);
  }
}

function validateInteger(data, key, errors) {
  const value = data[key];
  if (isFiniteNumber(value) && !Number.isInteger(value)) {
    errors.push(`${key} must be an integer`);
  }
}

function validateOptionalFields(data, errors) {
  for (const key of optionalNumbers) {
    if (key in data) {
      validateNullableNumber(data, key, errors);
      if (!/_delta(_mb)?$/.test(key)) {
        validateNonNegative(data, key, errors);
      }
    }
  }

  for (const key of optionalBooleans) {
    if (key in data && typeof data[key] !== 'boolean') {
      errors.push(`${key} must be a boolean`);
    }
  }

  for (const key of ['generated_at', 'browser_executable', 'browser_version', 'benchmark_variant', 'viewer_force_angle_backend', 'requested_angle_backend', 'gpu_timer_type', 'gpu_timer_unavailable_reason', 'last_gpu_timer_error', 'webgpu_device_loss_reason', 'webgpu_device_loss_message', 'last_render_error']) {
    if (key in data && data[key] !== null && typeof data[key] !== 'string') {
      errors.push(`${key} must be a string or null`);
    }
  }

  if ('frame_times_ms' in data) {
    if (!Array.isArray(data.frame_times_ms)) {
      errors.push('frame_times_ms must be an array when present');
    } else if (data.frame_times_ms.length === 0) {
      errors.push('frame_times_ms must not be empty when present');
    } else {
      data.frame_times_ms.forEach((value, index) => {
        if (!isFiniteNumber(value) || value < 0) {
          errors.push(`frame_times_ms[${index}] must be a non-negative finite number`);
        }
      });
    }
  }

  if ('scene_notes' in data && !Array.isArray(data.scene_notes)) {
    errors.push('scene_notes must be an array when present');
  }

  if (Array.isArray(data.scene_notes)) {
    data.scene_notes.forEach((value, index) => {
      if (typeof value !== 'string') {
        errors.push(`scene_notes[${index}] must be a string`);
      }
    });
  }

  validateOptionalStringArray(data, 'browser_flags', errors);
  validateOptionalStringArray(data, 'browser_extra_flags', errors);
}

function validate(data) {
  const errors = [];
  const missing = required.filter((key) => !(key in data));
  if (missing.length) {
    errors.push(`Missing required metric fields: ${missing.join(', ')}`);
  }

  if (!renderers.has(data.renderer_type)) {
    errors.push(`renderer_type must be one of: ${[...renderers].join(', ')}`);
  }
  if (!scenes.has(data.scene_name)) {
    errors.push(`scene_name must be one of: ${[...scenes].join(', ')}`);
  }
  if (typeof data.platform !== 'string' || data.platform.length === 0) {
    errors.push('platform must be a non-empty string');
  }

  for (const key of nullableStrings) {
    if (key in data) validateStringOrNull(data, key, errors);
  }

  for (const key of requiredFiniteNumbers) {
    if (key in data) {
      validateFiniteNumber(data, key, errors);
      validateNonNegative(data, key, errors);
    }
  }

  for (const key of nullableNumbers) {
    if (key in data) {
      validateNullableNumber(data, key, errors);
      validateNonNegative(data, key, errors);
    }
  }

  for (const key of ['dropped_frames', 'shader_compile_events']) {
    if (key in data) validateInteger(data, key, errors);
  }

  if (isFiniteNumber(data.measured_seconds) && data.measured_seconds <= 0) {
    errors.push('measured_seconds must be greater than zero');
  }
  if (isFiniteNumber(data.avg_fps) && data.avg_fps <= 0) {
    errors.push('avg_fps must be greater than zero');
  }
  if (isFiniteNumber(data.p95_frame_ms) && isFiniteNumber(data.p50_frame_ms) && data.p95_frame_ms < data.p50_frame_ms) {
    errors.push('p95_frame_ms must be greater than or equal to p50_frame_ms');
  }
  if (isFiniteNumber(data.p99_frame_ms) && isFiniteNumber(data.p95_frame_ms) && data.p99_frame_ms < data.p95_frame_ms) {
    errors.push('p99_frame_ms must be greater than or equal to p95_frame_ms');
  }

  validateOptionalFields(data, errors);
  return errors;
}

const files = process.argv.slice(2);
if (!files.length) {
  console.error('Usage: node scripts/validate_metrics.mjs <result.json...>');
  process.exit(2);
}

let failed = false;
for (const file of files) {
  let data;
  try {
    data = JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (error) {
    console.error(`FAIL: ${file}`);
    console.error(`  ${error.message}`);
    failed = true;
    continue;
  }

  const errors = validate(data);
  if (errors.length) {
    console.error(`FAIL: ${file}`);
    for (const error of errors) {
      console.error(`  ${error}`);
    }
    failed = true;
  } else {
    console.log(`OK: ${file} contains ${required.length} required metric fields and valid benchmark values.`);
  }
}

if (failed) process.exit(1);
