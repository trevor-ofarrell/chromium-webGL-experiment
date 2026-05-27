import * as THREE from 'three';

function normalizeWebGpuAdapterInfo(info) {
  if (!info) return null;
  const parts = [
    info.description,
    info.vendor,
    info.architecture,
    info.device,
  ].filter((value) => typeof value === 'string' && value.trim().length > 0);
  return {
    gpu_name: parts.length ? `WebGPU (${parts.join(' / ')})` : null,
    driver_version: typeof info.vendor === 'string' && info.vendor.trim() ? info.vendor : null,
    angle_backend: 'WebGPU',
  };
}

async function requestWebGpuAdapterMetadata() {
  try {
    const adapter = await navigator.gpu.requestAdapter({ powerPreference: 'high-performance' });
    if (!adapter) return null;
    if (adapter.info) {
      return normalizeWebGpuAdapterInfo(adapter.info);
    }
    if (typeof adapter.requestAdapterInfo === 'function') {
      return normalizeWebGpuAdapterInfo(await adapter.requestAdapterInfo());
    }
  } catch {
    return null;
  }
  return null;
}

export async function createRenderer({ canvas, rendererType, trackGpuTimestamps = true }) {
  if (rendererType === 'webgpu') {
    if (!navigator.gpu) {
      throw new Error('WebGPU is not available in this browser.');
    }
    const metadata = await requestWebGpuAdapterMetadata();
    const module = await import('three/webgpu');
    const WebGPURenderer = module.WebGPURenderer || module.default;
    const renderer = new WebGPURenderer({
      canvas,
      antialias: false,
      alpha: false,
      powerPreference: 'high-performance',
      trackTimestamp: trackGpuTimestamps,
    });
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    if (renderer.info) renderer.info.autoReset = false;
    await renderer.init?.();
    return { renderer, type: 'webgpu', gl: null, metadata };
  }

  const attributes = {
    alpha: false,
    antialias: false,
    depth: true,
    stencil: false,
    desynchronized: true,
    powerPreference: 'high-performance',
    preserveDrawingBuffer: false,
  };
  const gl = canvas.getContext('webgl2', attributes);
  if (!gl) {
    throw new Error('WebGL2 context creation failed.');
  }

  const renderer = new THREE.WebGLRenderer({ canvas, context: gl });
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.info.autoReset = false;
  return { renderer, type: 'webgl2', gl };
}

export function rendererMetadata(bundle) {
  const metadata = {
    gpu_name: null,
    driver_version: null,
    angle_backend: null,
  };

  if (bundle.metadata) return bundle.metadata;
  if (!bundle.gl) return metadata;

  const gl = bundle.gl;
  const debugInfo = gl.getExtension('WEBGL_debug_renderer_info');
  if (debugInfo) {
    metadata.gpu_name = gl.getParameter(debugInfo.UNMASKED_RENDERER_WEBGL);
    const vendor = gl.getParameter(debugInfo.UNMASKED_VENDOR_WEBGL);
    metadata.driver_version = vendor || null;
    metadata.angle_backend = metadata.gpu_name || null;
  }

  return metadata;
}
