export class WebGpuGpuTimer {
  constructor(renderer) {
    this.renderer = renderer;
    this.samples = [];
    this.pending = null;
    this.errorCount = 0;
    this.lastError = null;

    if (typeof renderer?.resolveTimestampsAsync !== 'function') {
      this.available = false;
      this.unavailableReason = 'renderer.resolveTimestampsAsync unavailable';
    } else if (!renderer?.backend?.trackTimestamp) {
      this.available = false;
      this.unavailableReason = 'WebGPU timestamp-query feature unavailable';
    } else {
      this.available = true;
      this.unavailableReason = null;
    }
  }

  begin() {}

  end() {}

  poll() {
    const samples = this.samples.splice(0);
    this.scheduleResolve();
    return samples;
  }

  scheduleResolve() {
    if (!this.available || this.pending) return;

    this.pending = this.renderer.resolveTimestampsAsync('render')
      .then((duration) => {
        if (Number.isFinite(duration)) {
          this.samples.push(duration);
        }
      })
      .catch((error) => {
        this.errorCount += 1;
        this.lastError = error?.message || String(error);
      })
      .finally(() => {
        this.pending = null;
      });
  }

  metadata() {
    return {
      gpu_timer_type: 'webgpu_timestamp_query',
      gpu_timer_available: this.available,
      gpu_timer_unavailable_reason: this.unavailableReason,
      gpu_timer_error_count: this.errorCount,
      last_gpu_timer_error: this.lastError,
    };
  }
}
