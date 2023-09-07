class DashboardChart extends BaseChart {
  constructor(el, options) {
    super(el, { ...options, chartType: "line" });
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
        ...super.chartOptions.scales,
        x: {
          ...super.chartOptions.scales.x,
          ticks: {
            ...super.chartOptions.scales.x.ticks,
            callback: function (value, index, ticks) {
              // Remove the year from the date string
              return this.getLabelForValue(value).split("-").slice(1).join("-");
            },
          },
        },
        y: {
          ...super.chartOptions.scales.y,
          beginAtZero: true,
        },
      },
    };
  }
}

class RealtimeChart extends DashboardChart {
  constructor(el, options) {
    super(el, options);
    let d = parseInt(localStorage.sidekiqTimeInterval) || 5000;
    if (d < 2000) { d = 2000; }
    this.delay = d
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

  registerLegend(el) {
    this.legend = el;
  }

  renderLegend(dp) {
    this.legend.innerHTML = `
      <span>
        <span class="swatch" style="background-color: ${dp[0].dataset.borderColor};"></span>
        <span>${dp[0].dataset.label}: ${dp[0].formattedValue}</span>
      </span>
      <span>
        <span class="swatch" style="background-color: ${dp[1].dataset.borderColor};"></span>
        <span>${dp[1].dataset.label}: ${dp[1].formattedValue}</span>
      </span>
      <span class="time">${dp[0].label}</span>
    `;
  }

  renderCursor(dp) {
    if (this.cursorX != dp[0].label) {
      this.cursorX = dp[0].label;
      this.update()
    }
  }

  get chartOptions() {
    return {
      ...super.chartOptions,
      scales: {
        ...super.chartOptions.scales,
        x: {
          ...super.chartOptions.scales.x,
          display: false,
        },
      },
      plugins: {
        ...super.chartOptions.plugins,
        tooltip: {
          ...super.chartOptions.plugins.tooltip,
          enabled: false,
          external: (context) => {
            const dp = context.tooltip.dataPoints;
            if (dp && dp.length == 2 && this.legend) {
              this.renderLegend(dp);
              this.renderCursor(dp);
            }
          },
        },
        annotation: {
          annotations: {
            ...super.chartOptions.plugins.annotation.annotations,
            cursor: this.cursorX && {
              type: "line",
              borderColor: "rgba(0, 0, 0, 0.3)",
              xMin: this.cursorX,
              xMax: this.cursorX,
              borderWidth: 1,
            },
          },
        },
      },
    };
  }
}
