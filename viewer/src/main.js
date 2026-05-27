import './styles.css';
import * as THREE from 'three';
import { createBenchmarkScene } from './scenes.js';
import { createRenderer, rendererMetadata } from './renderers.js';
import { BenchmarkRecorder } from './metrics.js';
import { WebGlGpuTimer } from './webgl_gpu_timer.js';
import { WebGpuGpuTimer } from './webgpu_gpu_timer.js';

const canvas = document.querySelector('#viewer');
const hud = document.querySelector('#hud');

function numberParam(params, name, fallback) {
  if (!params.has(name)) return fallback;
  const value = Number(params.get(name));
  return Number.isFinite(value) && value >= 0 ? value : fallback;
}

function booleanParam(params, name, fallback = false) {
  if (!params.has(name)) return fallback;
  return params.get(name) === '1' || params.get(name) === 'true';
}

function enumParam(params, name, fallback, allowedValues) {
  if (!params.has(name)) return fallback;
  const value = params.get(name);
  return allowedValues.includes(value) ? value : fallback;
}

function parseOptions() {
  const params = new URLSearchParams(window.location.search);
  const benchmark = params.get('benchmark') === '1';
  return {
    benchmark,
    sceneName: params.get('scene') || 'many-draw-calls',
    rendererType: params.get('renderer') || 'webgl2',
    warmupSeconds: numberParam(params, 'warmup', 5),
    measuredSeconds: numberParam(params, 'duration', 30),
    complexity: numberParam(params, 'complexity', 1),
    precompileResources: booleanParam(params, 'precompile'),
    prerenderFrames: numberParam(params, 'prerenderFrames', 0),
    settleGpuAfterWarmup: booleanParam(params, 'settleGpuAfterWarmup'),
    pipelineQuietFrames: Math.floor(numberParam(params, 'pipelineQuietFrames', 0)),
    pipelineQuietMaxFrames: Math.floor(numberParam(params, 'pipelineQuietMaxFrames', 30)),
    gpuTiming: booleanParam(params, 'gpuTiming', true),
    startDelayMs: numberParam(params, 'startDelayMs', 0),
    textureUploadMode: enumParam(params, 'textureUploadMode', 'canvas', ['canvas', 'data']),
    queueInstrumentation: booleanParam(params, 'queueInstrumentation'),
    commandEncoderInstrumentation: booleanParam(params, 'commandEncoderInstrumentation'),
    bindGroupInstrumentation: booleanParam(params, 'bindGroupInstrumentation'),
    pipelineStateInstrumentation: booleanParam(params, 'pipelineStateInstrumentation'),
    bufferStateInstrumentation: booleanParam(params, 'bufferStateInstrumentation'),
    renderStateInstrumentation: booleanParam(params, 'renderStateInstrumentation'),
    immediateInstrumentation: booleanParam(params, 'immediateInstrumentation'),
    webgpuBundleMode: enumParam(params, 'webgpuBundleMode', 'off', ['off', 'static']),
    showHud: booleanParam(params, 'showHud', !benchmark),
  };
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function fitRenderer(renderer) {
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  const width = Math.max(1, Math.floor(window.innerWidth * dpr));
  const height = Math.max(1, Math.floor(window.innerHeight * dpr));
  renderer.setPixelRatio(dpr);
  renderer.setSize(window.innerWidth, window.innerHeight, false);
  return { width, height, dpr };
}

function updateHud(options, recorder) {
  if (!options.showHud) return;
  const result = recorder.preview();
  const fps = result.avg_fps ? result.avg_fps.toFixed(1) : '--';
  const p95 = result.p95_frame_ms ? result.p95_frame_ms.toFixed(2) : '--';
  hud.innerHTML = [
    `<span>${options.rendererType} / ${options.sceneName}</span>`,
    `<span>fps ${fps} | p95 ${p95} ms</span>`,
  ].join('');
}

function isThenable(value) {
  return value && typeof value.then === 'function';
}

function finishRender(gpuTimer, renderStart) {
  gpuTimer?.end();
  return performance.now() - renderStart;
}

function renderOnce(renderer, sceneBundle, gpuTimer) {
  const renderStart = performance.now();
  renderer.info?.reset?.();
  gpuTimer?.begin();
  let renderResult;
  try {
    renderResult = sceneBundle.render
      ? sceneBundle.render(renderer)
      : renderer.render(sceneBundle.scene, sceneBundle.camera);
  } catch (error) {
    gpuTimer?.end();
    throw error;
  }

  if (isThenable(renderResult)) {
    return renderResult.then(
      () => finishRender(gpuTimer, renderStart),
      (error) => {
        gpuTimer?.end();
        throw error;
      },
    );
  }

  return finishRender(gpuTimer, renderStart);
}

function getCompileTargets(sceneBundle) {
  if (Array.isArray(sceneBundle.compileTargets) && sceneBundle.compileTargets.length > 0) {
    return sceneBundle.compileTargets.filter((target) => target?.scene && target?.camera);
  }
  if (sceneBundle.scene && sceneBundle.camera) {
    return [{ scene: sceneBundle.scene, camera: sceneBundle.camera }];
  }
  return [];
}

const MATERIAL_TEXTURE_KEYS = [
  'map',
  'matcap',
  'alphaMap',
  'aoMap',
  'bumpMap',
  'normalMap',
  'displacementMap',
  'roughnessMap',
  'metalnessMap',
  'emissiveMap',
  'envMap',
  'lightMap',
  'specularMap',
  'gradientMap',
  'clearcoatMap',
  'clearcoatNormalMap',
  'clearcoatRoughnessMap',
  'sheenColorMap',
  'sheenRoughnessMap',
  'iridescenceMap',
  'iridescenceThicknessMap',
  'transmissionMap',
  'thicknessMap',
];

function addTextureCandidate(textures, value) {
  if (value?.isTexture) textures.add(value);
}

function collectMaterialTextures(material, textures) {
  if (!material) return;
  for (const key of MATERIAL_TEXTURE_KEYS) {
    addTextureCandidate(textures, material[key]);
  }

  const uniforms = material.uniforms;
  if (uniforms && typeof uniforms === 'object') {
    for (const uniform of Object.values(uniforms)) {
      addTextureCandidate(textures, uniform?.value);
    }
  }
}

function collectSceneTextures(scene, textures) {
  scene?.traverse?.((object) => {
    const material = object.material;
    if (Array.isArray(material)) {
      for (const entry of material) collectMaterialTextures(entry, textures);
    } else {
      collectMaterialTextures(material, textures);
    }
  });
}

function getWarmupTextures(sceneBundle, compileTargets) {
  const textures = new Set();
  collectSceneTextures(sceneBundle.scene, textures);
  for (const target of compileTargets) collectSceneTextures(target.scene, textures);
  for (const texture of sceneBundle.warmupTextures || []) {
    addTextureCandidate(textures, texture);
  }
  return [...textures];
}

function getWarmupRenderTargets(sceneBundle) {
  const targets = new Set();
  for (const target of sceneBundle.renderTargets || []) {
    if (target) targets.add(target);
  }
  return [...targets];
}

function pipelineCreateCount(pipelineInstrumentation) {
  const snapshot = pipelineInstrumentation?.snapshot?.();
  if (!snapshot?.webgpu_pipeline_instrumentation_available) return null;
  const count = snapshot.webgpu_pipeline_create_total_count;
  return Number.isFinite(count) ? count : null;
}

async function drainSubmittedGpuWork(renderer) {
  const queue = renderer.backend?.device?.queue;
  if (queue && typeof queue.onSubmittedWorkDone === 'function') {
    await queue.onSubmittedWorkDone();
    return 'webgpu.queue.onSubmittedWorkDone';
  }

  const gl = renderer.getContext?.();
  if (gl && typeof gl.finish === 'function') {
    gl.finish();
    return 'webgl.finish';
  }

  return 'unavailable';
}

async function warmResources(renderer, sceneBundle, options, pipelineInstrumentation) {
  const pipelineQuietFrames = Math.max(0, Math.floor(options.pipelineQuietFrames || 0));
  const pipelineQuietMaxFrames = pipelineQuietFrames > 0
    ? Math.max(pipelineQuietFrames, Math.floor(options.pipelineQuietMaxFrames || pipelineQuietFrames))
    : 0;
  const enabled = options.precompileResources ||
    options.prerenderFrames > 0 ||
    options.settleGpuAfterWarmup ||
    pipelineQuietFrames > 0;
  const result = {
    enabled,
    precompile: options.precompileResources,
    prerenderFrames: options.prerenderFrames,
    settleGpu: options.settleGpuAfterWarmup,
    pipelineQuietFrames,
    pipelineQuietMaxFrames,
    pipelineQuietActualFrames: 0,
    pipelineQuietAchieved: false,
    compileTargets: 0,
    totalMs: 0,
    precompileMs: 0,
    prerenderMs: 0,
    pipelineQuietMs: 0,
    settleGpuMs: 0,
    settleGpuMethod: null,
    settleGpuError: null,
    pipelineQuietError: null,
    textureTargets: 0,
    renderTargets: 0,
    textureInitMs: 0,
    renderTargetInitMs: 0,
    textureInitError: null,
    renderTargetInitError: null,
  };

  if (!enabled) return result;

  const totalStart = performance.now();
  const compileTargets = getCompileTargets(sceneBundle);
  if (options.precompileResources && compileTargets.length > 0) {
    const renderTargets = getWarmupRenderTargets(sceneBundle);
    if (renderTargets.length > 0) {
      const start = performance.now();
      result.renderTargets = renderTargets.length;
      if (typeof renderer.initRenderTarget === 'function') {
        try {
          for (const target of renderTargets) renderer.initRenderTarget(target);
        } catch (error) {
          result.renderTargetInitError = error?.message || String(error);
        }
      } else {
        result.renderTargetInitError = 'renderer.initRenderTarget-unavailable';
      }
      result.renderTargetInitMs = performance.now() - start;
    }

    const textureTargets = getWarmupTextures(sceneBundle, compileTargets);
    if (textureTargets.length > 0) {
      const start = performance.now();
      result.textureTargets = textureTargets.length;
      if (typeof renderer.initTexture === 'function') {
        try {
          for (const texture of textureTargets) renderer.initTexture(texture);
        } catch (error) {
          result.textureInitError = error?.message || String(error);
        }
      } else {
        result.textureInitError = 'renderer.initTexture-unavailable';
      }
      result.textureInitMs = performance.now() - start;
    }

    const start = performance.now();
    result.compileTargets = compileTargets.length;
    for (const target of compileTargets) {
      if (renderer.compileAsync) {
        await renderer.compileAsync(target.scene, target.camera);
      } else if (renderer.compile) {
        renderer.compile(target.scene, target.camera);
      }
    }
    result.precompileMs = performance.now() - start;
  }

  if (options.prerenderFrames > 0) {
    const start = performance.now();
    for (let i = 0; i < options.prerenderFrames; i += 1) {
      sceneBundle.update?.(i / 60, 'resource-warmup');
      const renderResult = renderOnce(renderer, sceneBundle, null);
      if (isThenable(renderResult)) await renderResult;
    }
    result.prerenderMs = performance.now() - start;
  }

  if (pipelineQuietFrames > 0) {
    const start = performance.now();
    try {
      let lastPipelineCount = pipelineCreateCount(pipelineInstrumentation);
      if (lastPipelineCount === null) {
        result.pipelineQuietError = 'webgpu-pipeline-instrumentation-unavailable';
      } else {
        let quietFrameCount = 0;
        for (let i = 0; i < pipelineQuietMaxFrames && quietFrameCount < pipelineQuietFrames; i += 1) {
          sceneBundle.update?.((options.prerenderFrames + i) / 60, 'resource-warmup');
          const renderResult = renderOnce(renderer, sceneBundle, null);
          if (isThenable(renderResult)) await renderResult;
          await Promise.resolve();
          await drainSubmittedGpuWork(renderer);
          await Promise.resolve();

          result.pipelineQuietActualFrames += 1;
          const currentPipelineCount = pipelineCreateCount(pipelineInstrumentation);
          if (currentPipelineCount === lastPipelineCount) {
            quietFrameCount += 1;
          } else {
            quietFrameCount = 0;
            lastPipelineCount = currentPipelineCount;
          }
        }
        result.pipelineQuietAchieved = quietFrameCount >= pipelineQuietFrames;
        if (!result.pipelineQuietAchieved) {
          result.pipelineQuietError = `pipeline-create-not-quiet-after-${pipelineQuietMaxFrames}-frames`;
        }
      }
    } catch (error) {
      result.pipelineQuietError = error?.message || String(error);
    }
    result.pipelineQuietMs = performance.now() - start;
  }

  if (options.settleGpuAfterWarmup) {
    const start = performance.now();
    try {
      result.settleGpuMethod = await drainSubmittedGpuWork(renderer);
    } catch (error) {
      result.settleGpuError = error?.message || String(error);
    }
    result.settleGpuMs = performance.now() - start;
  }

  result.totalMs = performance.now() - totalStart;
  return result;
}

function createStabilityMonitor(canvas, renderer) {
  const state = {
    webglContextLostCount: 0,
    webglContextRestoredCount: 0,
    webglContextCurrentlyLost: false,
    webglLastContextLossMs: null,
    webgpuDeviceLost: false,
    webgpuDeviceLossReason: null,
    webgpuDeviceLossMessage: null,
    webgpuDeviceLossSource: null,
    renderErrorCount: 0,
    lastRenderError: null,
  };

  const recordWebGpuDeviceLoss = (info, source) => {
    state.webgpuDeviceLost = true;
    state.webgpuDeviceLossReason = info?.reason || state.webgpuDeviceLossReason;
    state.webgpuDeviceLossMessage = info?.message || state.webgpuDeviceLossMessage || String(info || '');
    state.webgpuDeviceLossSource = state.webgpuDeviceLossSource || source || null;
  };

  canvas.addEventListener('webglcontextlost', (event) => {
    event.preventDefault();
    state.webglContextLostCount += 1;
    state.webglContextCurrentlyLost = true;
    state.webglLastContextLossMs = performance.now();
  });

  canvas.addEventListener('webglcontextrestored', () => {
    state.webglContextRestoredCount += 1;
    state.webglContextCurrentlyLost = false;
  });

  if (renderer && typeof renderer.onDeviceLost === 'function') {
    const originalOnDeviceLost = renderer.onDeviceLost.bind(renderer);
    renderer.onDeviceLost = (info) => {
      recordWebGpuDeviceLoss(info, 'three.renderer.onDeviceLost');
      originalOnDeviceLost(info);
    };
  }

  const deviceLost = renderer?.backend?.device?.lost;
  if (deviceLost && typeof deviceLost.then === 'function') {
    deviceLost.then(
      (info) => recordWebGpuDeviceLoss(info, 'gpu.device.lost'),
      (error) => recordWebGpuDeviceLoss(error, 'gpu.device.lost.rejected'),
    );
  }

  return state;
}

function applyStabilityResult(result, stability) {
  result.webgl_context_lost_count = stability.webglContextLostCount;
  result.webgl_context_restored_count = stability.webglContextRestoredCount;
  result.webgl_context_currently_lost = stability.webglContextCurrentlyLost;
  result.webgl_last_context_loss_ms = stability.webglLastContextLossMs;
  result.webgpu_device_lost = stability.webgpuDeviceLost;
  result.webgpu_device_loss_reason = stability.webgpuDeviceLossReason;
  result.webgpu_device_loss_message = stability.webgpuDeviceLossMessage;
  result.webgpu_device_loss_source = stability.webgpuDeviceLossSource;
  result.render_error_count = stability.renderErrorCount;
  result.last_render_error = stability.lastRenderError;
}

async function settleStabilitySignalsBeforeResult() {
  await Promise.resolve();
  await new Promise((resolve) => {
    setTimeout(resolve, 0);
  });
  await Promise.resolve();
}

function createGpuTimer(rendererBundle, options) {
  if (!options.gpuTiming) return null;
  if (rendererBundle.gl) return new WebGlGpuTimer(rendererBundle.gl);
  if (rendererBundle.type === 'webgpu') return new WebGpuGpuTimer(rendererBundle.renderer);
  return null;
}

function byteLengthOf(value) {
  if (!value) return null;
  if (Number.isFinite(value.byteLength)) return value.byteLength;
  if (Number.isFinite(value.length)) return value.length;
  return null;
}

function bytesPerElementOf(value) {
  if (!value) return 1;
  if (Number.isFinite(value.BYTES_PER_ELEMENT) && value.BYTES_PER_ELEMENT > 0) {
    return value.BYTES_PER_ELEMENT;
  }
  return 1;
}

function normalizeExtent(extent) {
  if (Array.isArray(extent)) {
    return {
      width: Number(extent[0]) || 1,
      height: Number(extent[1]) || 1,
      depth: Number(extent[2]) || 1,
    };
  }
  if (extent && typeof extent === 'object') {
    return {
      width: Number(extent.width) || 1,
      height: Number(extent.height) || 1,
      depth: Number(extent.depthOrArrayLayers ?? extent.depth) || 1,
    };
  }
  return { width: 1, height: 1, depth: 1 };
}

function estimateRgba8ExtentBytes(extent) {
  const { width, height, depth } = normalizeExtent(extent);
  return Math.max(0, width * height * depth * 4);
}

function estimateWriteBufferBytes(args) {
  const data = args[2];
  const bytes = byteLengthOf(data);
  if (bytes === null) return 0;
  const bytesPerElement = bytesPerElementOf(data);
  const explicitElementCount = Number(args[4]);
  if (Number.isFinite(explicitElementCount) && explicitElementCount >= 0) {
    return Math.max(0, explicitElementCount * bytesPerElement);
  }
  const dataElementOffset = Math.max(0, Number(args[3]) || 0);
  return Math.max(0, bytes - dataElementOffset * bytesPerElement);
}

function estimateWriteTextureBytes(args) {
  return byteLengthOf(args[1]) ?? estimateRgba8ExtentBytes(args[3]);
}

function estimateTextureCopyBytes(args) {
  return estimateRgba8ExtentBytes(args[2]);
}

function estimateSubmitCommandBufferCount(args) {
  const commandBuffers = args[0];
  if (!commandBuffers) return 0;
  if (Array.isArray(commandBuffers)) return commandBuffers.length;
  if (Number.isFinite(commandBuffers.length)) return Math.max(0, Number(commandBuffers.length));
  return 0;
}

function estimateExplicitCopyBytes(args, index) {
  const value = Number(args[index]);
  return Number.isFinite(value) && value >= 0 ? value : 0;
}

function hasOwn(value, key) {
  return value != null && Object.prototype.hasOwnProperty.call(value, key);
}

function summarizeExtentShape(extent) {
  if (Array.isArray(extent)) {
    const length = extent.length;
    return {
      common: length >= 1 && length <= 3,
      dict: false,
      sequence: true,
      width: Number(extent[0]) || 0,
      height: Number(extent[1] ?? 1) || 0,
      depth: Number(extent[2] ?? 1) || 0,
    };
  }
  if (extent && typeof extent === 'object') {
    return {
      common: !hasOwn(extent, 'depth') && Number.isFinite(Number(extent.width)),
      dict: true,
      sequence: false,
      width: Number(extent.width) || 0,
      height: Number(extent.height ?? 1) || 0,
      depth: Number(extent.depthOrArrayLayers ?? 1) || 0,
    };
  }
  return { common: false, dict: false, sequence: false, width: 0, height: 0, depth: 0 };
}

function sourceDimensions(source) {
  if (!source || typeof source !== 'object') return { width: 0, height: 0 };
  const width = Number(source.width ?? source.videoWidth ?? source.naturalWidth);
  const height = Number(source.height ?? source.videoHeight ?? source.naturalHeight);
  return {
    width: Number.isFinite(width) ? width : 0,
    height: Number.isFinite(height) ? height : 0,
  };
}

function summarizeOrigin2DShape(value, explicit) {
  if (!explicit) {
    return {
      defaultOrigin: true,
      explicitOrigin: false,
      commonOrigin: true,
      explicitCommonOrigin: false,
      x: 0,
      y: 0,
    };
  }
  if (Array.isArray(value)) {
    const commonOrigin = value.length <= 2;
    return {
      defaultOrigin: false,
      explicitOrigin: true,
      commonOrigin,
      explicitCommonOrigin: commonOrigin,
      x: Number(value[0]) || 0,
      y: Number(value[1]) || 0,
    };
  }
  if (value && typeof value === 'object') {
    return {
      defaultOrigin: false,
      explicitOrigin: true,
      commonOrigin: true,
      explicitCommonOrigin: true,
      x: Number(value.x) || 0,
      y: Number(value.y) || 0,
    };
  }
  return {
    defaultOrigin: false,
    explicitOrigin: true,
    commonOrigin: false,
    explicitCommonOrigin: false,
    x: 0,
    y: 0,
  };
}

function summarizeWriteTextureDescriptor(args) {
  const layout = args[2] || {};
  const extent = summarizeExtentShape(args[3]);
  const hasBytesPerRow = Number.isFinite(Number(layout.bytesPerRow));
  return {
    commonLayout: (Number(layout.offset) || 0) === 0 && hasBytesPerRow && !hasOwn(layout, 'rowsPerImage'),
    commonExtent: extent.common,
    dictExtent: extent.dict,
    sequenceExtent: extent.sequence,
  };
}

function summarizeCopyExternalImageDescriptor(args) {
  const copyImage = args[0] || {};
  const destination = args[1] || {};
  const extent = summarizeExtentShape(args[2]);
  const dimensions = sourceDimensions(copyImage.source);
  const origin = summarizeOrigin2DShape(
    copyImage.origin,
    hasOwn(copyImage, 'origin'),
  );
  const fullSource =
    origin.commonOrigin &&
    origin.x === 0 &&
    origin.y === 0 &&
    dimensions.width > 0 &&
    dimensions.height > 0 &&
    extent.width === dimensions.width &&
    extent.height === dimensions.height &&
    extent.depth === 1;
  return {
    commonExtent: extent.common,
    dictExtent: extent.dict,
    sequenceExtent: extent.sequence,
    defaultOrigin: origin.defaultOrigin,
    commonOrigin: origin.commonOrigin,
    explicitCommonOrigin: origin.explicitCommonOrigin,
    srgbDestination: destination.colorSpace == null || destination.colorSpace === 'srgb',
    fullSource,
  };
}

function isGpuColorDict(value) {
  return value && typeof value === 'object' && !Array.isArray(value) &&
    Number.isFinite(Number(value.r)) &&
    Number.isFinite(Number(value.g)) &&
    Number.isFinite(Number(value.b)) &&
    Number.isFinite(Number(value.a));
}

function summarizeRenderPassDescriptor(args) {
  const descriptor = args[0];
  const attachments = Array.isArray(descriptor?.colorAttachments) ? descriptor.colorAttachments : [];
  let clearValueCount = 0;
  let clearValueDictCount = 0;
  for (const attachment of attachments) {
    if (!attachment || attachment.clearValue == null) continue;
    clearValueCount += 1;
    if (isGpuColorDict(attachment.clearValue)) clearValueDictCount += 1;
  }
  return {
    colorAttachmentCount: attachments.length,
    clearValueCount,
    clearValueDictCount,
    hasDepthStencilAttachment: descriptor?.depthStencilAttachment != null,
  };
}

function sequenceLength(value) {
  if (!value) return 0;
  if (Array.isArray(value)) return value.length;
  const length = Number(value.length);
  return Number.isFinite(length) && length >= 0 ? Math.floor(length) : 0;
}

function sequenceItems(value) {
  return Array.isArray(value) ? value : [];
}

function recordConstantCount(stage) {
  const constants = stage?.constants;
  if (!constants || typeof constants !== 'object') return 0;
  if (constants instanceof Map) return constants.size;
  return Object.keys(constants).length;
}

function summarizePipelineDescriptor(method, args) {
  const descriptor = args[0];
  const summary = {
    renderDescriptorCount: 0,
    computeDescriptorCount: 0,
    renderVertexBufferCount: 0,
    renderVertexAttributeCount: 0,
    renderStackVertexBufferEligibleCount: 0,
    renderColorTargetCount: 0,
    renderBlendTargetCount: 0,
    renderStackColorTargetEligibleCount: 0,
    vertexConstantCount: 0,
    vertexStackConstantEligibleCount: 0,
    fragmentConstantCount: 0,
    fragmentStackConstantEligibleCount: 0,
    computeConstantCount: 0,
    computeStackConstantEligibleCount: 0,
    stackFastPathEligibleCount: 0,
  };

  if (!descriptor || typeof descriptor !== 'object') return summary;

  const noteStackConstantEligibility = (count, key) => {
    if (count > 0 && count <= 8) {
      summary[key] += 1;
      summary.stackFastPathEligibleCount += 1;
    }
  };

  if (method === 'createRenderPipeline' || method === 'createRenderPipelineAsync') {
    summary.renderDescriptorCount = 1;
    const vertexBuffers = sequenceItems(descriptor.vertex?.buffers);
    summary.renderVertexBufferCount = sequenceLength(descriptor.vertex?.buffers);
    let maxAttributeCount = 0;
    for (const buffer of vertexBuffers) {
      const attributeCount = sequenceLength(buffer?.attributes);
      summary.renderVertexAttributeCount += attributeCount;
      maxAttributeCount = Math.max(maxAttributeCount, attributeCount);
    }
    if (
      summary.renderVertexBufferCount > 0 &&
      summary.renderVertexBufferCount <= 4 &&
      maxAttributeCount <= 8
    ) {
      summary.renderStackVertexBufferEligibleCount = 1;
      summary.stackFastPathEligibleCount += 1;
    }

    const colorTargets = sequenceItems(descriptor.fragment?.targets);
    summary.renderColorTargetCount = sequenceLength(descriptor.fragment?.targets);
    for (const target of colorTargets) {
      if (target?.blend) summary.renderBlendTargetCount += 1;
    }
    if (summary.renderColorTargetCount > 0 && summary.renderColorTargetCount <= 4) {
      summary.renderStackColorTargetEligibleCount = 1;
      summary.stackFastPathEligibleCount += 1;
    }

    summary.vertexConstantCount = recordConstantCount(descriptor.vertex);
    noteStackConstantEligibility(summary.vertexConstantCount, 'vertexStackConstantEligibleCount');
    summary.fragmentConstantCount = recordConstantCount(descriptor.fragment);
    noteStackConstantEligibility(summary.fragmentConstantCount, 'fragmentStackConstantEligibleCount');
    return summary;
  }

  if (method === 'createComputePipeline' || method === 'createComputePipelineAsync') {
    summary.computeDescriptorCount = 1;
    summary.computeConstantCount = recordConstantCount(descriptor.compute);
    noteStackConstantEligibility(summary.computeConstantCount, 'computeStackConstantEligibleCount');
  }

  return summary;
}

function installWebGpuQueueInstrumentation(rendererBundle, enabled) {
  const state = {
    enabled,
    available: false,
    error: enabled ? null : 'disabled',
    writeBufferCount: 0,
    writeBufferMs: 0,
    writeBufferBytes: 0,
    writeTextureCount: 0,
    writeTextureMs: 0,
    writeTextureBytes: 0,
    writeTextureCommonLayoutCount: 0,
    writeTextureCommonExtentCount: 0,
    writeTextureDictExtentCount: 0,
    writeTextureSequenceExtentCount: 0,
    copyExternalImageCount: 0,
    copyExternalImageMs: 0,
    copyExternalImageBytes: 0,
    copyExternalImageDefaultOriginCount: 0,
    copyExternalImageCommonOriginCount: 0,
    copyExternalImageExplicitCommonOriginCount: 0,
    copyExternalImageCommonExtentCount: 0,
    copyExternalImageDictExtentCount: 0,
    copyExternalImageSequenceExtentCount: 0,
    copyExternalImageSrgbDestinationCount: 0,
    copyExternalImageFullSourceCount: 0,
    copyElementImageCount: 0,
    copyElementImageMs: 0,
    copyElementImageBytes: 0,
    submitCount: 0,
    submitMs: 0,
    submitCommandBufferCount: 0,
    submitSingleCommandBufferCount: 0,
    submitSmallBatchCount: 0,
    submitMaxCommandBuffers: 0,
  };

  const snapshot = () => ({
    webgpu_queue_instrumentation_enabled: state.enabled,
    webgpu_queue_instrumentation_available: state.available,
    webgpu_queue_instrumentation_error: state.error,
    webgpu_queue_write_buffer_count: state.writeBufferCount,
    webgpu_queue_write_buffer_ms: state.writeBufferMs,
    webgpu_queue_write_buffer_estimated_mb: state.writeBufferBytes / (1024 * 1024),
    webgpu_queue_write_texture_count: state.writeTextureCount,
    webgpu_queue_write_texture_ms: state.writeTextureMs,
    webgpu_queue_write_texture_estimated_mb: state.writeTextureBytes / (1024 * 1024),
    webgpu_queue_write_texture_common_layout_count: state.writeTextureCommonLayoutCount,
    webgpu_queue_write_texture_common_extent_count: state.writeTextureCommonExtentCount,
    webgpu_queue_write_texture_dict_extent_count: state.writeTextureDictExtentCount,
    webgpu_queue_write_texture_sequence_extent_count: state.writeTextureSequenceExtentCount,
    webgpu_queue_copy_external_image_count: state.copyExternalImageCount,
    webgpu_queue_copy_external_image_ms: state.copyExternalImageMs,
    webgpu_queue_copy_external_image_estimated_mb: state.copyExternalImageBytes / (1024 * 1024),
    webgpu_queue_copy_external_image_default_origin_count: state.copyExternalImageDefaultOriginCount,
    webgpu_queue_copy_external_image_common_origin_count: state.copyExternalImageCommonOriginCount,
    webgpu_queue_copy_external_image_explicit_common_origin_count:
      state.copyExternalImageExplicitCommonOriginCount,
    webgpu_queue_copy_external_image_common_extent_count: state.copyExternalImageCommonExtentCount,
    webgpu_queue_copy_external_image_dict_extent_count: state.copyExternalImageDictExtentCount,
    webgpu_queue_copy_external_image_sequence_extent_count: state.copyExternalImageSequenceExtentCount,
    webgpu_queue_copy_external_image_srgb_destination_count:
      state.copyExternalImageSrgbDestinationCount,
    webgpu_queue_copy_external_image_full_source_count: state.copyExternalImageFullSourceCount,
    webgpu_queue_copy_element_image_count: state.copyElementImageCount,
    webgpu_queue_copy_element_image_ms: state.copyElementImageMs,
    webgpu_queue_copy_element_image_estimated_mb: state.copyElementImageBytes / (1024 * 1024),
    webgpu_queue_submit_count: state.submitCount,
    webgpu_queue_submit_ms: state.submitMs,
    webgpu_queue_submit_command_buffer_count: state.submitCommandBufferCount,
    webgpu_queue_submit_avg_command_buffers: state.submitCount > 0 ? state.submitCommandBufferCount / state.submitCount : 0,
    webgpu_queue_submit_single_command_buffer_count: state.submitSingleCommandBufferCount,
    webgpu_queue_submit_small_batch_count: state.submitSmallBatchCount,
    webgpu_queue_submit_max_command_buffers: state.submitMaxCommandBuffers,
  });

  if (!enabled) return { snapshot };
  if (rendererBundle.type !== 'webgpu') {
    state.error = 'renderer-not-webgpu';
    return { snapshot };
  }

  const queue = rendererBundle.renderer?.backend?.device?.queue;
  if (!queue) {
    state.error = 'queue-unavailable';
    return { snapshot };
  }

  const failures = [];
  let installedCount = 0;
  const install = ({ method, countKey, msKey, bytesKey, estimateBytes, recordArgs }) => {
    const original = queue[method];
    if (typeof original !== 'function') return;
    const createWrapper = () => function instrumentedWebGpuQueueMethod(...args) {
      const start = performance.now();
      try {
        return original.apply(this, args);
      } finally {
        state[countKey] += 1;
        state[msKey] += performance.now() - start;
        if (bytesKey && estimateBytes) state[bytesKey] += estimateBytes(args);
        if (recordArgs) recordArgs(args);
      }
    };
    const tryInstall = (target, label) => {
      try {
        const wrapper = createWrapper();
        target[method] = wrapper;
        if (target[method] === wrapper || queue[method] === wrapper) {
          installedCount += 1;
          return true;
        }
      } catch (error) {
        failures.push(`${method} ${label}: ${error?.message || String(error)}`);
      }
      return false;
    };

    if (tryInstall(queue, 'instance')) return;
    const prototype = Object.getPrototypeOf(queue);
    if (prototype && prototype !== queue) {
      tryInstall(prototype, 'prototype');
    }
  };

  install({
    method: 'writeBuffer',
    countKey: 'writeBufferCount',
    msKey: 'writeBufferMs',
    bytesKey: 'writeBufferBytes',
    estimateBytes: estimateWriteBufferBytes,
  });
  install({
    method: 'writeTexture',
    countKey: 'writeTextureCount',
    msKey: 'writeTextureMs',
    bytesKey: 'writeTextureBytes',
    estimateBytes: estimateWriteTextureBytes,
    recordArgs: (args) => {
      const summary = summarizeWriteTextureDescriptor(args);
      if (summary.commonLayout) state.writeTextureCommonLayoutCount += 1;
      if (summary.commonExtent) state.writeTextureCommonExtentCount += 1;
      if (summary.dictExtent) state.writeTextureDictExtentCount += 1;
      if (summary.sequenceExtent) state.writeTextureSequenceExtentCount += 1;
    },
  });
  install({
    method: 'copyExternalImageToTexture',
    countKey: 'copyExternalImageCount',
    msKey: 'copyExternalImageMs',
    bytesKey: 'copyExternalImageBytes',
    estimateBytes: estimateTextureCopyBytes,
    recordArgs: (args) => {
      const summary = summarizeCopyExternalImageDescriptor(args);
      if (summary.defaultOrigin) state.copyExternalImageDefaultOriginCount += 1;
      if (summary.commonOrigin) state.copyExternalImageCommonOriginCount += 1;
      if (summary.explicitCommonOrigin) state.copyExternalImageExplicitCommonOriginCount += 1;
      if (summary.commonExtent) state.copyExternalImageCommonExtentCount += 1;
      if (summary.dictExtent) state.copyExternalImageDictExtentCount += 1;
      if (summary.sequenceExtent) state.copyExternalImageSequenceExtentCount += 1;
      if (summary.srgbDestination) state.copyExternalImageSrgbDestinationCount += 1;
      if (summary.fullSource) state.copyExternalImageFullSourceCount += 1;
    },
  });
  install({
    method: 'copyElementImageToTexture',
    countKey: 'copyElementImageCount',
    msKey: 'copyElementImageMs',
    bytesKey: 'copyElementImageBytes',
    estimateBytes: estimateTextureCopyBytes,
  });
  install({
    method: 'submit',
    countKey: 'submitCount',
    msKey: 'submitMs',
    recordArgs: (args) => {
      const commandBufferCount = estimateSubmitCommandBufferCount(args);
      state.submitCommandBufferCount += commandBufferCount;
      state.submitMaxCommandBuffers = Math.max(state.submitMaxCommandBuffers, commandBufferCount);
      if (commandBufferCount === 1) state.submitSingleCommandBufferCount += 1;
      if (commandBufferCount > 0 && commandBufferCount <= 4) state.submitSmallBatchCount += 1;
    },
  });

  state.available = installedCount > 0;
  state.error = state.available ? null : (failures.join('; ') || 'no-queue-methods-wrapped');
  return { snapshot };
}

function installWebGpuCommandEncoderInstrumentation(rendererBundle, enabled) {
  const state = {
    enabled,
    available: false,
    error: enabled ? null : 'disabled',
    phase: 'setup',
    createCount: 0,
    createMs: 0,
    beginRenderPassCount: 0,
    beginRenderPassMs: 0,
    renderPassColorAttachmentCount: 0,
    renderPassMaxColorAttachments: 0,
    renderPassClearValueCount: 0,
    renderPassClearValueDictCount: 0,
    renderPassDepthStencilAttachmentCount: 0,
    measuredRenderPassCount: 0,
    measuredRenderPassClearValueDictCount: 0,
    beginComputePassCount: 0,
    beginComputePassMs: 0,
    finishCount: 0,
    finishMs: 0,
    copyBufferToBufferCount: 0,
    copyBufferToBufferMs: 0,
    copyBufferToBufferBytes: 0,
    copyBufferToTextureCount: 0,
    copyBufferToTextureMs: 0,
    copyBufferToTextureBytes: 0,
    copyTextureToBufferCount: 0,
    copyTextureToBufferMs: 0,
    copyTextureToBufferBytes: 0,
    copyTextureToTextureCount: 0,
    copyTextureToTextureMs: 0,
    copyTextureToTextureBytes: 0,
    measuredCopyCount: 0,
    measuredCopyBytes: 0,
  };

  const snapshot = () => ({
    webgpu_command_encoder_instrumentation_enabled: state.enabled,
    webgpu_command_encoder_instrumentation_available: state.available,
    webgpu_command_encoder_instrumentation_error: state.error,
    webgpu_command_encoder_create_count: state.createCount,
    webgpu_command_encoder_create_ms: state.createMs,
    webgpu_command_encoder_begin_render_pass_count: state.beginRenderPassCount,
    webgpu_command_encoder_begin_render_pass_ms: state.beginRenderPassMs,
    webgpu_command_encoder_render_pass_color_attachment_count: state.renderPassColorAttachmentCount,
    webgpu_command_encoder_render_pass_max_color_attachments: state.renderPassMaxColorAttachments,
    webgpu_command_encoder_render_pass_clear_value_count: state.renderPassClearValueCount,
    webgpu_command_encoder_render_pass_clear_value_dict_count: state.renderPassClearValueDictCount,
    webgpu_command_encoder_render_pass_depth_stencil_attachment_count:
      state.renderPassDepthStencilAttachmentCount,
    webgpu_command_encoder_render_pass_measured_count: state.measuredRenderPassCount,
    webgpu_command_encoder_render_pass_measured_clear_value_dict_count:
      state.measuredRenderPassClearValueDictCount,
    webgpu_command_encoder_begin_compute_pass_count: state.beginComputePassCount,
    webgpu_command_encoder_begin_compute_pass_ms: state.beginComputePassMs,
    webgpu_command_encoder_finish_count: state.finishCount,
    webgpu_command_encoder_finish_ms: state.finishMs,
    webgpu_command_encoder_copy_buffer_to_buffer_count: state.copyBufferToBufferCount,
    webgpu_command_encoder_copy_buffer_to_buffer_ms: state.copyBufferToBufferMs,
    webgpu_command_encoder_copy_buffer_to_buffer_estimated_mb: state.copyBufferToBufferBytes / (1024 * 1024),
    webgpu_command_encoder_copy_buffer_to_texture_count: state.copyBufferToTextureCount,
    webgpu_command_encoder_copy_buffer_to_texture_ms: state.copyBufferToTextureMs,
    webgpu_command_encoder_copy_buffer_to_texture_estimated_mb: state.copyBufferToTextureBytes / (1024 * 1024),
    webgpu_command_encoder_copy_texture_to_buffer_count: state.copyTextureToBufferCount,
    webgpu_command_encoder_copy_texture_to_buffer_ms: state.copyTextureToBufferMs,
    webgpu_command_encoder_copy_texture_to_buffer_estimated_mb: state.copyTextureToBufferBytes / (1024 * 1024),
    webgpu_command_encoder_copy_texture_to_texture_count: state.copyTextureToTextureCount,
    webgpu_command_encoder_copy_texture_to_texture_ms: state.copyTextureToTextureMs,
    webgpu_command_encoder_copy_texture_to_texture_estimated_mb: state.copyTextureToTextureBytes / (1024 * 1024),
    webgpu_command_encoder_copy_measured_count: state.measuredCopyCount,
    webgpu_command_encoder_copy_measured_estimated_mb: state.measuredCopyBytes / (1024 * 1024),
  });

  const setPhase = (phase) => {
    state.phase = phase || 'other';
  };

  if (!enabled) return { setPhase, snapshot };
  if (rendererBundle.type !== 'webgpu') {
    state.error = 'renderer-not-webgpu';
    return { setPhase, snapshot };
  }

  const device = rendererBundle.renderer?.backend?.device;
  const originalCreate = device?.createCommandEncoder;
  if (typeof originalCreate !== 'function') {
    state.error = 'create-command-encoder-unavailable';
    return { setPhase, snapshot };
  }

  const failures = [];
  const instrumentedEncoders = new WeakSet();
  const wrapEncoderMethod = (encoder, spec) => {
    const original = encoder?.[spec.method];
    if (typeof original !== 'function') return;
    if (original.__threeViewerCommandEncoderInstrumented) return;

    try {
      const wrapper = function instrumentedWebGpuCommandEncoderMethod(...args) {
        const phase = state.phase;
        const start = performance.now();
        try {
          return original.apply(this, args);
        } finally {
          const elapsed = performance.now() - start;
          const estimatedBytes = spec.estimateBytes ? spec.estimateBytes(args) : 0;
          if (spec.recordArgs) spec.recordArgs(args, phase);
          state[spec.countKey] += 1;
          state[spec.msKey] += elapsed;
          if (spec.bytesKey) state[spec.bytesKey] += estimatedBytes;
          if (spec.isCopy && phase === 'measure') {
            state.measuredCopyCount += 1;
            state.measuredCopyBytes += estimatedBytes;
          }
        }
      };
      Object.defineProperty(wrapper, '__threeViewerCommandEncoderInstrumented', { value: true });
      encoder[spec.method] = wrapper;
    } catch (error) {
      failures.push(`${spec.method}: ${error?.message || String(error)}`);
    }
  };

  const instrumentEncoder = (encoder) => {
    if (!encoder || instrumentedEncoders.has(encoder)) return encoder;
    instrumentedEncoders.add(encoder);
    [
      {
        method: 'beginRenderPass',
        countKey: 'beginRenderPassCount',
        msKey: 'beginRenderPassMs',
        recordArgs: (args, phase) => {
          const summary = summarizeRenderPassDescriptor(args);
          state.renderPassColorAttachmentCount += summary.colorAttachmentCount;
          state.renderPassMaxColorAttachments = Math.max(
            state.renderPassMaxColorAttachments,
            summary.colorAttachmentCount,
          );
          state.renderPassClearValueCount += summary.clearValueCount;
          state.renderPassClearValueDictCount += summary.clearValueDictCount;
          if (summary.hasDepthStencilAttachment) {
            state.renderPassDepthStencilAttachmentCount += 1;
          }
          if (phase === 'measure') {
            state.measuredRenderPassCount += 1;
            state.measuredRenderPassClearValueDictCount += summary.clearValueDictCount;
          }
        },
      },
      { method: 'beginComputePass', countKey: 'beginComputePassCount', msKey: 'beginComputePassMs' },
      { method: 'finish', countKey: 'finishCount', msKey: 'finishMs' },
      {
        method: 'copyBufferToBuffer',
        countKey: 'copyBufferToBufferCount',
        msKey: 'copyBufferToBufferMs',
        bytesKey: 'copyBufferToBufferBytes',
        estimateBytes: (args) => estimateExplicitCopyBytes(args, 4),
        isCopy: true,
      },
      {
        method: 'copyBufferToTexture',
        countKey: 'copyBufferToTextureCount',
        msKey: 'copyBufferToTextureMs',
        bytesKey: 'copyBufferToTextureBytes',
        estimateBytes: estimateTextureCopyBytes,
        isCopy: true,
      },
      {
        method: 'copyTextureToBuffer',
        countKey: 'copyTextureToBufferCount',
        msKey: 'copyTextureToBufferMs',
        bytesKey: 'copyTextureToBufferBytes',
        estimateBytes: estimateTextureCopyBytes,
        isCopy: true,
      },
      {
        method: 'copyTextureToTexture',
        countKey: 'copyTextureToTextureCount',
        msKey: 'copyTextureToTextureMs',
        bytesKey: 'copyTextureToTextureBytes',
        estimateBytes: estimateTextureCopyBytes,
        isCopy: true,
      },
    ].forEach((spec) => wrapEncoderMethod(encoder, spec));
    return encoder;
  };

  try {
    const wrapper = function instrumentedWebGpuCreateCommandEncoder(...args) {
      const start = performance.now();
      try {
        return instrumentEncoder(originalCreate.apply(this, args));
      } finally {
        state.createCount += 1;
        state.createMs += performance.now() - start;
      }
    };
    Object.defineProperty(wrapper, '__threeViewerCommandEncoderInstrumentationCreate', { value: true });
    device.createCommandEncoder = wrapper;
    state.available = true;
  } catch (error) {
    failures.push(`createCommandEncoder: ${error?.message || String(error)}`);
  }

  state.error = state.available
    ? (failures.length ? failures.join('; ') : null)
    : (failures.join('; ') || 'create-command-encoder-wrap-failed');
  return { setPhase, snapshot };
}

function dynamicOffsetClassification(args) {
  if (args.length < 3) return 'none';
  const dynamicOffsets = args[2];
  if (dynamicOffsets == null) return 'none';
  if (args.length >= 5) {
    const start = Number(args[3]);
    const length = Number(args[4]);
    if (start === 0 && length === 0) return 'typedArrayEmpty';
    return 'nonEmpty';
  }
  const length = Number(dynamicOffsets?.length);
  if (Number.isFinite(length) && length === 0) return 'sequenceEmpty';
  return 'nonEmpty';
}

function installWebGpuBindGroupInstrumentation(rendererBundle, enabled) {
  const state = {
    enabled,
    available: false,
    error: enabled ? null : 'disabled',
    phase: 'setup',
    setCount: 0,
    setMs: 0,
    renderPassCount: 0,
    renderBundleCount: 0,
    computePassCount: 0,
    noDynamicOffsetCount: 0,
    sequenceEmptyDynamicOffsetCount: 0,
    typedArrayEmptyDynamicOffsetCount: 0,
    nonEmptyDynamicOffsetCount: 0,
    measuredSetCount: 0,
    measuredTypedArrayEmptyDynamicOffsetCount: 0,
  };

  const snapshot = () => ({
    webgpu_bind_group_instrumentation_enabled: state.enabled,
    webgpu_bind_group_instrumentation_available: state.available,
    webgpu_bind_group_instrumentation_error: state.error,
    webgpu_bind_group_set_count: state.setCount,
    webgpu_bind_group_set_ms: state.setMs,
    webgpu_bind_group_set_render_pass_count: state.renderPassCount,
    webgpu_bind_group_set_render_bundle_count: state.renderBundleCount,
    webgpu_bind_group_set_compute_pass_count: state.computePassCount,
    webgpu_bind_group_set_no_dynamic_offsets_count: state.noDynamicOffsetCount,
    webgpu_bind_group_set_sequence_empty_dynamic_offsets_count: state.sequenceEmptyDynamicOffsetCount,
    webgpu_bind_group_set_typed_array_empty_dynamic_offsets_count: state.typedArrayEmptyDynamicOffsetCount,
    webgpu_bind_group_set_non_empty_dynamic_offsets_count: state.nonEmptyDynamicOffsetCount,
    webgpu_bind_group_set_measured_count: state.measuredSetCount,
    webgpu_bind_group_set_measured_typed_array_empty_dynamic_offsets_count:
      state.measuredTypedArrayEmptyDynamicOffsetCount,
  });

  const setPhase = (phase) => {
    state.phase = phase || 'other';
  };

  if (!enabled) return { setPhase, snapshot };
  if (rendererBundle.type !== 'webgpu') {
    state.error = 'renderer-not-webgpu';
    return { setPhase, snapshot };
  }

  const failures = [];
  let installedCount = 0;
  const lastPipelineByEncoder = new WeakMap();
  const install = ({ constructorName, encoderKey }) => {
    const constructor = globalThis[constructorName];
    const prototype = constructor?.prototype;
    const original = prototype?.setBindGroup;
    if (typeof original !== 'function') {
      failures.push(`${constructorName}.setBindGroup unavailable`);
      return;
    }
    if (original.__threeViewerBindGroupInstrumented) {
      installedCount += 1;
      return;
    }

    try {
      const wrapper = function instrumentedWebGpuSetBindGroup(...args) {
        const phase = state.phase;
        const start = performance.now();
        try {
          return original.apply(this, args);
        } finally {
          const elapsed = performance.now() - start;
          state.setCount += 1;
          state.setMs += elapsed;
          state[`${encoderKey}Count`] += 1;
          const classification = dynamicOffsetClassification(args);
          if (classification === 'none') state.noDynamicOffsetCount += 1;
          else if (classification === 'sequenceEmpty') state.sequenceEmptyDynamicOffsetCount += 1;
          else if (classification === 'typedArrayEmpty') state.typedArrayEmptyDynamicOffsetCount += 1;
          else state.nonEmptyDynamicOffsetCount += 1;
          if (phase === 'measure') {
            state.measuredSetCount += 1;
            if (classification === 'typedArrayEmpty') {
              state.measuredTypedArrayEmptyDynamicOffsetCount += 1;
            }
          }
        }
      };
      Object.defineProperty(wrapper, '__threeViewerBindGroupInstrumented', { value: true });
      prototype.setBindGroup = wrapper;
      installedCount += 1;
    } catch (error) {
      failures.push(`${constructorName}.setBindGroup: ${error?.message || String(error)}`);
    }
  };

  install({ constructorName: 'GPURenderPassEncoder', encoderKey: 'renderPass' });
  install({ constructorName: 'GPURenderBundleEncoder', encoderKey: 'renderBundle' });
  install({ constructorName: 'GPUComputePassEncoder', encoderKey: 'computePass' });

  state.available = installedCount > 0;
  state.error = state.available ? null : (failures.join('; ') || 'no-bind-group-methods-wrapped');
  return { setPhase, snapshot };
}

function installWebGpuPipelineStateInstrumentation(rendererBundle, enabled) {
  const state = {
    enabled,
    available: false,
    error: enabled ? null : 'disabled',
    phase: 'setup',
    setCount: 0,
    setMs: 0,
    renderPassCount: 0,
    renderBundleCount: 0,
    computePassCount: 0,
    redundantSetCount: 0,
    measuredSetCount: 0,
    measuredRedundantSetCount: 0,
  };

  const snapshot = () => ({
    webgpu_pipeline_state_instrumentation_enabled: state.enabled,
    webgpu_pipeline_state_instrumentation_available: state.available,
    webgpu_pipeline_state_instrumentation_error: state.error,
    webgpu_pipeline_set_count: state.setCount,
    webgpu_pipeline_set_ms: state.setMs,
    webgpu_pipeline_set_render_pass_count: state.renderPassCount,
    webgpu_pipeline_set_render_bundle_count: state.renderBundleCount,
    webgpu_pipeline_set_compute_pass_count: state.computePassCount,
    webgpu_pipeline_set_redundant_count: state.redundantSetCount,
    webgpu_pipeline_set_measured_count: state.measuredSetCount,
    webgpu_pipeline_set_measured_redundant_count: state.measuredRedundantSetCount,
  });

  const setPhase = (phase) => {
    state.phase = phase || 'other';
  };

  if (!enabled) return { setPhase, snapshot };
  if (rendererBundle.type !== 'webgpu') {
    state.error = 'renderer-not-webgpu';
    return { setPhase, snapshot };
  }

  const failures = [];
  let installedCount = 0;
  const install = ({ constructorName, encoderKey }) => {
    const constructor = globalThis[constructorName];
    const prototype = constructor?.prototype;
    const original = prototype?.setPipeline;
    if (typeof original !== 'function') {
      failures.push(`${constructorName}.setPipeline unavailable`);
      return;
    }
    if (original.__threeViewerPipelineStateInstrumented) {
      installedCount += 1;
      return;
    }

    try {
      const wrapper = function instrumentedWebGpuSetPipeline(...args) {
        const phase = state.phase;
        const pipeline = args[0] || null;
        const encoder = (typeof this === 'object' || typeof this === 'function') && this !== null ? this : null;
        const previous = encoder ? lastPipelineByEncoder.get(encoder) || null : null;
        const redundant = pipeline !== null && previous === pipeline;
        const start = performance.now();
        try {
          return original.apply(this, args);
        } finally {
          if (encoder) lastPipelineByEncoder.set(encoder, pipeline);
          const elapsed = performance.now() - start;
          state.setCount += 1;
          state.setMs += elapsed;
          state[`${encoderKey}Count`] += 1;
          if (redundant) state.redundantSetCount += 1;
          if (phase === 'measure') {
            state.measuredSetCount += 1;
            if (redundant) state.measuredRedundantSetCount += 1;
          }
        }
      };
      Object.defineProperty(wrapper, '__threeViewerPipelineStateInstrumented', { value: true });
      prototype.setPipeline = wrapper;
      installedCount += 1;
    } catch (error) {
      failures.push(`${constructorName}.setPipeline: ${error?.message || String(error)}`);
    }
  };

  install({ constructorName: 'GPURenderPassEncoder', encoderKey: 'renderPass' });
  install({ constructorName: 'GPURenderBundleEncoder', encoderKey: 'renderBundle' });
  install({ constructorName: 'GPUComputePassEncoder', encoderKey: 'computePass' });

  state.available = installedCount > 0;
  state.error = state.available ? null : (failures.join('; ') || 'no-pipeline-state-methods-wrapped');
  return { setPhase, snapshot };
}

function normalizeGpuBindingOffset(args, index) {
  if (args.length <= index || args[index] === undefined) return 0;
  const value = Number(args[index]);
  return Number.isFinite(value) ? value : args[index];
}

function normalizeGpuBindingSize(args, index) {
  const specified = args.length > index && args[index] !== undefined;
  if (!specified) return { specified, value: null };
  const value = Number(args[index]);
  return { specified, value: Number.isFinite(value) ? value : args[index] };
}

function sameGpuBindingState(left, right) {
  return Boolean(left && right) &&
    left.buffer === right.buffer &&
    left.offset === right.offset &&
    left.sizeSpecified === right.sizeSpecified &&
    left.size === right.size &&
    left.indexFormat === right.indexFormat;
}

function immediateDataClassification(args) {
  const dataOffset = args.length > 2 && args[2] !== undefined ? Number(args[2]) : 0;
  const hasExplicitSize = args.length > 3 && args[3] !== undefined;
  if (dataOffset === 0 && !hasExplicitSize) return 'fullSpan';
  if (dataOffset === 0 && hasExplicitSize) {
    const data = args[1];
    const byteLength = Number(data?.byteLength);
    const bytesPerElement = Number(data?.BYTES_PER_ELEMENT || 1);
    const explicitSize = Number(args[3]);
    if (
      Number.isFinite(byteLength) &&
      Number.isFinite(bytesPerElement) &&
      bytesPerElement > 0 &&
      Number.isFinite(explicitSize) &&
      explicitSize * bytesPerElement === byteLength
    ) {
      return 'fullSpan';
    }
  }
  return 'subSpan';
}

function installWebGpuImmediateInstrumentation(rendererBundle, enabled) {
  const state = {
    enabled,
    available: false,
    error: enabled ? null : 'disabled',
    phase: 'setup',
    setCount: 0,
    setMs: 0,
    renderPassCount: 0,
    renderBundleCount: 0,
    computePassCount: 0,
    fullSpanCount: 0,
    subSpanCount: 0,
    measuredSetCount: 0,
    measuredFullSpanCount: 0,
  };

  const snapshot = () => ({
    webgpu_immediate_instrumentation_enabled: state.enabled,
    webgpu_immediate_instrumentation_available: state.available,
    webgpu_immediate_instrumentation_error: state.error,
    webgpu_immediate_set_count: state.setCount,
    webgpu_immediate_set_ms: state.setMs,
    webgpu_immediate_set_render_pass_count: state.renderPassCount,
    webgpu_immediate_set_render_bundle_count: state.renderBundleCount,
    webgpu_immediate_set_compute_pass_count: state.computePassCount,
    webgpu_immediate_set_full_span_count: state.fullSpanCount,
    webgpu_immediate_set_sub_span_count: state.subSpanCount,
    webgpu_immediate_set_measured_count: state.measuredSetCount,
    webgpu_immediate_set_measured_full_span_count: state.measuredFullSpanCount,
  });

  const setPhase = (phase) => {
    state.phase = phase || 'other';
  };

  if (!enabled) return { setPhase, snapshot };
  if (rendererBundle.type !== 'webgpu') {
    state.error = 'renderer-not-webgpu';
    return { setPhase, snapshot };
  }

  const failures = [];
  let installedCount = 0;
  const install = ({ constructorName, encoderKey }) => {
    const constructor = globalThis[constructorName];
    const prototype = constructor?.prototype;
    const original = prototype?.setImmediates;
    if (typeof original !== 'function') {
      failures.push(`${constructorName}.setImmediates unavailable`);
      return;
    }
    if (original.__threeViewerImmediateInstrumented) {
      installedCount += 1;
      return;
    }

    try {
      const wrapper = function instrumentedWebGpuSetImmediates(...args) {
        const phase = state.phase;
        const classification = immediateDataClassification(args);
        const start = performance.now();
        try {
          return original.apply(this, args);
        } finally {
          const elapsed = performance.now() - start;
          state.setCount += 1;
          state.setMs += elapsed;
          state[`${encoderKey}Count`] += 1;
          if (classification === 'fullSpan') state.fullSpanCount += 1;
          else state.subSpanCount += 1;
          if (phase === 'measure') {
            state.measuredSetCount += 1;
            if (classification === 'fullSpan') state.measuredFullSpanCount += 1;
          }
        }
      };
      Object.defineProperty(wrapper, '__threeViewerImmediateInstrumented', { value: true });
      prototype.setImmediates = wrapper;
      installedCount += 1;
    } catch (error) {
      failures.push(`${constructorName}.setImmediates: ${error?.message || String(error)}`);
    }
  };

  install({ constructorName: 'GPURenderPassEncoder', encoderKey: 'renderPass' });
  install({ constructorName: 'GPURenderBundleEncoder', encoderKey: 'renderBundle' });
  install({ constructorName: 'GPUComputePassEncoder', encoderKey: 'computePass' });

  state.available = installedCount > 0;
  state.error = state.available ? null : (failures.join('; ') || 'no-immediate-methods-wrapped');
  return { setPhase, snapshot };
}

function installWebGpuBufferStateInstrumentation(rendererBundle, enabled) {
  const state = {
    enabled,
    available: false,
    error: enabled ? null : 'disabled',
    phase: 'setup',
    setCount: 0,
    setMs: 0,
    renderPassCount: 0,
    renderBundleCount: 0,
    redundantSetCount: 0,
    measuredSetCount: 0,
    measuredRedundantSetCount: 0,
    vertexSetCount: 0,
    vertexRedundantSetCount: 0,
    vertexMeasuredSetCount: 0,
    vertexMeasuredRedundantSetCount: 0,
    indexSetCount: 0,
    indexRedundantSetCount: 0,
    indexMeasuredSetCount: 0,
    indexMeasuredRedundantSetCount: 0,
  };

  const snapshot = () => ({
    webgpu_buffer_state_instrumentation_enabled: state.enabled,
    webgpu_buffer_state_instrumentation_available: state.available,
    webgpu_buffer_state_instrumentation_error: state.error,
    webgpu_buffer_state_set_count: state.setCount,
    webgpu_buffer_state_set_ms: state.setMs,
    webgpu_buffer_state_set_render_pass_count: state.renderPassCount,
    webgpu_buffer_state_set_render_bundle_count: state.renderBundleCount,
    webgpu_buffer_state_set_redundant_count: state.redundantSetCount,
    webgpu_buffer_state_set_measured_count: state.measuredSetCount,
    webgpu_buffer_state_set_measured_redundant_count: state.measuredRedundantSetCount,
    webgpu_vertex_buffer_set_count: state.vertexSetCount,
    webgpu_vertex_buffer_set_redundant_count: state.vertexRedundantSetCount,
    webgpu_vertex_buffer_set_measured_count: state.vertexMeasuredSetCount,
    webgpu_vertex_buffer_set_measured_redundant_count: state.vertexMeasuredRedundantSetCount,
    webgpu_index_buffer_set_count: state.indexSetCount,
    webgpu_index_buffer_set_redundant_count: state.indexRedundantSetCount,
    webgpu_index_buffer_set_measured_count: state.indexMeasuredSetCount,
    webgpu_index_buffer_set_measured_redundant_count: state.indexMeasuredRedundantSetCount,
  });

  const setPhase = (phase) => {
    state.phase = phase || 'other';
  };

  if (!enabled) return { setPhase, snapshot };
  if (rendererBundle.type !== 'webgpu') {
    state.error = 'renderer-not-webgpu';
    return { setPhase, snapshot };
  }

  const failures = [];
  let installedCount = 0;
  const lastVertexBuffersByEncoder = new WeakMap();
  const lastIndexBufferByEncoder = new WeakMap();

  const record = ({ encoderKey, kind, redundant, elapsed, phase }) => {
    state.setCount += 1;
    state.setMs += elapsed;
    state[`${encoderKey}Count`] += 1;
    if (redundant) state.redundantSetCount += 1;
    if (phase === 'measure') {
      state.measuredSetCount += 1;
      if (redundant) state.measuredRedundantSetCount += 1;
    }
    if (kind === 'vertex') {
      state.vertexSetCount += 1;
      if (redundant) state.vertexRedundantSetCount += 1;
      if (phase === 'measure') {
        state.vertexMeasuredSetCount += 1;
        if (redundant) state.vertexMeasuredRedundantSetCount += 1;
      }
    } else {
      state.indexSetCount += 1;
      if (redundant) state.indexRedundantSetCount += 1;
      if (phase === 'measure') {
        state.indexMeasuredSetCount += 1;
        if (redundant) state.indexMeasuredRedundantSetCount += 1;
      }
    }
  };

  const installVertex = ({ constructorName, encoderKey }) => {
    const constructor = globalThis[constructorName];
    const prototype = constructor?.prototype;
    const original = prototype?.setVertexBuffer;
    if (typeof original !== 'function') {
      failures.push(`${constructorName}.setVertexBuffer unavailable`);
      return;
    }
    if (original.__threeViewerBufferStateInstrumented) {
      installedCount += 1;
      return;
    }

    try {
      const wrapper = function instrumentedWebGpuSetVertexBuffer(...args) {
        const phase = state.phase;
        const encoder = (typeof this === 'object' || typeof this === 'function') && this !== null ? this : null;
        const slot = Number(args[0]);
        const size = normalizeGpuBindingSize(args, 3);
        const current = {
          buffer: args[1] || null,
          offset: normalizeGpuBindingOffset(args, 2),
          sizeSpecified: size.specified,
          size: size.value,
          indexFormat: null,
        };
        const slotMap = encoder ? lastVertexBuffersByEncoder.get(encoder) || null : null;
        const previous = Number.isFinite(slot) && slotMap ? slotMap.get(slot) || null : null;
        const redundant = Number.isFinite(slot) && sameGpuBindingState(previous, current);
        const start = performance.now();
        try {
          return original.apply(this, args);
        } finally {
          if (encoder && Number.isFinite(slot)) {
            const nextSlotMap = slotMap || new Map();
            nextSlotMap.set(slot, current);
            if (!slotMap) lastVertexBuffersByEncoder.set(encoder, nextSlotMap);
          }
          record({ encoderKey, kind: 'vertex', redundant, elapsed: performance.now() - start, phase });
        }
      };
      Object.defineProperty(wrapper, '__threeViewerBufferStateInstrumented', { value: true });
      prototype.setVertexBuffer = wrapper;
      installedCount += 1;
    } catch (error) {
      failures.push(`${constructorName}.setVertexBuffer: ${error?.message || String(error)}`);
    }
  };

  const installIndex = ({ constructorName, encoderKey }) => {
    const constructor = globalThis[constructorName];
    const prototype = constructor?.prototype;
    const original = prototype?.setIndexBuffer;
    if (typeof original !== 'function') {
      failures.push(`${constructorName}.setIndexBuffer unavailable`);
      return;
    }
    if (original.__threeViewerBufferStateInstrumented) {
      installedCount += 1;
      return;
    }

    try {
      const wrapper = function instrumentedWebGpuSetIndexBuffer(...args) {
        const phase = state.phase;
        const encoder = (typeof this === 'object' || typeof this === 'function') && this !== null ? this : null;
        const size = normalizeGpuBindingSize(args, 3);
        const current = {
          buffer: args[0] || null,
          offset: normalizeGpuBindingOffset(args, 2),
          sizeSpecified: size.specified,
          size: size.value,
          indexFormat: args[1] || null,
        };
        const previous = encoder ? lastIndexBufferByEncoder.get(encoder) || null : null;
        const redundant = sameGpuBindingState(previous, current);
        const start = performance.now();
        try {
          return original.apply(this, args);
        } finally {
          if (encoder) lastIndexBufferByEncoder.set(encoder, current);
          record({ encoderKey, kind: 'index', redundant, elapsed: performance.now() - start, phase });
        }
      };
      Object.defineProperty(wrapper, '__threeViewerBufferStateInstrumented', { value: true });
      prototype.setIndexBuffer = wrapper;
      installedCount += 1;
    } catch (error) {
      failures.push(`${constructorName}.setIndexBuffer: ${error?.message || String(error)}`);
    }
  };

  for (const target of [
    { constructorName: 'GPURenderPassEncoder', encoderKey: 'renderPass' },
    { constructorName: 'GPURenderBundleEncoder', encoderKey: 'renderBundle' },
  ]) {
    installVertex(target);
    installIndex(target);
  }

  state.available = installedCount > 0;
  state.error = state.available ? null : (failures.join('; ') || 'no-buffer-state-methods-wrapped');
  return { setPhase, snapshot };
}

function sameRenderStateValues(left, right) {
  return Boolean(left && right) &&
    left.length === right.length &&
    left.every((value, index) => value === right[index]);
}

function normalizeRenderStateValues(args) {
  const normalized = [];
  for (const value of args) {
    if (value && typeof value === 'object') {
      const dictLike = ['r', 'g', 'b', 'a'].every((key) => key in value);
      if (dictLike) {
        normalized.push(value.r, value.g, value.b, value.a);
        continue;
      }
      if (typeof value.length === 'number' && value.length >= 4) {
        normalized.push(value[0], value[1], value[2], value[3]);
        continue;
      }
    }
    normalized.push(value);
  }
  return normalized.map((value) => {
    const numberValue = Number(value);
    return Number.isFinite(numberValue) ? numberValue : value;
  });
}

function installWebGpuRenderStateInstrumentation(rendererBundle, enabled) {
  const state = {
    enabled,
    available: false,
    error: enabled ? null : 'disabled',
    phase: 'setup',
    setCount: 0,
    setMs: 0,
    redundantSetCount: 0,
    measuredSetCount: 0,
    measuredRedundantSetCount: 0,
    viewportSetCount: 0,
    viewportRedundantSetCount: 0,
    viewportMeasuredSetCount: 0,
    viewportMeasuredRedundantSetCount: 0,
    scissorSetCount: 0,
    scissorRedundantSetCount: 0,
    scissorMeasuredSetCount: 0,
    scissorMeasuredRedundantSetCount: 0,
    stencilSetCount: 0,
    stencilRedundantSetCount: 0,
    stencilMeasuredSetCount: 0,
    stencilMeasuredRedundantSetCount: 0,
    blendConstantSetCount: 0,
    blendConstantRedundantSetCount: 0,
    blendConstantMeasuredSetCount: 0,
    blendConstantMeasuredRedundantSetCount: 0,
  };

  const snapshot = () => ({
    webgpu_render_state_instrumentation_enabled: state.enabled,
    webgpu_render_state_instrumentation_available: state.available,
    webgpu_render_state_instrumentation_error: state.error,
    webgpu_render_state_set_count: state.setCount,
    webgpu_render_state_set_ms: state.setMs,
    webgpu_render_state_set_render_pass_count: state.setCount,
    webgpu_render_state_set_redundant_count: state.redundantSetCount,
    webgpu_render_state_set_measured_count: state.measuredSetCount,
    webgpu_render_state_set_measured_redundant_count: state.measuredRedundantSetCount,
    webgpu_viewport_set_count: state.viewportSetCount,
    webgpu_viewport_set_redundant_count: state.viewportRedundantSetCount,
    webgpu_viewport_set_measured_count: state.viewportMeasuredSetCount,
    webgpu_viewport_set_measured_redundant_count: state.viewportMeasuredRedundantSetCount,
    webgpu_scissor_rect_set_count: state.scissorSetCount,
    webgpu_scissor_rect_set_redundant_count: state.scissorRedundantSetCount,
    webgpu_scissor_rect_set_measured_count: state.scissorMeasuredSetCount,
    webgpu_scissor_rect_set_measured_redundant_count: state.scissorMeasuredRedundantSetCount,
    webgpu_stencil_reference_set_count: state.stencilSetCount,
    webgpu_stencil_reference_set_redundant_count: state.stencilRedundantSetCount,
    webgpu_stencil_reference_set_measured_count: state.stencilMeasuredSetCount,
    webgpu_stencil_reference_set_measured_redundant_count: state.stencilMeasuredRedundantSetCount,
    webgpu_blend_constant_set_count: state.blendConstantSetCount,
    webgpu_blend_constant_set_redundant_count: state.blendConstantRedundantSetCount,
    webgpu_blend_constant_set_measured_count: state.blendConstantMeasuredSetCount,
    webgpu_blend_constant_set_measured_redundant_count: state.blendConstantMeasuredRedundantSetCount,
  });

  const setPhase = (phase) => {
    state.phase = phase || 'other';
  };

  if (!enabled) return { setPhase, snapshot };
  if (rendererBundle.type !== 'webgpu') {
    state.error = 'renderer-not-webgpu';
    return { setPhase, snapshot };
  }

  const constructor = globalThis.GPURenderPassEncoder;
  const prototype = constructor?.prototype;
  if (!prototype) {
    state.error = 'GPURenderPassEncoder unavailable';
    return { setPhase, snapshot };
  }

  const failures = [];
  let installedCount = 0;
  const lastValuesByMethod = {
    setViewport: new WeakMap(),
    setScissorRect: new WeakMap(),
    setStencilReference: new WeakMap(),
    setBlendConstant: new WeakMap(),
  };

  const record = ({ kind, redundant, elapsed, phase }) => {
    state.setCount += 1;
    state.setMs += elapsed;
    if (redundant) state.redundantSetCount += 1;
    if (phase === 'measure') {
      state.measuredSetCount += 1;
      if (redundant) state.measuredRedundantSetCount += 1;
    }

    state[`${kind}SetCount`] += 1;
    if (redundant) state[`${kind}RedundantSetCount`] += 1;
    if (phase === 'measure') {
      state[`${kind}MeasuredSetCount`] += 1;
      if (redundant) state[`${kind}MeasuredRedundantSetCount`] += 1;
    }
  };

  const install = ({ method, kind }) => {
    const original = prototype[method];
    if (typeof original !== 'function') {
      failures.push(`GPURenderPassEncoder.${method} unavailable`);
      return;
    }
    if (original.__threeViewerRenderStateInstrumented) {
      installedCount += 1;
      return;
    }

    try {
      const wrapper = function instrumentedWebGpuRenderStateMethod(...args) {
        const phase = state.phase;
        const encoder = (typeof this === 'object' || typeof this === 'function') && this !== null ? this : null;
        const current = normalizeRenderStateValues(args);
        const previous = encoder ? lastValuesByMethod[method].get(encoder) || null : null;
        const redundant = sameRenderStateValues(previous, current);
        const start = performance.now();
        try {
          return original.apply(this, args);
        } finally {
          if (encoder) lastValuesByMethod[method].set(encoder, current);
          record({ kind, redundant, elapsed: performance.now() - start, phase });
        }
      };
      Object.defineProperty(wrapper, '__threeViewerRenderStateInstrumented', { value: true });
      prototype[method] = wrapper;
      installedCount += 1;
    } catch (error) {
      failures.push(`GPURenderPassEncoder.${method}: ${error?.message || String(error)}`);
    }
  };

  install({ method: 'setViewport', kind: 'viewport' });
  install({ method: 'setScissorRect', kind: 'scissor' });
  install({ method: 'setStencilReference', kind: 'stencil' });
  install({ method: 'setBlendConstant', kind: 'blendConstant' });

  state.available = installedCount > 0;
  state.error = state.available ? null : (failures.join('; ') || 'no-render-state-methods-wrapped');
  return { setPhase, snapshot };
}

function installWebGpuPipelineInstrumentation(rendererBundle, enabled = true) {
  const state = {
    enabled,
    available: false,
    error: enabled ? null : 'disabled',
    phase: 'setup',
    renderPipelineCount: 0,
    renderPipelineMs: 0,
    renderPipelineAsyncCount: 0,
    renderPipelineAsyncMs: 0,
    computePipelineCount: 0,
    computePipelineMs: 0,
    computePipelineAsyncCount: 0,
    computePipelineAsyncMs: 0,
    totalCount: 0,
    totalMs: 0,
    setupCount: 0,
    setupMs: 0,
    resourceWarmupCount: 0,
    resourceWarmupMs: 0,
    warmupCount: 0,
    warmupMs: 0,
    measuredCount: 0,
    measuredMs: 0,
    otherCount: 0,
    otherMs: 0,
    descriptorRenderCount: 0,
    descriptorComputeCount: 0,
    descriptorRenderVertexBufferCount: 0,
    descriptorRenderVertexAttributeCount: 0,
    descriptorRenderStackVertexBufferEligibleCount: 0,
    descriptorRenderColorTargetCount: 0,
    descriptorRenderBlendTargetCount: 0,
    descriptorRenderStackColorTargetEligibleCount: 0,
    descriptorVertexConstantCount: 0,
    descriptorVertexStackConstantEligibleCount: 0,
    descriptorFragmentConstantCount: 0,
    descriptorFragmentStackConstantEligibleCount: 0,
    descriptorComputeConstantCount: 0,
    descriptorComputeStackConstantEligibleCount: 0,
    descriptorStackFastPathEligibleCount: 0,
    descriptorMeasuredCount: 0,
    descriptorMeasuredStackFastPathEligibleCount: 0,
  };

  const phaseBucket = (phase) => {
    if (phase === 'setup' || phase === 'prepare') return 'setup';
    if (phase === 'resource-warmup') return 'resourceWarmup';
    if (phase === 'warmup') return 'warmup';
    if (phase === 'measure') return 'measured';
    return 'other';
  };

  const recordDescriptorSummary = (phase, descriptorSummary) => {
    if (!descriptorSummary) return;
    const descriptorCount =
      descriptorSummary.renderDescriptorCount + descriptorSummary.computeDescriptorCount;
    state.descriptorRenderCount += descriptorSummary.renderDescriptorCount;
    state.descriptorComputeCount += descriptorSummary.computeDescriptorCount;
    state.descriptorRenderVertexBufferCount += descriptorSummary.renderVertexBufferCount;
    state.descriptorRenderVertexAttributeCount += descriptorSummary.renderVertexAttributeCount;
    state.descriptorRenderStackVertexBufferEligibleCount +=
      descriptorSummary.renderStackVertexBufferEligibleCount;
    state.descriptorRenderColorTargetCount += descriptorSummary.renderColorTargetCount;
    state.descriptorRenderBlendTargetCount += descriptorSummary.renderBlendTargetCount;
    state.descriptorRenderStackColorTargetEligibleCount +=
      descriptorSummary.renderStackColorTargetEligibleCount;
    state.descriptorVertexConstantCount += descriptorSummary.vertexConstantCount;
    state.descriptorVertexStackConstantEligibleCount +=
      descriptorSummary.vertexStackConstantEligibleCount;
    state.descriptorFragmentConstantCount += descriptorSummary.fragmentConstantCount;
    state.descriptorFragmentStackConstantEligibleCount +=
      descriptorSummary.fragmentStackConstantEligibleCount;
    state.descriptorComputeConstantCount += descriptorSummary.computeConstantCount;
    state.descriptorComputeStackConstantEligibleCount +=
      descriptorSummary.computeStackConstantEligibleCount;
    state.descriptorStackFastPathEligibleCount += descriptorSummary.stackFastPathEligibleCount;
    if (phaseBucket(phase) === 'measured') {
      state.descriptorMeasuredCount += descriptorCount;
      state.descriptorMeasuredStackFastPathEligibleCount +=
        descriptorSummary.stackFastPathEligibleCount;
    }
  };

  const record = (phase, countKey, msKey, ms, descriptorSummary) => {
    const bucket = phaseBucket(phase);
    state[countKey] += 1;
    state[msKey] += ms;
    state.totalCount += 1;
    state.totalMs += ms;
    state[`${bucket}Count`] += 1;
    state[`${bucket}Ms`] += ms;
    recordDescriptorSummary(phase, descriptorSummary);
  };

  const snapshot = () => ({
    webgpu_pipeline_instrumentation_enabled: state.enabled,
    webgpu_pipeline_instrumentation_available: state.available,
    webgpu_pipeline_instrumentation_error: state.error,
    webgpu_pipeline_create_render_count: state.renderPipelineCount,
    webgpu_pipeline_create_render_ms: state.renderPipelineMs,
    webgpu_pipeline_create_render_async_count: state.renderPipelineAsyncCount,
    webgpu_pipeline_create_render_async_ms: state.renderPipelineAsyncMs,
    webgpu_pipeline_create_compute_count: state.computePipelineCount,
    webgpu_pipeline_create_compute_ms: state.computePipelineMs,
    webgpu_pipeline_create_compute_async_count: state.computePipelineAsyncCount,
    webgpu_pipeline_create_compute_async_ms: state.computePipelineAsyncMs,
    webgpu_pipeline_create_total_count: state.totalCount,
    webgpu_pipeline_create_total_ms: state.totalMs,
    webgpu_pipeline_create_setup_count: state.setupCount,
    webgpu_pipeline_create_setup_ms: state.setupMs,
    webgpu_pipeline_create_resource_warmup_count: state.resourceWarmupCount,
    webgpu_pipeline_create_resource_warmup_ms: state.resourceWarmupMs,
    webgpu_pipeline_create_warmup_count: state.warmupCount,
    webgpu_pipeline_create_warmup_ms: state.warmupMs,
    webgpu_pipeline_create_measured_count: state.measuredCount,
    webgpu_pipeline_create_measured_ms: state.measuredMs,
    webgpu_pipeline_create_other_count: state.otherCount,
    webgpu_pipeline_create_other_ms: state.otherMs,
    webgpu_pipeline_descriptor_render_count: state.descriptorRenderCount,
    webgpu_pipeline_descriptor_compute_count: state.descriptorComputeCount,
    webgpu_pipeline_descriptor_render_vertex_buffer_count:
      state.descriptorRenderVertexBufferCount,
    webgpu_pipeline_descriptor_render_vertex_attribute_count:
      state.descriptorRenderVertexAttributeCount,
    webgpu_pipeline_descriptor_render_stack_vertex_buffer_eligible_count:
      state.descriptorRenderStackVertexBufferEligibleCount,
    webgpu_pipeline_descriptor_render_color_target_count:
      state.descriptorRenderColorTargetCount,
    webgpu_pipeline_descriptor_render_blend_target_count:
      state.descriptorRenderBlendTargetCount,
    webgpu_pipeline_descriptor_render_stack_color_target_eligible_count:
      state.descriptorRenderStackColorTargetEligibleCount,
    webgpu_pipeline_descriptor_vertex_constant_count: state.descriptorVertexConstantCount,
    webgpu_pipeline_descriptor_vertex_stack_constant_eligible_count:
      state.descriptorVertexStackConstantEligibleCount,
    webgpu_pipeline_descriptor_fragment_constant_count:
      state.descriptorFragmentConstantCount,
    webgpu_pipeline_descriptor_fragment_stack_constant_eligible_count:
      state.descriptorFragmentStackConstantEligibleCount,
    webgpu_pipeline_descriptor_compute_constant_count:
      state.descriptorComputeConstantCount,
    webgpu_pipeline_descriptor_compute_stack_constant_eligible_count:
      state.descriptorComputeStackConstantEligibleCount,
    webgpu_pipeline_descriptor_stack_fast_path_eligible_count:
      state.descriptorStackFastPathEligibleCount,
    webgpu_pipeline_descriptor_measured_count: state.descriptorMeasuredCount,
    webgpu_pipeline_descriptor_measured_stack_fast_path_eligible_count:
      state.descriptorMeasuredStackFastPathEligibleCount,
  });

  const setPhase = (phase) => {
    state.phase = phase || 'other';
  };

  if (!enabled) return { setPhase, snapshot };
  if (rendererBundle.type !== 'webgpu') {
    state.error = 'renderer-not-webgpu';
    return { setPhase, snapshot };
  }

  const device = rendererBundle.renderer?.backend?.device;
  if (!device) {
    state.error = 'device-unavailable';
    return { setPhase, snapshot };
  }

  const failures = [];
  let installedCount = 0;
  const install = ({ method, countKey, msKey }) => {
    const createWrapper = (original) => {
      const wrapper = function instrumentedWebGpuPipelineMethod(...args) {
        const phase = state.phase;
        const descriptorSummary = summarizePipelineDescriptor(method, args);
        const start = performance.now();
        let result;
        try {
          result = original.apply(this, args);
        } catch (error) {
          record(phase, countKey, msKey, performance.now() - start, descriptorSummary);
          throw error;
        }
        if (isThenable(result)) {
          return result.then(
            (value) => {
              record(phase, countKey, msKey, performance.now() - start, descriptorSummary);
              return value;
            },
            (error) => {
              record(phase, countKey, msKey, performance.now() - start, descriptorSummary);
              throw error;
            },
          );
        }
        record(phase, countKey, msKey, performance.now() - start, descriptorSummary);
        return result;
      };
      Object.defineProperty(wrapper, '__threeViewerPipelineInstrumented', { value: true });
      return wrapper;
    };

    const tryInstall = (target, label) => {
      const original = target?.[method];
      if (typeof original !== 'function') return false;
      if (original.__threeViewerPipelineInstrumented) {
        installedCount += 1;
        return true;
      }
      try {
        const wrapper = createWrapper(original);
        target[method] = wrapper;
        if (target[method] === wrapper || device[method] === wrapper) {
          installedCount += 1;
          return true;
        }
      } catch (error) {
        failures.push(`${method} ${label}: ${error?.message || String(error)}`);
      }
      return false;
    };

    if (tryInstall(device, 'instance')) return;
    const prototype = Object.getPrototypeOf(device);
    if (prototype && prototype !== device) {
      tryInstall(prototype, 'prototype');
    }
  };

  install({
    method: 'createRenderPipeline',
    countKey: 'renderPipelineCount',
    msKey: 'renderPipelineMs',
  });
  install({
    method: 'createRenderPipelineAsync',
    countKey: 'renderPipelineAsyncCount',
    msKey: 'renderPipelineAsyncMs',
  });
  install({
    method: 'createComputePipeline',
    countKey: 'computePipelineCount',
    msKey: 'computePipelineMs',
  });
  install({
    method: 'createComputePipelineAsync',
    countKey: 'computePipelineAsyncCount',
    msKey: 'computePipelineAsyncMs',
  });

  state.available = installedCount > 0;
  state.error = state.available ? null : (failures.join('; ') || 'no-pipeline-methods-wrapped');
  return { setPhase, snapshot };
}

function applyRuntimeShaderCompileEvidence(result, pipelineMetrics) {
  const measuredPipelineEvents = pipelineMetrics.webgpu_pipeline_create_measured_count;
  if (!pipelineMetrics.webgpu_pipeline_instrumentation_available || !Number.isFinite(measuredPipelineEvents)) {
    return;
  }

  const currentRuntimeEvents = Number.isFinite(result.runtime_shader_compile_events)
    ? result.runtime_shader_compile_events
    : 0;
  result.runtime_shader_compile_events = Math.max(currentRuntimeEvents, measuredPipelineEvents);
  result.shader_compile_events = result.runtime_shader_compile_events;
  result.shader_compile_event_source = 'webgpu-pipeline-create-measured';
}

async function main() {
  const options = parseOptions();
  hud.hidden = !options.showHud;
  if (options.startDelayMs > 0) {
    await delay(options.startDelayMs);
  }

  const rendererBundle = await createRenderer({
    canvas,
    rendererType: options.rendererType,
    trackGpuTimestamps: options.gpuTiming,
  });
  const renderer = rendererBundle.renderer;
  const stability = createStabilityMonitor(canvas, renderer);
  const webGpuQueueInstrumentation = installWebGpuQueueInstrumentation(rendererBundle, options.queueInstrumentation);
  const webGpuCommandEncoderInstrumentation =
    installWebGpuCommandEncoderInstrumentation(rendererBundle, options.commandEncoderInstrumentation);
  const webGpuBindGroupInstrumentation =
    installWebGpuBindGroupInstrumentation(rendererBundle, options.bindGroupInstrumentation);
  const webGpuPipelineStateInstrumentation =
    installWebGpuPipelineStateInstrumentation(rendererBundle, options.pipelineStateInstrumentation);
  const webGpuBufferStateInstrumentation =
    installWebGpuBufferStateInstrumentation(rendererBundle, options.bufferStateInstrumentation);
  const webGpuRenderStateInstrumentation =
    installWebGpuRenderStateInstrumentation(rendererBundle, options.renderStateInstrumentation);
  const webGpuImmediateInstrumentation =
    installWebGpuImmediateInstrumentation(rendererBundle, options.immediateInstrumentation);
  const webGpuPipelineInstrumentation = installWebGpuPipelineInstrumentation(rendererBundle, true);
  fitRenderer(renderer);

  webGpuCommandEncoderInstrumentation.setPhase('prepare');
  webGpuBindGroupInstrumentation.setPhase('prepare');
  webGpuPipelineStateInstrumentation.setPhase('prepare');
  webGpuBufferStateInstrumentation.setPhase('prepare');
  webGpuRenderStateInstrumentation.setPhase('prepare');
  webGpuImmediateInstrumentation.setPhase('prepare');
  webGpuPipelineInstrumentation.setPhase('prepare');
  const sceneBundle = await createBenchmarkScene({
    THREE,
    rendererType: options.rendererType,
    sceneName: options.sceneName,
    complexity: options.complexity,
    textureUploadMode: options.textureUploadMode,
    webgpuBundleMode: options.webgpuBundleMode,
  });

  sceneBundle.resize?.(window.innerWidth, window.innerHeight);
  await sceneBundle.prepare?.(renderer);
  webGpuCommandEncoderInstrumentation.setPhase('resource-warmup');
  webGpuBindGroupInstrumentation.setPhase('resource-warmup');
  webGpuPipelineStateInstrumentation.setPhase('resource-warmup');
  webGpuBufferStateInstrumentation.setPhase('resource-warmup');
  webGpuRenderStateInstrumentation.setPhase('resource-warmup');
  webGpuImmediateInstrumentation.setPhase('resource-warmup');
  webGpuPipelineInstrumentation.setPhase('resource-warmup');
  const resourceWarmup = await warmResources(renderer, sceneBundle, options, webGpuPipelineInstrumentation);
  webGpuCommandEncoderInstrumentation.setPhase('idle');
  webGpuBindGroupInstrumentation.setPhase('idle');
  webGpuPipelineStateInstrumentation.setPhase('idle');
  webGpuBufferStateInstrumentation.setPhase('idle');
  webGpuRenderStateInstrumentation.setPhase('idle');
  webGpuImmediateInstrumentation.setPhase('idle');
  webGpuPipelineInstrumentation.setPhase('idle');

  const metadata = rendererMetadata(rendererBundle);
  const recorder = new BenchmarkRecorder({
    sceneName: options.sceneName,
    rendererType: options.rendererType,
    warmupSeconds: options.warmupSeconds,
    measuredSeconds: options.measuredSeconds,
    complexity: options.complexity,
    metadata,
    resourceWarmup,
  });

  const gpuTimer = createGpuTimer(rendererBundle, options);
  let lastHud = 0;
  let stopped = false;

  window.addEventListener('resize', () => {
    fitRenderer(renderer);
    sceneBundle.resize?.(window.innerWidth, window.innerHeight);
  });

  window.addEventListener('pointermove', (event) => {
    sceneBundle.input?.({
      x: event.clientX / Math.max(1, window.innerWidth),
      y: event.clientY / Math.max(1, window.innerHeight),
    });
  });

  function frame(now) {
    if (stopped) return;

    const frameStart = performance.now();
    const phase = recorder.beginFrame(now);
    webGpuCommandEncoderInstrumentation.setPhase(phase);
    webGpuBindGroupInstrumentation.setPhase(phase);
    webGpuPipelineStateInstrumentation.setPhase(phase);
    webGpuBufferStateInstrumentation.setPhase(phase);
    webGpuRenderStateInstrumentation.setPhase(phase);
    webGpuImmediateInstrumentation.setPhase(phase);
    webGpuPipelineInstrumentation.setPhase(phase);
    const updateStart = performance.now();
    sceneBundle.update?.(now * 0.001, phase);
    const updateMs = performance.now() - updateStart;

    const failFrame = (error) => {
      stability.renderErrorCount += 1;
      stability.lastRenderError = error?.message || String(error);
      throw error;
    };

    const finishFrame = (renderMs) => {
      const gpuSamples = gpuTimer?.poll() || [];
      const cpuFrameMs = performance.now() - frameStart;

      recorder.endFrame({
        now,
        phase,
        updateMs,
        renderMs,
        cpuFrameMs,
        gpuMs: gpuSamples.length ? gpuSamples.reduce((sum, value) => sum + value, 0) / gpuSamples.length : null,
        rendererInfo: renderer.info,
        sceneStats: sceneBundle.stats,
      });

      if (now - lastHud > 500) {
        updateHud(options, recorder);
        lastHud = now;
      }

      if (recorder.done) {
        stopped = true;
        const result = recorder.finalize();
        const stats = sceneBundle.stats || {};
        if (!result.draw_calls && stats.drawCalls) result.draw_calls = stats.drawCalls;
        if (!result.triangles && stats.triangles) result.triangles = stats.triangles;
        if (!result.buffer_upload_mb && stats.bufferUploadBytes) {
          result.buffer_upload_mb = stats.bufferUploadBytes / (1024 * 1024);
        }
        if (!result.texture_upload_mb && stats.textureUploadBytes) {
          result.texture_upload_mb = stats.textureUploadBytes / (1024 * 1024);
        }
        result.texture_upload_mode = stats.textureUploadMode || null;
        result.texture_update_count = stats.textureUpdateCount || null;
        result.scene_notes = stats.notes || [];
        if (resourceWarmup.enabled) {
          result.scene_notes.push(`Resource warmup: precompile=${resourceWarmup.precompile}, prerenderFrames=${resourceWarmup.prerenderFrames}, compileTargets=${resourceWarmup.compileTargets}, textureTargets=${resourceWarmup.textureTargets}, renderTargets=${resourceWarmup.renderTargets}.`);
          if (resourceWarmup.settleGpu) {
            result.scene_notes.push(`Resource warmup GPU settle: method=${resourceWarmup.settleGpuMethod}, ms=${resourceWarmup.settleGpuMs.toFixed(2)}.`);
          }
        }
        result.gpu_timing_enabled = options.gpuTiming;
        result.benchmark_hud_enabled = options.showHud;
        Object.assign(result, webGpuQueueInstrumentation.snapshot());
        Object.assign(result, webGpuCommandEncoderInstrumentation.snapshot());
        Object.assign(result, webGpuBindGroupInstrumentation.snapshot());
        Object.assign(result, webGpuPipelineStateInstrumentation.snapshot());
        Object.assign(result, webGpuBufferStateInstrumentation.snapshot());
        Object.assign(result, webGpuRenderStateInstrumentation.snapshot());
        Object.assign(result, webGpuImmediateInstrumentation.snapshot());
        const pipelineMetrics = webGpuPipelineInstrumentation.snapshot();
        Object.assign(result, pipelineMetrics);
        applyRuntimeShaderCompileEvidence(result, pipelineMetrics);
        if (gpuTimer?.metadata) Object.assign(result, gpuTimer.metadata());
        const emitResult = async () => {
          await settleStabilitySignalsBeforeResult();
          applyStabilityResult(result, stability);
          window.__THREE_VIEWER_BENCHMARK_RESULT__ = result;
          console.log(`THREE_VIEWER_RESULT ${JSON.stringify(result)}`);
          webGpuCommandEncoderInstrumentation.setPhase('done');
          webGpuBindGroupInstrumentation.setPhase('done');
          webGpuPipelineStateInstrumentation.setPhase('done');
          webGpuBufferStateInstrumentation.setPhase('done');
          webGpuRenderStateInstrumentation.setPhase('done');
          webGpuImmediateInstrumentation.setPhase('done');
          webGpuPipelineInstrumentation.setPhase('done');
        };
        emitResult().catch((error) => {
          stability.renderErrorCount += 1;
          stability.lastRenderError = error?.message || String(error);
          console.error(error);
        });
        return;
      }

      webGpuCommandEncoderInstrumentation.setPhase('idle');
      webGpuBindGroupInstrumentation.setPhase('idle');
      webGpuPipelineStateInstrumentation.setPhase('idle');
      webGpuBufferStateInstrumentation.setPhase('idle');
      webGpuRenderStateInstrumentation.setPhase('idle');
      webGpuImmediateInstrumentation.setPhase('idle');
      webGpuPipelineInstrumentation.setPhase('idle');
      requestAnimationFrame(frame);
    };

    let renderResult = 0;
    try {
      if (!stability.webglContextCurrentlyLost && !stability.webgpuDeviceLost) {
        renderResult = renderOnce(renderer, sceneBundle, gpuTimer);
      }
    } catch (error) {
      failFrame(error);
      return;
    }

    if (isThenable(renderResult)) {
      renderResult.then(finishFrame, failFrame);
      return;
    }

    finishFrame(renderResult);
  }

  requestAnimationFrame(frame);
}

main().catch((error) => {
  console.error(error);
  hud.hidden = false;
  hud.textContent = error?.message || String(error);
});
