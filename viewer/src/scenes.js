import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';

function makeRng(seed) {
  let state = seed >>> 0;
  return () => {
    state = (1664525 * state + 1013904223) >>> 0;
    return state / 0x100000000;
  };
}

function viewerAssetUrl(relativePath) {
  return new URL(relativePath.replace(/^\/+/, ''), document.baseURI || window.location.href).href;
}

function makeCamera(THREE) {
  const camera = new THREE.PerspectiveCamera(60, window.innerWidth / Math.max(1, window.innerHeight), 0.1, 5000);
  camera.position.set(0, 18, 55);
  camera.lookAt(0, 0, 0);
  return camera;
}

function addLights(THREE, scene) {
  scene.add(new THREE.HemisphereLight(0xcfe8ff, 0x101820, 1.8));
  const key = new THREE.DirectionalLight(0xffffff, 2.5);
  key.position.set(24, 48, 32);
  scene.add(key);
}

function commonBundle(THREE, sceneName) {
  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0x05070a);
  const camera = makeCamera(THREE);
  addLights(THREE, scene);
  return {
    scene,
    camera,
    stats: {
      textureUploadBytes: 0,
      bufferUploadBytes: 0,
      shaderCompileEvents: 0,
      webgpuBundleMode: 'off',
      webgpuBundleGroups: 0,
      notes: [],
    },
    resize(width, height) {
      camera.aspect = width / Math.max(1, height);
      camera.updateProjectionMatrix();
    },
    input() {},
    sceneName,
  };
}

async function loadBundleGroupClass(rendererType, webgpuBundleMode) {
  if (rendererType !== 'webgpu' || webgpuBundleMode !== 'static') return null;
  const module = await import('three/webgpu');
  if (!module.BundleGroup) {
    throw new Error('webgpuBundleMode=static requested, but Three.js BundleGroup is unavailable.');
  }
  return module.BundleGroup;
}

function createBundleGroup(BundleGroup) {
  if (!BundleGroup) {
    return null;
  }
  const group = new BundleGroup();
  group.static = true;
  return group;
}

function recordBundleGroupUse(bundle, groupCount, description) {
  bundle.stats.webgpuBundleGroups += groupCount;
  if (groupCount > 0) {
    bundle.stats.notes.push(description);
  }
}

function finalizeBundleMode(bundle, rendererType, requestedMode) {
  const mode = rendererType === 'webgpu' ? requestedMode : 'off';
  bundle.stats.webgpuBundleMode = mode;
  if (mode === 'static' && bundle.stats.webgpuBundleGroups === 0) {
    bundle.stats.notes.push('WebGPU static BundleGroup mode was requested, but this scene has no bundle-compatible draw-call group.');
  }
  return bundle;
}

function cameraOrbit(camera, time, radius, height, speed = 0.2) {
  const angle = time * speed;
  camera.position.set(Math.cos(angle) * radius, height + Math.sin(angle * 0.7) * 4, Math.sin(angle) * radius);
  camera.lookAt(0, 0, 0);
}

function createManyDrawCalls({ THREE, complexity, BundleGroup = null }) {
  const bundle = commonBundle(THREE, 'many-draw-calls');
  const rng = makeRng(0x514a);
  const count = Math.floor(2200 * complexity);
  const geometry = new THREE.BoxGeometry(0.8, 0.8, 0.8);
  const materials = Array.from({ length: 12 }, (_, index) => new THREE.MeshStandardMaterial({
    color: new THREE.Color().setHSL(index / 12, 0.64, 0.54),
    roughness: 0.55,
    metalness: 0.08,
  }));
  const meshes = [];
  const side = Math.ceil(Math.sqrt(count));
  const bundleGroup = createBundleGroup(BundleGroup);
  const meshParent = bundleGroup || bundle.scene;
  if (bundleGroup) bundle.scene.add(bundleGroup);

  for (let i = 0; i < count; i += 1) {
    const mesh = new THREE.Mesh(geometry, materials[i % materials.length]);
    const x = (i % side - side / 2) * 1.28;
    const z = (Math.floor(i / side) - side / 2) * 1.28;
    mesh.position.set(x, (rng() - 0.5) * 5, z);
    mesh.rotation.set(rng() * Math.PI, rng() * Math.PI, rng() * Math.PI);
    meshParent.add(mesh);
    meshes.push(mesh);
  }

  bundle.stats.drawCalls = count;
  bundle.stats.triangles = count * 12;
  bundle.stats.bufferUploadBytes = count * 12 * 3 * 4;
  recordBundleGroupUse(
    bundle,
    bundleGroup ? 1 : 0,
    'WebGPU static BundleGroup wraps the many-draw-calls mesh set so WebGPURenderer can record render bundles.',
  );
  bundle.update = (time) => {
    cameraOrbit(bundle.camera, time, 62, 24, 0.18);
    for (let i = 0; i < meshes.length; i += 19) {
      meshes[i].rotation.y += 0.01;
      meshes[i].rotation.x += 0.006;
    }
  };

  return bundle;
}

function createInstancing({ THREE, complexity }) {
  const bundle = commonBundle(THREE, 'instancing');
  const rng = makeRng(0x1a57);
  const count = Math.floor(65000 * complexity);
  const geometry = new THREE.BoxGeometry(0.46, 0.46, 0.46);
  const material = new THREE.MeshStandardMaterial({
    color: 0xa6e3ff,
    roughness: 0.38,
    metalness: 0.2,
  });
  const mesh = new THREE.InstancedMesh(geometry, material, count);
  const matrix = new THREE.Matrix4();
  const color = new THREE.Color();
  const side = Math.ceil(Math.cbrt(count));

  for (let i = 0; i < count; i += 1) {
    const x = (i % side - side / 2) * 0.78;
    const y = (Math.floor(i / side) % side - side / 2) * 0.78;
    const z = (Math.floor(i / (side * side)) - side / 2) * 0.78;
    matrix.makeRotationFromEuler(new THREE.Euler(rng() * Math.PI, rng() * Math.PI, rng() * Math.PI));
    matrix.setPosition(x, y, z);
    mesh.setMatrixAt(i, matrix);
    color.setHSL(0.52 + rng() * 0.12, 0.5, 0.45 + rng() * 0.2);
    mesh.setColorAt(i, color);
  }

  mesh.instanceMatrix.needsUpdate = true;
  if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true;
  bundle.scene.add(mesh);
  bundle.stats.drawCalls = 1;
  bundle.stats.triangles = count * 12;
  bundle.stats.bufferUploadBytes = count * (16 + 3) * 4;
  bundle.update = (time) => {
    cameraOrbit(bundle.camera, time, 56, 18, 0.16);
    mesh.rotation.y = time * 0.08;
  };
  return bundle;
}

async function createWebGpuShaderHeavyMaterial() {
  const {
    MeshBasicNodeMaterial,
    TSL,
  } = await import('three/webgpu');

  const uTime = TSL.uniform(0);
  const heavyColor = TSL.wgslFn(`
    fn viewerShaderHeavy(p: vec3<f32>, n: vec3<f32>, uTime: f32) -> vec3<f32> {
      let pn = normalize(p);
      let nn = normalize(n);
      var v = 0.0;

      for (var i: i32 = 0; i < 56; i = i + 1) {
        let f = f32(i) * 0.071 + 0.4;
        v += sin(dot(pn, vec3<f32>(f, f * 1.7, f * 2.3)) * 18.0 + uTime * (0.7 + f));
        v += cos(dot(nn, vec3<f32>(f * 2.1, f * 0.8, f * 1.4)) * 12.0 - uTime * (0.3 + f));
      }

      let level = clamp(v / 112.0 + 0.5, 0.0, 1.0);
      return mix(vec3<f32>(0.05, 0.2, 0.7), vec3<f32>(0.9, 1.0, 0.45), smoothstep(0.25, 0.85, level));
    }
  `);

  const material = new MeshBasicNodeMaterial();
  material.colorNode = heavyColor({
    p: TSL.positionLocal,
    n: TSL.normalLocal,
    uTime,
  });
  material.userData.uTime = uTime;
  return material;
}

async function createShaderHeavy({ THREE, rendererType }) {
  const bundle = commonBundle(THREE, 'shader-heavy');
  const geometry = new THREE.IcosahedronGeometry(15, 5);
  let material;

  if (rendererType === 'webgpu') {
    material = await createWebGpuShaderHeavyMaterial();
    bundle.stats.notes.push('WebGPU shader-heavy uses a WGSL node material with the same loop count as the WebGL GLSL scene.');
  } else {
    material = new THREE.ShaderMaterial({
      uniforms: {
        uTime: { value: 0 },
      },
      vertexShader: `
        varying vec3 vNormal;
        varying vec3 vPos;
        void main() {
          vNormal = normalize(normalMatrix * normal);
          vPos = position;
          gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
        }
      `,
      fragmentShader: `
        precision highp float;
        uniform float uTime;
        varying vec3 vNormal;
        varying vec3 vPos;
        void main() {
          vec3 n = normalize(vNormal);
          vec3 p = normalize(vPos);
          float v = 0.0;
          for (int i = 0; i < 56; i++) {
            float f = float(i) * 0.071 + 0.4;
            v += sin(dot(p, vec3(f, f * 1.7, f * 2.3)) * 18.0 + uTime * (0.7 + f));
            v += cos(dot(n, vec3(f * 2.1, f * 0.8, f * 1.4)) * 12.0 - uTime * (0.3 + f));
          }
          v = v / 112.0 + 0.5;
          vec3 color = mix(vec3(0.05, 0.2, 0.7), vec3(0.9, 1.0, 0.45), smoothstep(0.25, 0.85, v));
          gl_FragColor = vec4(color, 1.0);
        }
      `,
    });
    bundle.stats.shaderCompileEvents = 1;
  }

  const mesh = new THREE.Mesh(geometry, material);
  bundle.scene.add(mesh);
  bundle.stats.drawCalls = 1;
  bundle.stats.triangles = geometry.index ? geometry.index.count / 3 : geometry.attributes.position.count / 3;
  bundle.stats.bufferUploadBytes = geometry.attributes.position.count * 3 * 4;
  bundle.update = (time) => {
    cameraOrbit(bundle.camera, time, 45, 16, 0.12);
    mesh.rotation.x = time * 0.2;
    mesh.rotation.y = time * 0.13;
    if (material.uniforms?.uTime) material.uniforms.uTime.value = time;
    if (material.userData?.uTime) material.userData.uTime.value = time;
  };
  return bundle;
}

function writeTextureDataBlock(data, textureSize, x, y, size, r, g, b) {
  const xStart = Math.max(0, x);
  const yStart = Math.max(0, y);
  const xEnd = Math.min(textureSize, x + size);
  const yEnd = Math.min(textureSize, y + size);
  for (let py = yStart; py < yEnd; py += 1) {
    let offset = (py * textureSize + xStart) * 4;
    for (let px = xStart; px < xEnd; px += 1) {
      data[offset] = r;
      data[offset + 1] = g;
      data[offset + 2] = b;
      data[offset + 3] = 255;
      offset += 4;
    }
  }
}

function seedTextureData(data, textureSize, seed) {
  const colorA = [42 + (seed * 17) % 128, 84 + (seed * 29) % 128, 128 + (seed * 37) % 96];
  const colorB = [180 + (seed * 11) % 64, 64 + (seed * 23) % 96, 52 + (seed * 31) % 128];
  for (let y = 0; y < textureSize; y += 1) {
    for (let x = 0; x < textureSize; x += 1) {
      const color = ((x >> 4) + (y >> 4) + seed) % 2 === 0 ? colorA : colorB;
      const offset = (y * textureSize + x) * 4;
      data[offset] = color[0];
      data[offset + 1] = color[1];
      data[offset + 2] = color[2];
      data[offset + 3] = 255;
    }
  }
}

async function createTextureStreaming({ THREE, complexity, textureUploadMode = 'canvas', BundleGroup = null }) {
  const bundle = commonBundle(THREE, 'texture-streaming');
  const rng = makeRng(0x7e71);
  const textureCount = Math.floor(48 * complexity);
  const textureSize = 192;
  const geometry = new THREE.PlaneGeometry(2.4, 2.4);
  const canvases = [];
  const contexts = [];
  const textureData = [];
  const textures = [];
  const meshes = [];
  const bundleGroup = createBundleGroup(BundleGroup);
  const meshParent = bundleGroup || bundle.scene;
  if (bundleGroup) bundle.scene.add(bundleGroup);

  let assetTexture = null;
  try {
    const response = await fetch(viewerAssetUrl('assets/checker.svg'), { cache: 'no-store' });
    const blob = await response.blob();
    const bitmap = await createImageBitmap(blob);
    assetTexture = new THREE.Texture(bitmap);
    assetTexture.colorSpace = THREE.SRGBColorSpace;
    assetTexture.needsUpdate = true;
    bundle.stats.textureUploadBytes += bitmap.width * bitmap.height * 4;
  } catch {
    assetTexture = await new THREE.TextureLoader().loadAsync(viewerAssetUrl('assets/checker.svg'));
  }

  for (let i = 0; i < textureCount; i += 1) {
    let texture;
    if (textureUploadMode === 'data') {
      const data = new Uint8Array(textureSize * textureSize * 4);
      seedTextureData(data, textureSize, i);
      texture = new THREE.DataTexture(data, textureSize, textureSize, THREE.RGBAFormat, THREE.UnsignedByteType);
      textureData.push(data);
    } else {
      const canvas = document.createElement('canvas');
      canvas.width = textureSize;
      canvas.height = textureSize;
      const context = canvas.getContext('2d', { alpha: false });
      texture = new THREE.CanvasTexture(canvas);
      canvases.push(canvas);
      contexts.push(context);
      textureData.push(null);
    }
    texture.colorSpace = THREE.SRGBColorSpace;
    texture.needsUpdate = true;
    const material = new THREE.MeshBasicMaterial({ map: i === 0 ? assetTexture : texture });
    const mesh = new THREE.Mesh(geometry, material);
    const side = Math.ceil(Math.sqrt(textureCount));
    mesh.position.set((i % side - side / 2) * 3.0, (Math.floor(i / side) - side / 2) * 3.0, 0);
    meshParent.add(mesh);
    textures.push(texture);
    meshes.push(mesh);
  }

  bundle.stats.drawCalls = textureCount;
  bundle.stats.triangles = textureCount * 2;
  bundle.stats.textureUploadMode = textureUploadMode;
  bundle.stats.textureUpdateCount = 0;
  bundle.stats.notes.push(`Texture streaming upload mode: ${textureUploadMode}.`);
  recordBundleGroupUse(
    bundle,
    bundleGroup ? 1 : 0,
    'WebGPU static BundleGroup wraps the texture-streaming mesh set while texture contents continue to update each frame.',
  );
  bundle.camera.position.set(0, 0, Math.max(24, Math.sqrt(textureCount) * 5.8));
  bundle.camera.lookAt(0, 0, 0);
  const updateColor = new THREE.Color();
  bundle.update = (time) => {
    for (let i = 1; i < textures.length; i += 1) {
      const hue = Math.floor((time * 50 + i * 19) % 360);
      if (textureUploadMode === 'data') {
        const data = textureData[i];
        updateColor.setHSL(((hue + 150) % 360) / 360, 0.8, 0.68);
        const r = Math.floor(updateColor.r * 255);
        const g = Math.floor(updateColor.g * 255);
        const b = Math.floor(updateColor.b * 255);
        for (let j = 0; j < 12; j += 1) {
          const x = Math.floor(rng() * textureSize);
          const y = Math.floor(rng() * textureSize);
          writeTextureDataBlock(data, textureSize, x, y, 18, r, g, b);
        }
      } else {
        const context = contexts[i];
        context.fillStyle = `hsl(${hue}, 70%, 36%)`;
        context.fillRect(0, 0, textureSize, textureSize);
        context.fillStyle = `hsl(${(hue + 150) % 360}, 80%, 68%)`;
        for (let j = 0; j < 12; j += 1) {
          const x = Math.floor(rng() * textureSize);
          const y = Math.floor(rng() * textureSize);
          context.fillRect(x, y, 18, 18);
        }
      }
      textures[i].needsUpdate = true;
      meshes[i].rotation.z = Math.sin(time + i) * 0.08;
    }
    bundle.stats.textureUpdateCount += Math.max(0, textures.length - 1);
    bundle.stats.textureUploadBytes += Math.max(0, textures.length - 1) * textureSize * textureSize * 4;
  };

  return bundle;
}

function createPostprocessing({ THREE, rendererType, complexity }) {
  const bundle = commonBundle(THREE, 'postprocessing');
  const baseScene = bundle.scene;
  const baseCamera = bundle.camera;
  const count = Math.floor(22000 * complexity);
  const geometry = new THREE.TorusKnotGeometry(0.18, 0.045, 32, 8);
  const material = new THREE.MeshStandardMaterial({ color: 0xf7c948, roughness: 0.42, metalness: 0.28 });
  const mesh = new THREE.InstancedMesh(geometry, material, count);
  const matrix = new THREE.Matrix4();
  const side = Math.ceil(Math.sqrt(count));

  for (let i = 0; i < count; i += 1) {
    matrix.makeTranslation((i % side - side / 2) * 0.55, 0, (Math.floor(i / side) - side / 2) * 0.55);
    mesh.setMatrixAt(i, matrix);
  }
  baseScene.add(mesh);
  bundle.stats.drawCalls = 2;
  bundle.stats.triangles = count * (geometry.index ? geometry.index.count / 3 : geometry.attributes.position.count / 3) + 2;

  const RenderTarget = rendererType === 'webgpu' && THREE.RenderTarget ? THREE.RenderTarget : THREE.WebGLRenderTarget;
  const target = new RenderTarget(1, 1, {
    depthBuffer: true,
    stencilBuffer: false,
  });
  const screenScene = new THREE.Scene();
  const screenCamera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
  const screenMaterial = rendererType === 'webgpu'
    ? new THREE.MeshBasicMaterial({ map: target.texture })
    : new THREE.ShaderMaterial({
        uniforms: {
          tDiffuse: { value: target.texture },
          uTime: { value: 0 },
          uTexel: { value: new THREE.Vector2(1, 1) },
        },
        vertexShader: `
          varying vec2 vUv;
          void main() {
            vUv = uv;
            gl_Position = vec4(position.xy, 0.0, 1.0);
          }
        `,
        fragmentShader: `
          precision highp float;
          uniform sampler2D tDiffuse;
          uniform float uTime;
          uniform vec2 uTexel;
          varying vec2 vUv;
          void main() {
            vec3 color = texture2D(tDiffuse, vUv).rgb * 0.34;
            color += texture2D(tDiffuse, vUv + vec2(uTexel.x, 0.0)).rgb * 0.16;
            color += texture2D(tDiffuse, vUv - vec2(uTexel.x, 0.0)).rgb * 0.16;
            color += texture2D(tDiffuse, vUv + vec2(0.0, uTexel.y)).rgb * 0.16;
            color += texture2D(tDiffuse, vUv - vec2(0.0, uTexel.y)).rgb * 0.16;
            float scan = 0.96 + 0.04 * sin((vUv.y + uTime * 0.05) * 900.0);
            gl_FragColor = vec4(color * scan, 1.0);
          }
        `,
      });
  screenScene.add(new THREE.Mesh(new THREE.PlaneGeometry(2, 2), screenMaterial));

  bundle.stats.shaderCompileEvents = 1;
  bundle.stats.bufferUploadBytes = count * 16 * 4;
  if (rendererType === 'webgpu') {
    bundle.stats.notes.push('WebGPU postprocessing uses a RenderTarget plus full-screen MeshBasicMaterial pass; custom WGSL effect shader is future work.');
  }
  bundle.resize = (width, height) => {
    baseCamera.aspect = width / Math.max(1, height);
    baseCamera.updateProjectionMatrix();
    target.setSize(Math.max(1, width), Math.max(1, height));
    screenMaterial.uniforms?.uTexel?.value.set(1 / Math.max(1, width), 1 / Math.max(1, height));
  };
  bundle.update = (time) => {
    cameraOrbit(baseCamera, time, 64, 32, 0.12);
    mesh.rotation.y = time * 0.04;
    if (screenMaterial.uniforms?.uTime) screenMaterial.uniforms.uTime.value = time;
  };
  bundle.render = (renderer) => {
    renderer.setRenderTarget(target);
    renderer.render(baseScene, baseCamera);
    renderer.setRenderTarget(null);
    renderer.render(screenScene, screenCamera);
  };
  bundle.renderTargets = [target];
  bundle.compileTargets = [
    { scene: baseScene, camera: baseCamera },
    { scene: screenScene, camera: screenCamera },
  ];
  return bundle;
}

function createLargeStatic({ THREE, complexity }) {
  const bundle = commonBundle(THREE, 'large-static');
  const grid = Math.floor(360 * Math.sqrt(complexity));
  const vertexCount = (grid + 1) * (grid + 1);
  const positions = new Float32Array(vertexCount * 3);
  const normals = new Float32Array(vertexCount * 3);
  const colors = new Float32Array(vertexCount * 3);
  const indices = new Uint32Array(grid * grid * 6);
  const size = 180;
  let p = 0;

  for (let z = 0; z <= grid; z += 1) {
    for (let x = 0; x <= grid; x += 1) {
      const nx = x / grid - 0.5;
      const nz = z / grid - 0.5;
      const y = Math.sin(nx * 28) * Math.cos(nz * 23) * 5 + Math.sin((nx + nz) * 48) * 1.5;
      positions[p * 3] = nx * size;
      positions[p * 3 + 1] = y;
      positions[p * 3 + 2] = nz * size;
      normals[p * 3] = 0;
      normals[p * 3 + 1] = 1;
      normals[p * 3 + 2] = 0;
      colors[p * 3] = 0.18 + y * 0.012;
      colors[p * 3 + 1] = 0.5 + y * 0.01;
      colors[p * 3 + 2] = 0.72;
      p += 1;
    }
  }

  let n = 0;
  for (let z = 0; z < grid; z += 1) {
    for (let x = 0; x < grid; x += 1) {
      const a = z * (grid + 1) + x;
      const b = a + 1;
      const c = a + grid + 1;
      const d = c + 1;
      indices[n++] = a;
      indices[n++] = c;
      indices[n++] = b;
      indices[n++] = b;
      indices[n++] = c;
      indices[n++] = d;
    }
  }

  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute('position', new THREE.BufferAttribute(positions, 3));
  geometry.setAttribute('normal', new THREE.BufferAttribute(normals, 3));
  geometry.setAttribute('color', new THREE.BufferAttribute(colors, 3));
  geometry.setIndex(new THREE.BufferAttribute(indices, 1));
  geometry.computeBoundingSphere();

  const material = new THREE.MeshStandardMaterial({
    vertexColors: true,
    roughness: 0.7,
    metalness: 0.03,
  });
  const mesh = new THREE.Mesh(geometry, material);
  bundle.scene.add(mesh);
  bundle.stats.drawCalls = 1;
  bundle.stats.triangles = indices.length / 3;
  bundle.stats.bufferUploadBytes = positions.byteLength + normals.byteLength + colors.byteLength + indices.byteLength;
  bundle.update = (time) => {
    cameraOrbit(bundle.camera, time, 155, 58, 0.08);
  };
  return bundle;
}

async function createGltfLoaderStress({ THREE, complexity, BundleGroup = null }) {
  const bundle = commonBundle(THREE, 'gltf-loader-stress');
  const loader = new GLTFLoader();
  const gltf = await loader.loadAsync(viewerAssetUrl('assets/models/cube-stress.gltf'));
  const loadedMeshes = [];
  gltf.scene.traverse((object) => {
    if (object.isMesh) loadedMeshes.push(object);
  });
  if (!loadedMeshes.length) {
    throw new Error('gltf-loader-stress asset did not contain a mesh.');
  }

  const sourceMesh = loadedMeshes[0];
  const geometry = sourceMesh.geometry;
  const baseMaterial = sourceMesh.material;
  const materials = Array.from({ length: 10 }, (_, index) => {
    const material = baseMaterial.clone();
    if (material.color) {
      material.color = new THREE.Color().setHSL(0.52 + index * 0.035, 0.64, 0.55);
    }
    return material;
  });
  const rng = makeRng(0x61f7);
  const count = Math.floor(1500 * complexity);
  const side = Math.ceil(Math.sqrt(count));
  const meshes = [];
  const bundleGroup = createBundleGroup(BundleGroup);
  const meshParent = bundleGroup || bundle.scene;
  if (bundleGroup) bundle.scene.add(bundleGroup);

  for (let i = 0; i < count; i += 1) {
    const mesh = new THREE.Mesh(geometry, materials[i % materials.length]);
    const x = (i % side - side / 2) * 1.45;
    const z = (Math.floor(i / side) - side / 2) * 1.45;
    mesh.position.set(x, (rng() - 0.5) * 8, z);
    mesh.rotation.set(rng() * Math.PI, rng() * Math.PI, rng() * Math.PI);
    mesh.scale.setScalar(0.55 + rng() * 0.7);
    meshParent.add(mesh);
    meshes.push(mesh);
  }

  bundle.stats.drawCalls = count;
  bundle.stats.triangles = count * (geometry.index ? geometry.index.count / 3 : geometry.attributes.position.count / 3);
  bundle.stats.bufferUploadBytes = Object.values(geometry.attributes)
    .reduce((total, attribute) => total + attribute.array.byteLength, 0) +
    (geometry.index ? geometry.index.array.byteLength : 0);
  bundle.stats.notes.push('Loads bundled glTF through GLTFLoader, then expands it into many Mesh nodes sharing the loaded geometry.');
  recordBundleGroupUse(
    bundle,
    bundleGroup ? 1 : 0,
    'WebGPU static BundleGroup wraps the expanded glTF mesh set so WebGPURenderer can record render bundles.',
  );
  bundle.update = (time) => {
    cameraOrbit(bundle.camera, time, 66, 28, 0.14);
    for (let i = 0; i < meshes.length; i += 23) {
      meshes[i].rotation.y += 0.012;
      meshes[i].rotation.z += 0.007;
    }
  };
  return bundle;
}

export async function createBenchmarkScene({
  THREE,
  rendererType,
  sceneName,
  complexity,
  textureUploadMode,
  webgpuBundleMode = 'off',
}) {
  const requestedBundleMode = webgpuBundleMode === 'static' ? 'static' : 'off';
  const BundleGroup = await loadBundleGroupClass(rendererType, requestedBundleMode);
  let bundle;
  switch (sceneName) {
    case 'many-draw-calls':
      bundle = createManyDrawCalls({ THREE, complexity, BundleGroup });
      break;
    case 'instancing':
      bundle = createInstancing({ THREE, complexity });
      break;
    case 'shader-heavy':
      bundle = await createShaderHeavy({ THREE, rendererType, complexity });
      break;
    case 'texture-streaming':
      bundle = await createTextureStreaming({ THREE, complexity, textureUploadMode, BundleGroup });
      break;
    case 'postprocessing':
      bundle = createPostprocessing({ THREE, rendererType, complexity });
      break;
    case 'large-static':
      bundle = createLargeStatic({ THREE, complexity });
      break;
    case 'gltf-loader-stress':
      bundle = await createGltfLoaderStress({ THREE, rendererType, complexity, BundleGroup });
      break;
    default:
      throw new Error(`Unknown scene: ${sceneName}`);
  }
  return finalizeBundleMode(bundle, rendererType, requestedBundleMode);
}
