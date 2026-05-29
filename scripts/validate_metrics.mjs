#!/usr/bin/env node
import fs from 'node:fs';

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
}

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
  'complexity',
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
const webGpuStaticBundleScenes = new Set([
  'many-draw-calls',
  'texture-streaming',
  'gltf-loader-stress',
]);

const nullableStrings = new Set([
  'chromium_revision',
  'fork_revision',
  'build_args_hash',
  'gpu_name',
  'driver_version',
  'angle_backend',
]);

const requiredFiniteNumbers = new Set([
  'complexity',
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
  'dropped_frame_rate',
  'p95_cpu_frame_ms',
  'p99_cpu_frame_ms',
  'p95_gpu_frame_ms',
  'p99_gpu_frame_ms',
  'p95_js_frame_ms',
  'p99_js_frame_ms',
  'p95_render_submission_ms',
  'p99_render_submission_ms',
  'process_rss_start_mb',
  'process_rss_peak_mb',
  'process_rss_end_mb',
  'process_rss_delta_mb',
  'resource_warmup_ms',
  'resource_warmup_precompile_ms',
  'resource_warmup_prerender_ms',
  'resource_warmup_settle_gpu_ms',
  'resource_warmup_prerender_frames',
  'resource_warmup_pipeline_quiet_frames',
  'resource_warmup_pipeline_quiet_max_frames',
  'resource_warmup_pipeline_quiet_actual_frames',
  'resource_warmup_pipeline_quiet_ms',
  'resource_warmup_compile_targets',
  'resource_warmup_texture_targets',
  'resource_warmup_render_targets',
  'resource_warmup_texture_init_ms',
  'resource_warmup_render_target_init_ms',
  'webgpu_bundle_groups',
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
  'runtime_shader_compile_events',
  'scene_declared_shader_compile_events',
  'webgl_context_lost_count',
  'webgl_context_restored_count',
  'webgl_last_context_loss_ms',
  'render_error_count',
  'gpu_timer_error_count',
  'texture_update_count',
  'webgpu_queue_write_buffer_count',
  'webgpu_queue_write_buffer_ms',
  'webgpu_queue_write_buffer_estimated_mb',
  'webgpu_queue_write_texture_count',
  'webgpu_queue_write_texture_ms',
  'webgpu_queue_write_texture_estimated_mb',
  'webgpu_queue_write_texture_common_layout_count',
  'webgpu_queue_write_texture_common_extent_count',
  'webgpu_queue_write_texture_dict_extent_count',
  'webgpu_queue_write_texture_sequence_extent_count',
  'webgpu_queue_copy_external_image_count',
  'webgpu_queue_copy_external_image_ms',
  'webgpu_queue_copy_external_image_estimated_mb',
  'webgpu_queue_copy_external_image_default_origin_count',
  'webgpu_queue_copy_external_image_common_origin_count',
  'webgpu_queue_copy_external_image_explicit_common_origin_count',
  'webgpu_queue_copy_external_image_common_extent_count',
  'webgpu_queue_copy_external_image_dict_extent_count',
  'webgpu_queue_copy_external_image_sequence_extent_count',
  'webgpu_queue_copy_external_image_srgb_destination_count',
  'webgpu_queue_copy_external_image_full_source_count',
  'webgpu_queue_copy_element_image_count',
  'webgpu_queue_copy_element_image_ms',
  'webgpu_queue_copy_element_image_estimated_mb',
  'webgpu_queue_submit_count',
  'webgpu_queue_submit_ms',
  'webgpu_queue_submit_command_buffer_count',
  'webgpu_queue_submit_avg_command_buffers',
  'webgpu_queue_submit_single_command_buffer_count',
  'webgpu_queue_submit_small_batch_count',
  'webgpu_queue_submit_max_command_buffers',
  'webgpu_command_encoder_create_count',
  'webgpu_command_encoder_create_ms',
  'webgpu_command_encoder_begin_render_pass_count',
  'webgpu_command_encoder_begin_render_pass_ms',
  'webgpu_command_encoder_render_pass_color_attachment_count',
  'webgpu_command_encoder_render_pass_max_color_attachments',
  'webgpu_command_encoder_render_pass_clear_value_count',
  'webgpu_command_encoder_render_pass_clear_value_dict_count',
  'webgpu_command_encoder_render_pass_depth_stencil_attachment_count',
  'webgpu_command_encoder_render_pass_measured_count',
  'webgpu_command_encoder_render_pass_measured_clear_value_dict_count',
  'webgpu_command_encoder_begin_compute_pass_count',
  'webgpu_command_encoder_begin_compute_pass_ms',
  'webgpu_command_encoder_finish_count',
  'webgpu_command_encoder_finish_ms',
  'webgpu_command_encoder_copy_buffer_to_buffer_count',
  'webgpu_command_encoder_copy_buffer_to_buffer_ms',
  'webgpu_command_encoder_copy_buffer_to_buffer_estimated_mb',
  'webgpu_command_encoder_copy_buffer_to_texture_count',
  'webgpu_command_encoder_copy_buffer_to_texture_ms',
  'webgpu_command_encoder_copy_buffer_to_texture_estimated_mb',
  'webgpu_command_encoder_copy_texture_to_buffer_count',
  'webgpu_command_encoder_copy_texture_to_buffer_ms',
  'webgpu_command_encoder_copy_texture_to_buffer_estimated_mb',
  'webgpu_command_encoder_copy_texture_to_texture_count',
  'webgpu_command_encoder_copy_texture_to_texture_ms',
  'webgpu_command_encoder_copy_texture_to_texture_estimated_mb',
  'webgpu_command_encoder_copy_measured_count',
  'webgpu_command_encoder_copy_measured_estimated_mb',
  'webgpu_bind_group_set_count',
  'webgpu_bind_group_set_ms',
  'webgpu_bind_group_set_render_pass_count',
  'webgpu_bind_group_set_render_bundle_count',
  'webgpu_bind_group_set_compute_pass_count',
  'webgpu_bind_group_set_redundant_count',
  'webgpu_bind_group_set_redundant_no_dynamic_offsets_count',
  'webgpu_bind_group_set_no_dynamic_offsets_count',
  'webgpu_bind_group_set_sequence_empty_dynamic_offsets_count',
  'webgpu_bind_group_set_typed_array_empty_dynamic_offsets_count',
  'webgpu_bind_group_set_non_empty_dynamic_offsets_count',
  'webgpu_bind_group_set_measured_count',
  'webgpu_bind_group_set_measured_redundant_count',
  'webgpu_bind_group_set_measured_redundant_no_dynamic_offsets_count',
  'webgpu_bind_group_set_measured_typed_array_empty_dynamic_offsets_count',
  'webgpu_pipeline_set_count',
  'webgpu_pipeline_set_ms',
  'webgpu_pipeline_set_render_pass_count',
  'webgpu_pipeline_set_render_bundle_count',
  'webgpu_pipeline_set_compute_pass_count',
  'webgpu_pipeline_set_redundant_count',
  'webgpu_pipeline_set_measured_count',
  'webgpu_pipeline_set_measured_redundant_count',
  'webgpu_buffer_state_set_count',
  'webgpu_buffer_state_set_ms',
  'webgpu_buffer_state_set_render_pass_count',
  'webgpu_buffer_state_set_render_bundle_count',
  'webgpu_buffer_state_set_redundant_count',
  'webgpu_buffer_state_set_measured_count',
  'webgpu_buffer_state_set_measured_redundant_count',
  'webgpu_render_state_set_count',
  'webgpu_render_state_set_ms',
  'webgpu_render_state_set_render_pass_count',
  'webgpu_render_state_set_redundant_count',
  'webgpu_render_state_set_measured_count',
  'webgpu_render_state_set_measured_redundant_count',
  'webgpu_viewport_set_count',
  'webgpu_viewport_set_redundant_count',
  'webgpu_viewport_set_measured_count',
  'webgpu_viewport_set_measured_redundant_count',
  'webgpu_scissor_rect_set_count',
  'webgpu_scissor_rect_set_redundant_count',
  'webgpu_scissor_rect_set_measured_count',
  'webgpu_scissor_rect_set_measured_redundant_count',
  'webgpu_stencil_reference_set_count',
  'webgpu_stencil_reference_set_redundant_count',
  'webgpu_stencil_reference_set_measured_count',
  'webgpu_stencil_reference_set_measured_redundant_count',
  'webgpu_blend_constant_set_count',
  'webgpu_blend_constant_set_redundant_count',
  'webgpu_blend_constant_set_measured_count',
  'webgpu_blend_constant_set_measured_redundant_count',
  'webgpu_vertex_buffer_set_count',
  'webgpu_vertex_buffer_set_redundant_count',
  'webgpu_vertex_buffer_set_measured_count',
  'webgpu_vertex_buffer_set_measured_redundant_count',
  'webgpu_index_buffer_set_count',
  'webgpu_index_buffer_set_redundant_count',
  'webgpu_index_buffer_set_measured_count',
  'webgpu_index_buffer_set_measured_redundant_count',
  'webgpu_immediate_set_count',
  'webgpu_immediate_set_ms',
  'webgpu_immediate_set_render_pass_count',
  'webgpu_immediate_set_render_bundle_count',
  'webgpu_immediate_set_compute_pass_count',
  'webgpu_immediate_set_full_span_count',
  'webgpu_immediate_set_sub_span_count',
  'webgpu_immediate_set_measured_count',
  'webgpu_immediate_set_measured_full_span_count',
  'webgpu_pipeline_create_render_count',
  'webgpu_pipeline_create_render_ms',
  'webgpu_pipeline_create_render_async_count',
  'webgpu_pipeline_create_render_async_ms',
  'webgpu_pipeline_create_compute_count',
  'webgpu_pipeline_create_compute_ms',
  'webgpu_pipeline_create_compute_async_count',
  'webgpu_pipeline_create_compute_async_ms',
  'webgpu_pipeline_create_total_count',
  'webgpu_pipeline_create_total_ms',
  'webgpu_pipeline_create_setup_count',
  'webgpu_pipeline_create_setup_ms',
  'webgpu_pipeline_create_resource_warmup_count',
  'webgpu_pipeline_create_resource_warmup_ms',
  'webgpu_pipeline_create_warmup_count',
  'webgpu_pipeline_create_warmup_ms',
  'webgpu_pipeline_create_measured_count',
  'webgpu_pipeline_create_measured_ms',
  'webgpu_pipeline_create_other_count',
  'webgpu_pipeline_create_other_ms',
  'webgpu_pipeline_descriptor_render_count',
  'webgpu_pipeline_descriptor_compute_count',
  'webgpu_pipeline_descriptor_render_vertex_buffer_count',
  'webgpu_pipeline_descriptor_render_vertex_attribute_count',
  'webgpu_pipeline_descriptor_render_stack_vertex_buffer_eligible_count',
  'webgpu_pipeline_descriptor_render_color_target_count',
  'webgpu_pipeline_descriptor_render_blend_target_count',
  'webgpu_pipeline_descriptor_render_stack_color_target_eligible_count',
  'webgpu_pipeline_descriptor_vertex_constant_count',
  'webgpu_pipeline_descriptor_vertex_stack_constant_eligible_count',
  'webgpu_pipeline_descriptor_fragment_constant_count',
  'webgpu_pipeline_descriptor_fragment_stack_constant_eligible_count',
  'webgpu_pipeline_descriptor_compute_constant_count',
  'webgpu_pipeline_descriptor_compute_stack_constant_eligible_count',
  'webgpu_pipeline_descriptor_stack_fast_path_eligible_count',
  'webgpu_pipeline_descriptor_measured_count',
  'webgpu_pipeline_descriptor_measured_stack_fast_path_eligible_count',
]);

const optionalBooleans = new Set([
  'viewer_mode',
  'viewer_block_external_navigation',
  'viewer_file_mode',
  'viewer_trusted_content',
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
  'browser_is_from_checkout',
  'webgpu_blob_cache_origin_eligible',
  'webgpu_blob_cache_disabled_by_explicit_toggle',
  'webgpu_blob_cache_expected_available',
  'webgpu_blob_cache_hash_validation_disabled',
  'resource_warmup_enabled',
  'resource_warmup_precompile',
  'resource_warmup_settle_gpu',
  'resource_warmup_pipeline_quiet_achieved',
  'webgl_context_currently_lost',
  'webgpu_device_lost',
  'gpu_timing_enabled',
  'benchmark_hud_enabled',
  'gpu_timer_available',
  'webgpu_queue_instrumentation_enabled',
  'webgpu_queue_instrumentation_available',
  'webgpu_command_encoder_instrumentation_enabled',
  'webgpu_command_encoder_instrumentation_available',
  'webgpu_bind_group_instrumentation_enabled',
  'webgpu_bind_group_instrumentation_available',
  'webgpu_pipeline_state_instrumentation_enabled',
  'webgpu_pipeline_state_instrumentation_available',
  'webgpu_buffer_state_instrumentation_enabled',
  'webgpu_buffer_state_instrumentation_available',
  'webgpu_render_state_instrumentation_enabled',
  'webgpu_render_state_instrumentation_available',
  'webgpu_immediate_instrumentation_enabled',
  'webgpu_immediate_instrumentation_available',
  'webgpu_pipeline_instrumentation_enabled',
  'webgpu_pipeline_instrumentation_available',
  'profile_reuse_enabled',
  'profile_dir_created_by_runner',
]);

const optionalNonNegativeSeries = new Set([
  'cpu_frame_times_ms',
  'js_frame_times_ms',
  'render_submission_times_ms',
  'gpu_frame_times_ms',
]);

const integerNumbers = new Set([
  'dropped_frames',
  'shader_compile_events',
  'resource_warmup_prerender_frames',
  'resource_warmup_pipeline_quiet_frames',
  'resource_warmup_pipeline_quiet_max_frames',
  'resource_warmup_pipeline_quiet_actual_frames',
  'resource_warmup_compile_targets',
  'resource_warmup_texture_targets',
  'resource_warmup_render_targets',
  'webgpu_bundle_groups',
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
  'runtime_shader_compile_events',
  'scene_declared_shader_compile_events',
  'webgl_context_lost_count',
  'webgl_context_restored_count',
  'render_error_count',
  'gpu_timer_error_count',
  'texture_update_count',
  'webgpu_queue_write_buffer_count',
  'webgpu_queue_write_texture_count',
  'webgpu_queue_write_texture_common_layout_count',
  'webgpu_queue_write_texture_common_extent_count',
  'webgpu_queue_write_texture_dict_extent_count',
  'webgpu_queue_write_texture_sequence_extent_count',
  'webgpu_queue_copy_external_image_count',
  'webgpu_queue_copy_external_image_default_origin_count',
  'webgpu_queue_copy_external_image_common_origin_count',
  'webgpu_queue_copy_external_image_explicit_common_origin_count',
  'webgpu_queue_copy_external_image_common_extent_count',
  'webgpu_queue_copy_external_image_dict_extent_count',
  'webgpu_queue_copy_external_image_sequence_extent_count',
  'webgpu_queue_copy_external_image_srgb_destination_count',
  'webgpu_queue_copy_external_image_full_source_count',
  'webgpu_queue_copy_element_image_count',
  'webgpu_queue_submit_count',
  'webgpu_queue_submit_command_buffer_count',
  'webgpu_queue_submit_single_command_buffer_count',
  'webgpu_queue_submit_small_batch_count',
  'webgpu_queue_submit_max_command_buffers',
  'webgpu_bind_group_set_count',
  'webgpu_bind_group_set_render_pass_count',
  'webgpu_bind_group_set_render_bundle_count',
  'webgpu_bind_group_set_compute_pass_count',
  'webgpu_bind_group_set_no_dynamic_offsets_count',
  'webgpu_bind_group_set_sequence_empty_dynamic_offsets_count',
  'webgpu_bind_group_set_typed_array_empty_dynamic_offsets_count',
  'webgpu_bind_group_set_non_empty_dynamic_offsets_count',
  'webgpu_bind_group_set_measured_count',
  'webgpu_bind_group_set_measured_typed_array_empty_dynamic_offsets_count',
  'webgpu_pipeline_set_count',
  'webgpu_pipeline_set_render_pass_count',
  'webgpu_pipeline_set_render_bundle_count',
  'webgpu_pipeline_set_compute_pass_count',
  'webgpu_pipeline_set_redundant_count',
  'webgpu_pipeline_set_measured_count',
  'webgpu_pipeline_set_measured_redundant_count',
  'webgpu_buffer_state_set_count',
  'webgpu_buffer_state_set_render_pass_count',
  'webgpu_buffer_state_set_render_bundle_count',
  'webgpu_buffer_state_set_redundant_count',
  'webgpu_buffer_state_set_measured_count',
  'webgpu_buffer_state_set_measured_redundant_count',
  'webgpu_render_state_set_count',
  'webgpu_render_state_set_render_pass_count',
  'webgpu_render_state_set_redundant_count',
  'webgpu_render_state_set_measured_count',
  'webgpu_render_state_set_measured_redundant_count',
  'webgpu_viewport_set_count',
  'webgpu_viewport_set_redundant_count',
  'webgpu_viewport_set_measured_count',
  'webgpu_viewport_set_measured_redundant_count',
  'webgpu_scissor_rect_set_count',
  'webgpu_scissor_rect_set_redundant_count',
  'webgpu_scissor_rect_set_measured_count',
  'webgpu_scissor_rect_set_measured_redundant_count',
  'webgpu_stencil_reference_set_count',
  'webgpu_stencil_reference_set_redundant_count',
  'webgpu_stencil_reference_set_measured_count',
  'webgpu_stencil_reference_set_measured_redundant_count',
  'webgpu_blend_constant_set_count',
  'webgpu_blend_constant_set_redundant_count',
  'webgpu_blend_constant_set_measured_count',
  'webgpu_blend_constant_set_measured_redundant_count',
  'webgpu_vertex_buffer_set_count',
  'webgpu_vertex_buffer_set_redundant_count',
  'webgpu_vertex_buffer_set_measured_count',
  'webgpu_vertex_buffer_set_measured_redundant_count',
  'webgpu_index_buffer_set_count',
  'webgpu_index_buffer_set_redundant_count',
  'webgpu_index_buffer_set_measured_count',
  'webgpu_index_buffer_set_measured_redundant_count',
  'webgpu_immediate_set_count',
  'webgpu_immediate_set_render_pass_count',
  'webgpu_immediate_set_render_bundle_count',
  'webgpu_immediate_set_compute_pass_count',
  'webgpu_immediate_set_full_span_count',
  'webgpu_immediate_set_sub_span_count',
  'webgpu_immediate_set_measured_count',
  'webgpu_immediate_set_measured_full_span_count',
  'webgpu_pipeline_create_render_count',
  'webgpu_pipeline_create_render_async_count',
  'webgpu_pipeline_create_compute_count',
  'webgpu_pipeline_create_compute_async_count',
  'webgpu_pipeline_create_total_count',
  'webgpu_pipeline_create_setup_count',
  'webgpu_pipeline_create_resource_warmup_count',
  'webgpu_pipeline_create_warmup_count',
  'webgpu_pipeline_create_measured_count',
  'webgpu_pipeline_create_other_count',
  'webgpu_pipeline_descriptor_render_count',
  'webgpu_pipeline_descriptor_compute_count',
  'webgpu_pipeline_descriptor_render_vertex_buffer_count',
  'webgpu_pipeline_descriptor_render_vertex_attribute_count',
  'webgpu_pipeline_descriptor_render_stack_vertex_buffer_eligible_count',
  'webgpu_pipeline_descriptor_render_color_target_count',
  'webgpu_pipeline_descriptor_render_blend_target_count',
  'webgpu_pipeline_descriptor_render_stack_color_target_eligible_count',
  'webgpu_pipeline_descriptor_vertex_constant_count',
  'webgpu_pipeline_descriptor_vertex_stack_constant_eligible_count',
  'webgpu_pipeline_descriptor_fragment_constant_count',
  'webgpu_pipeline_descriptor_fragment_stack_constant_eligible_count',
  'webgpu_pipeline_descriptor_compute_constant_count',
  'webgpu_pipeline_descriptor_compute_stack_constant_eligible_count',
  'webgpu_pipeline_descriptor_stack_fast_path_eligible_count',
  'webgpu_pipeline_descriptor_measured_count',
  'webgpu_pipeline_descriptor_measured_stack_fast_path_eligible_count',
]);

const shaderCompileEventSources = new Set([
  'renderer-program-delta',
  'scene-declared',
  'webgpu-pipeline-create-measured',
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

  for (const key of ['generated_at', 'browser_executable', 'browser_version', 'benchmark_variant', 'viewer_force_angle_backend', 'requested_angle_backend', 'viewer_url', 'viewer_url_scheme', 'viewer_origin', 'texture_upload_mode', 'webgpu_bundle_mode', 'resource_warmup_settle_gpu_method', 'resource_warmup_settle_gpu_error', 'resource_warmup_texture_init_error', 'resource_warmup_render_target_init_error', 'resource_warmup_pipeline_quiet_error', 'shader_compile_event_source', 'gpu_timer_type', 'gpu_timer_unavailable_reason', 'last_gpu_timer_error', 'webgpu_queue_instrumentation_error', 'webgpu_command_encoder_instrumentation_error', 'webgpu_bind_group_instrumentation_error', 'webgpu_pipeline_state_instrumentation_error', 'webgpu_buffer_state_instrumentation_error', 'webgpu_render_state_instrumentation_error', 'webgpu_immediate_instrumentation_error', 'webgpu_pipeline_instrumentation_error', 'webgpu_blob_cache_eligibility_reason', 'webgpu_device_loss_reason', 'webgpu_device_loss_message', 'webgpu_device_loss_source', 'last_render_error', 'profile_cache_mode', 'profile_cache_key', 'profile_dir']) {
    if (key in data && data[key] !== null && typeof data[key] !== 'string') {
      errors.push(`${key} must be a string or null`);
    }
  }

  if ('webgpu_bundle_mode' in data &&
      data.webgpu_bundle_mode !== null &&
      !['off', 'static'].includes(data.webgpu_bundle_mode)) {
    errors.push('webgpu_bundle_mode must be off or static when present');
  }
  if (data.renderer_type !== 'webgpu' && data.webgpu_bundle_mode === 'static') {
    errors.push('webgpu_bundle_mode=static is only valid with renderer_type=webgpu');
  }
  if (data.webgpu_bundle_mode !== 'static' &&
      isFiniteNumber(data.webgpu_bundle_groups) &&
      data.webgpu_bundle_groups > 0) {
    errors.push('webgpu_bundle_groups must be zero unless webgpu_bundle_mode=static');
  }
  if (data.renderer_type === 'webgpu' &&
      data.webgpu_bundle_mode === 'static' &&
      webGpuStaticBundleScenes.has(data.scene_name) &&
      (!Number.isInteger(data.webgpu_bundle_groups) || data.webgpu_bundle_groups <= 0)) {
    errors.push(`${data.scene_name}: webgpu_bundle_mode=static requires a positive webgpu_bundle_groups count`);
  }

  if ('profile_cache_mode' in data && data.profile_cache_mode !== null && !['fresh-temp', 'explicit-reuse'].includes(data.profile_cache_mode)) {
    errors.push('profile_cache_mode must be fresh-temp or explicit-reuse when present');
  }
  if ('shader_compile_event_source' in data &&
      data.shader_compile_event_source !== null &&
      !shaderCompileEventSources.has(data.shader_compile_event_source)) {
    errors.push(`shader_compile_event_source must be one of: ${[...shaderCompileEventSources].join(', ')}`);
  }
  if (data.profile_cache_mode === 'explicit-reuse') {
    if (data.profile_reuse_enabled !== true) {
      errors.push('profile_reuse_enabled must be true when profile_cache_mode is explicit-reuse');
    }
    if (typeof data.profile_cache_key !== 'string' || data.profile_cache_key.length === 0) {
      errors.push('profile_cache_key must be a non-empty string when profile_cache_mode is explicit-reuse');
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

  for (const key of optionalNonNegativeSeries) {
    if (!(key in data)) continue;
    if (!Array.isArray(data[key])) {
      errors.push(`${key} must be an array when present`);
    } else if (data[key].length === 0) {
      errors.push(`${key} must not be empty when present`);
    } else {
      data[key].forEach((value, index) => {
        if (!isFiniteNumber(value) || value < 0) {
          errors.push(`${key}[${index}] must be a non-negative finite number`);
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

  for (const key of integerNumbers) {
    if (key in data) validateInteger(data, key, errors);
  }

  if (isFiniteNumber(data.measured_seconds) && data.measured_seconds <= 0) {
    errors.push('measured_seconds must be greater than zero');
  }
  if (isFiniteNumber(data.complexity) && data.complexity <= 0) {
    errors.push('complexity must be greater than zero');
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
    data = readJson(file);
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
