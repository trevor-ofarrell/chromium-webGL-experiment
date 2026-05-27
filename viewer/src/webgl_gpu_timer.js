export class WebGlGpuTimer {
  constructor(gl) {
    this.gl = gl;
    this.ext = gl.getExtension('EXT_disjoint_timer_query_webgl2');
    this.pending = [];
    this.active = null;
    this.errorCount = 0;
    this.lastError = null;
  }

  begin() {
    if (!this.ext || this.active) return;
    const query = this.gl.createQuery();
    this.gl.beginQuery(this.ext.TIME_ELAPSED_EXT, query);
    this.active = query;
  }

  end() {
    if (!this.ext || !this.active) return;
    this.gl.endQuery(this.ext.TIME_ELAPSED_EXT);
    this.pending.push(this.active);
    this.active = null;
  }

  poll() {
    if (!this.ext) return [];
    const samples = [];
    const remaining = [];
    const disjoint = this.gl.getParameter(this.ext.GPU_DISJOINT_EXT);

    for (const query of this.pending) {
      const available = this.gl.getQueryParameter(query, this.gl.QUERY_RESULT_AVAILABLE);
      if (!available) {
        remaining.push(query);
        continue;
      }

      if (!disjoint) {
        const nanoseconds = this.gl.getQueryParameter(query, this.gl.QUERY_RESULT);
        samples.push(nanoseconds / 1_000_000);
      }
      this.gl.deleteQuery(query);
    }

    this.pending = remaining;
    return samples;
  }

  metadata() {
    return {
      gpu_timer_type: 'webgl_timer_query',
      gpu_timer_available: Boolean(this.ext),
      gpu_timer_unavailable_reason: this.ext ? null : 'EXT_disjoint_timer_query_webgl2 unavailable',
      gpu_timer_error_count: this.errorCount,
      last_gpu_timer_error: this.lastError,
    };
  }
}
