function average(values) {
  if (!values.length) return null;
  return values.reduce((sum, value) => sum + value, 0) / values.length;
}

function percentile(values, fraction) {
  if (!values.length) return null;
  const sorted = [...values].sort((a, b) => a - b);
  const index = Math.min(sorted.length - 1, Math.max(0, Math.floor((sorted.length - 1) * fraction)));
  return sorted[index];
}

function lowFps(frameTimes, fraction) {
  if (!frameTimes.length) return null;
  const count = Math.max(1, Math.floor(frameTimes.length * fraction));
  const worst = [...frameTimes].sort((a, b) => b - a).slice(0, count);
  const avgWorstFrameMs = average(worst);
  return avgWorstFrameMs ? 1000 / avgWorstFrameMs : null;
}

function memoryMb() {
  const memory = performance.memory;
  return memory?.usedJSHeapSize ? memory.usedJSHeapSize / (1024 * 1024) : null;
}

function seriesStats(values) {
  const finite = values.filter(Number.isFinite);
  if (!finite.length) {
    return {
      start: null,
      end: null,
      peak: null,
      delta: null,
    };
  }

  const start = finite[0];
  const end = finite[finite.length - 1];
  return {
    start,
    end,
    peak: Math.max(...finite),
    delta: end - start,
  };
}

function rendererProgramCount(rendererInfo) {
  const memory = rendererInfo?.memory;
  if (Array.isArray(rendererInfo?.programs)) return rendererInfo.programs.length;
  if (Number.isFinite(memory?.programs)) return memory.programs;
  return null;
}

export class BenchmarkRecorder {
  constructor({ sceneName, rendererType, warmupSeconds, measuredSeconds, complexity = null, metadata, resourceWarmup }) {
    this.sceneName = sceneName;
    this.rendererType = rendererType;
    this.warmupSeconds = warmupSeconds;
    this.measuredSeconds = measuredSeconds;
    const numericComplexity = Number(complexity);
    this.complexity = Number.isFinite(numericComplexity) ? numericComplexity : null;
    this.metadata = metadata;
    this.resourceWarmup = resourceWarmup || null;
    this.firstFrameNow = null;
    this.firstFrameCompletedAt = null;
    this.lastMeasuredNow = null;
    this.measureStartNow = null;
    this.measureEndNow = null;
    this.done = false;

    this.frameTimes = [];
    this.cpuFrameTimes = [];
    this.updateTimes = [];
    this.renderTimes = [];
    this.gpuTimes = [];
    this.drawCalls = [];
    this.triangles = [];
    this.textureUploadBytes = 0;
    this.bufferUploadBytes = 0;
    this.runtimeShaderCompileEvents = null;
    this.sceneDeclaredShaderCompileEvents = 0;
    this.programBaseline = null;
    this.lastPreMeasureProgramCount = null;
    this.lastSceneStats = null;
    this.rendererMemory = {
      geometries: [],
      textures: [],
      programs: [],
    };
  }

  beginFrame(now) {
    if (this.firstFrameNow === null) this.firstFrameNow = now;
    const elapsed = (now - this.firstFrameNow) / 1000;
    if (elapsed < this.warmupSeconds) return 'warmup';
    if (elapsed < this.warmupSeconds + this.measuredSeconds) return 'measure';
    this.done = true;
    return 'done';
  }

  endFrame({ now, phase, updateMs, renderMs, cpuFrameMs, gpuMs, rendererInfo, sceneStats }) {
    if (this.firstFrameCompletedAt === null) {
      this.firstFrameCompletedAt = performance.now();
    }

    if (sceneStats) {
      this.lastSceneStats = sceneStats;
      this.sceneDeclaredShaderCompileEvents = Math.max(
        this.sceneDeclaredShaderCompileEvents,
        sceneStats.shaderCompileEvents || 0,
      );
    }

    const measuredProgramCount = rendererProgramCount(rendererInfo);
    if (Number.isFinite(measuredProgramCount)) {
      if (phase === 'measure') {
        if (this.programBaseline === null) {
          this.programBaseline = Number.isFinite(this.lastPreMeasureProgramCount)
            ? this.lastPreMeasureProgramCount
            : measuredProgramCount;
        }
      } else {
        this.lastPreMeasureProgramCount = measuredProgramCount;
      }
    }

    if (phase !== 'measure') return;

    if (this.measureStartNow === null) this.measureStartNow = now;
    this.measureEndNow = now;
    if (this.lastMeasuredNow !== null) {
      this.frameTimes.push(now - this.lastMeasuredNow);
    }
    this.lastMeasuredNow = now;

    this.cpuFrameTimes.push(cpuFrameMs);
    this.updateTimes.push(updateMs);
    this.renderTimes.push(renderMs);
    if (Number.isFinite(gpuMs)) this.gpuTimes.push(gpuMs);

    const render = rendererInfo?.render;
    if (render) {
      this.drawCalls.push(render.calls || sceneStats?.drawCalls || 0);
      this.triangles.push(render.triangles || sceneStats?.triangles || 0);
    } else if (sceneStats) {
      this.drawCalls.push(sceneStats.drawCalls || 0);
      this.triangles.push(sceneStats.triangles || 0);
    }

    if (sceneStats) {
      this.textureUploadBytes = sceneStats.textureUploadBytes || this.textureUploadBytes;
      this.bufferUploadBytes = sceneStats.bufferUploadBytes || this.bufferUploadBytes;
    }

    const memory = rendererInfo?.memory;
    if (memory) {
      if (Number.isFinite(memory.geometries)) this.rendererMemory.geometries.push(memory.geometries);
      if (Number.isFinite(memory.textures)) this.rendererMemory.textures.push(memory.textures);
    }
    if (Number.isFinite(measuredProgramCount)) {
      this.rendererMemory.programs.push(measuredProgramCount);
    }
  }

  preview() {
    return {
      avg_fps: this.avgFps(),
      p95_frame_ms: percentile(this.frameTimes, 0.95),
    };
  }

  avgFps() {
    if (this.measureStartNow === null || this.measureEndNow === null) return null;
    const elapsed = (this.measureEndNow - this.measureStartNow) / 1000;
    return elapsed > 0 ? this.frameTimes.length / elapsed : null;
  }

  finalize() {
    const avgFrameMs = average(this.frameTimes);
    const droppedFrames = this.frameTimes.filter((value) => value > 25).length;
    const droppedFrameRate = this.frameTimes.length
      ? droppedFrames / this.frameTimes.length
      : 0;
    const drawCalls = average(this.drawCalls) || this.lastSceneStats?.drawCalls || null;
    const triangles = average(this.triangles) || this.lastSceneStats?.triangles || null;
    const geometryMemory = seriesStats(this.rendererMemory.geometries);
    const textureMemory = seriesStats(this.rendererMemory.textures);
    const programMemory = seriesStats(this.rendererMemory.programs);
    if (Number.isFinite(programMemory.peak) && Number.isFinite(this.programBaseline)) {
      this.runtimeShaderCompileEvents = Math.max(0, Math.round(programMemory.peak - this.programBaseline));
    }
    const shaderCompileEvents = this.runtimeShaderCompileEvents !== null
      ? this.runtimeShaderCompileEvents
      : this.sceneDeclaredShaderCompileEvents;
    const shaderCompileEventSource = this.runtimeShaderCompileEvents !== null
      ? 'renderer-program-delta'
      : 'scene-declared';
    const result = {
      chromium_revision: null,
      fork_revision: null,
      build_args_hash: null,
      platform: navigator.userAgent,
      gpu_name: this.metadata.gpu_name,
      driver_version: this.metadata.driver_version,
      angle_backend: this.metadata.angle_backend,
      renderer_type: this.rendererType,
      scene_name: this.sceneName,
      complexity: this.complexity,
      warmup_seconds: this.warmupSeconds,
      measured_seconds: this.measuredSeconds,
      avg_fps: this.avgFps(),
      p50_frame_ms: percentile(this.frameTimes, 0.50),
      p95_frame_ms: percentile(this.frameTimes, 0.95),
      p99_frame_ms: percentile(this.frameTimes, 0.99),
      one_percent_low_fps: lowFps(this.frameTimes, 0.01),
      point_one_percent_low_fps: lowFps(this.frameTimes, 0.001),
      avg_cpu_frame_ms: average(this.cpuFrameTimes),
      avg_gpu_frame_ms: average(this.gpuTimes),
      avg_js_frame_ms: average(this.updateTimes),
      avg_render_submission_ms: average(this.renderTimes),
      p95_cpu_frame_ms: percentile(this.cpuFrameTimes, 0.95),
      p99_cpu_frame_ms: percentile(this.cpuFrameTimes, 0.99),
      p95_gpu_frame_ms: percentile(this.gpuTimes, 0.95),
      p99_gpu_frame_ms: percentile(this.gpuTimes, 0.99),
      p95_js_frame_ms: percentile(this.updateTimes, 0.95),
      p99_js_frame_ms: percentile(this.updateTimes, 0.99),
      p95_render_submission_ms: percentile(this.renderTimes, 0.95),
      p99_render_submission_ms: percentile(this.renderTimes, 0.99),
      avg_compositor_latency_ms: null,
      avg_presentation_latency_ms: null,
      avg_frame_ms: avgFrameMs,
      max_frame_ms: this.frameTimes.length ? Math.max(...this.frameTimes) : null,
      dropped_frames: droppedFrames,
      dropped_frame_rate: droppedFrameRate,
      draw_calls: drawCalls,
      triangles,
      texture_upload_mb: this.textureUploadBytes / (1024 * 1024),
      buffer_upload_mb: this.bufferUploadBytes / (1024 * 1024),
      shader_compile_events: shaderCompileEvents,
      runtime_shader_compile_events: this.runtimeShaderCompileEvents,
      scene_declared_shader_compile_events: this.sceneDeclaredShaderCompileEvents,
      shader_compile_event_source: shaderCompileEventSource,
      webgpu_bundle_mode: this.lastSceneStats?.webgpuBundleMode || 'off',
      webgpu_bundle_groups: this.lastSceneStats?.webgpuBundleGroups || 0,
      js_heap_mb: memoryMb(),
      gpu_memory_mb: null,
      process_rss_mb: null,
      startup_ms_to_first_frame: this.firstFrameCompletedAt,
      resource_warmup_enabled: Boolean(this.resourceWarmup?.enabled),
      resource_warmup_precompile: Boolean(this.resourceWarmup?.precompile),
      resource_warmup_prerender_frames: this.resourceWarmup?.prerenderFrames || 0,
      resource_warmup_settle_gpu: Boolean(this.resourceWarmup?.settleGpu),
      resource_warmup_pipeline_quiet_frames: this.resourceWarmup?.pipelineQuietFrames || 0,
      resource_warmup_pipeline_quiet_max_frames: this.resourceWarmup?.pipelineQuietMaxFrames || 0,
      resource_warmup_pipeline_quiet_actual_frames: this.resourceWarmup?.pipelineQuietActualFrames || 0,
      resource_warmup_pipeline_quiet_achieved: Boolean(this.resourceWarmup?.pipelineQuietAchieved),
      resource_warmup_compile_targets: this.resourceWarmup?.compileTargets || 0,
      resource_warmup_texture_targets: this.resourceWarmup?.textureTargets || 0,
      resource_warmup_render_targets: this.resourceWarmup?.renderTargets || 0,
      resource_warmup_ms: this.resourceWarmup?.totalMs || 0,
      resource_warmup_precompile_ms: this.resourceWarmup?.precompileMs || 0,
      resource_warmup_texture_init_ms: this.resourceWarmup?.textureInitMs || 0,
      resource_warmup_render_target_init_ms: this.resourceWarmup?.renderTargetInitMs || 0,
      resource_warmup_prerender_ms: this.resourceWarmup?.prerenderMs || 0,
      resource_warmup_pipeline_quiet_ms: this.resourceWarmup?.pipelineQuietMs || 0,
      resource_warmup_settle_gpu_ms: this.resourceWarmup?.settleGpuMs || 0,
      resource_warmup_settle_gpu_method: this.resourceWarmup?.settleGpuMethod || null,
      resource_warmup_settle_gpu_error: this.resourceWarmup?.settleGpuError || null,
      resource_warmup_texture_init_error: this.resourceWarmup?.textureInitError || null,
      resource_warmup_render_target_init_error: this.resourceWarmup?.renderTargetInitError || null,
      resource_warmup_pipeline_quiet_error: this.resourceWarmup?.pipelineQuietError || null,
      renderer_memory_geometries_start: geometryMemory.start,
      renderer_memory_geometries_end: geometryMemory.end,
      renderer_memory_geometries_peak: geometryMemory.peak,
      renderer_memory_geometries_delta: geometryMemory.delta,
      renderer_memory_textures_start: textureMemory.start,
      renderer_memory_textures_end: textureMemory.end,
      renderer_memory_textures_peak: textureMemory.peak,
      renderer_memory_textures_delta: textureMemory.delta,
      renderer_programs_start: programMemory.start,
      renderer_programs_end: programMemory.end,
      renderer_programs_peak: programMemory.peak,
      renderer_programs_delta: programMemory.delta,
      frame_times_ms: [...this.frameTimes],
      cpu_frame_times_ms: [...this.cpuFrameTimes],
      js_frame_times_ms: [...this.updateTimes],
      render_submission_times_ms: [...this.renderTimes],
    };
    if (this.gpuTimes.length) {
      result.gpu_frame_times_ms = [...this.gpuTimes];
    }
    return result;
  }
}
