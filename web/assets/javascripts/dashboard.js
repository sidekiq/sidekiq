Sidekiq = {};

var nf = new Intl.NumberFormat();

var updateStatsSummary = function(data) {
  document.getElementById("txtProcessed").innerText = nf.format(data.processed);
  document.getElementById("txtFailed").innerText = nf.format(data.failed);
  document.getElementById("txtBusy").innerText = nf.format(data.busy);
  document.getElementById("txtScheduled").innerText = nf.format(data.scheduled);
  document.getElementById("txtRetries").innerText = nf.format(data.retries);
  document.getElementById("txtEnqueued").innerText = nf.format(data.enqueued);
  document.getElementById("txtDead").innerText = nf.format(data.dead);
}

var updateRedisStats = function(data) {
  document.getElementById('redis_version').innerText = data.redis_version;
  document.getElementById('uptime_in_days').innerText = data.uptime_in_days;
  document.getElementById('connected_clients').innerText = data.connected_clients;
  document.getElementById('used_memory_human').innerText = data.used_memory_human;
  document.getElementById('used_memory_peak_human').innerText = data.used_memory_peak_human;
}

var updateFooterUTCTime = function(time) {
  document.getElementById('serverUtcTime').innerText = time;
}

var pulseBeacon = function() {
  document.getElementById('beacon').classList.add('pulse');
  window.setTimeout(() => { document.getElementById('beacon').classList.remove('pulse'); }, 1000);
}

var setSliderLabel = function(val) {
  document.getElementById('sldr-text').innerText = Math.round(parseFloat(val) / 1000) + ' sec';
}

var ready = (callback) => {
  if (document.readyState != "loading") callback();
  else document.addEventListener("DOMContentLoaded", callback);
}

ready(() => {
  var sldr = document.getElementById('sldr');
  if (typeof localStorage.sidekiqTimeInterval !== 'undefined') {
    sldr.value = localStorage.sidekiqTimeInterval;
    setSliderLabel(localStorage.sidekiqTimeInterval);
  }

  sldr.addEventListener("change", event => {
    localStorage.sidekiqTimeInterval = sldr.value;
    setSliderLabel(sldr.value);
    sldr.dispatchEvent(
      new CustomEvent("interval:update", { bubbles: true, detail: sldr.value })
    );
  });

  sldr.addEventListener("mousemove", event => {
    setSliderLabel(sldr.value);
  });
});

class DashboardChart extends BaseChart {
  constructor(id, options) {
    super(id, { ...options, chartType: "line" });
    this.init();
  }

  get data() {
    return [this.options.processed, this.options.failed];
  }

  get datasets() {
    return [
      {
        label: this.options.processedLabel,
        data: this.data[0],
        borderColor: this.colors.success,
        backgroundColor: this.colors.success,
        borderWidth: 2,
        pointRadius: 2,
      },
      {
        label: this.options.failedLabel,
        data: this.data[1],
        borderColor: this.colors.failure,
        backgroundColor: this.colors.failure,
        borderWidth: 2,
        pointRadius: 2,
      },
    ];
  }

  get chartOptions() {
    return {
      ...super.chartOptions,
      aspectRatio: 4,
      scales: {
        y: {
          beginAtZero: true,
        },
      },
    };
  }
}

class RealtimeChart extends DashboardChart {
  constructor(id, options) {
    super(id, options);
    this.delay = parseInt(localStorage.sidekiqTimeInterval) || 5000;
    this.startPolling();
    document.addEventListener("interval:update", this.handleUpdate.bind(this));
  }

  async startPolling() {
    // Fetch initial values so we can show diffs moving forward
    this.stats = await this.fetchStats();
    this._interval = setInterval(this.poll.bind(this), this.delay);
  }

  async poll() {
    const stats = await this.fetchStats();
    const processed = stats.sidekiq.processed - this.stats.sidekiq.processed;
    const failed = stats.sidekiq.failed - this.stats.sidekiq.failed;

    this.chart.data.labels.shift();
    this.chart.data.datasets[0].data.shift();
    this.chart.data.datasets[1].data.shift();
    this.chart.data.labels.push(new Date().toUTCString().split(" ")[4]);
    this.chart.data.datasets[0].data.push(processed);
    this.chart.data.datasets[1].data.push(failed);
    this.chart.update();

    updateStatsSummary(this.stats.sidekiq);
    updateRedisStats(this.stats.redis);
    updateFooterUTCTime(this.stats.server_utc_time);
    pulseBeacon();

    this.stats = stats;
  }

  async fetchStats() {
    const response = await fetch(this.options.updateUrl);
    return await response.json();
  }

  handleUpdate(e) {
    this.delay = parseInt(e.detail);
    clearInterval(this._interval);
    this.startPolling();
  }
}
