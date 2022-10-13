class JobMetricsOverviewChart extends BaseChart {
  POLL_DELAY = 60000;
  CHART_LIMIT = 5;

  constructor(chartId, tableBodyId, options) {
    super(document.getElementById(chartId), { ...options, chartType: "line" });
    this.tableBodyId = tableBodyId;

    this.updateUrl = "/sidekiq/metrics.json";

    this.jobClassMetadata = {};
    this.startPolling();
  }

  async startPolling() {
    await this.poll();
    this._interval = setInterval(this.poll.bind(this), this.POLL_DELAY);
  }

  async poll() {
    const data = await this.fetchStats();
    this.options = {
      ...this.options,
      ...data
    };

    this.jobClasses.forEach((jobClass) => {
      if (!this.jobClassMetadata[jobClass]) {
        this.jobClassMetadata[jobClass] = {
          checked: this.checkedJobClasses.length < this.CHART_LIMIT,
        };
      }
    })

    if (!this.chart) {
      this.init();
    }

    this.update();

    document.getElementById('serverUtcTime').innerText = data.server_utc_time;
    document.getElementById('metrics-data-from').innerText = data.data_from;
  }

  async fetchStats() {
    const response = await fetch(this.updateUrl);
    return await response.json();
  }

  // Return the datasets that are checked in the table
  // and should be included in the chart.
  get datasets() {

    return Object.entries(this.options.series || {})
      .filter(([jobClass, _]) => this.checkedJobClasses.includes(jobClass))
      .map(([jobClass, _]) => this.buildDataset(jobClass));
  }

  get metric() {
    return this._metric || this.options.initialMetric;
  }

  set metric(m) {
    this._metric = m;
  }

  get jobClasses() {
    return Object.keys(this.options.tableData || {});
  }

  get checkedJobClasses() {
    return this.jobClasses.filter((jobClass) => this.jobClassMetadata[jobClass]?.checked);
  }

  // Setup eventListener for table checkbox and
  // assign a color.
  registerSwatch(element) {
    element.addEventListener(
      "change",
      (event) => {
        const element = event.target;
        this.toggleClass(element.value, element.checked);
      }
    )
    const jobClass = element.value;
    element.style.color = this.colors.assignments[jobClass] || "";
  }

  // Toggle the jobClass and add / remove it from the chart.
  toggleClass(jobClass, checked) {
    if (checked) {
      this.chart.data.datasets.push(this.buildDataset(jobClass));
    } else {
      const i = this.chart.data.datasets.findIndex((ds) => ds.label == jobClass);
      this.colors.checkIn(jobClass);
      this.chart.data.datasets.splice(i, 1);
    }

    const metadata = this.jobClassMetadata[jobClass] || {};
    metadata.checked = checked;
    metadata.color = this.colors.assignments[jobClass] || "";
    this.jobClassMetadata[jobClass] = metadata;
    this.update();
  }

  buildDataset(jobClass) {
    const color = this.colors.checkOut(jobClass);

    return {
      label: jobClass,
      data: this.options.series[jobClass],
      borderColor: color,
      backgroundColor: color,
      borderWidth: 2,
      pointRadius: 2,
    };
  }

  update() {
    this.chart.data = {labels: this.options.labels, datasets: this.datasets };
    this.chart.update('none');
    this.updateTableBody();
  }

  updateTableBody() {
    let rows = "";
    if (this.jobClasses.length > 0) {
      this.jobClasses.forEach((jobClass) => {
        const metadata = this.jobClassMetadata[jobClass] || {};
        const result = this.options.tableData[jobClass];
        rows += `
          <tr>
            <td>
              <div class="metrics-swatch-wrapper">
                <input
                  type="checkbox"
                  id="metrics-swatch-${jobClass}"
                  class="metrics-swatch"
                  value="${jobClass}"
                  ${metadata.checked ? 'checked' : ''}
                  style="color: ${metadata.color}"
                />
                <code>
                  <a href="/sidekiq/metrics/${jobClass}">
                    ${jobClass}
                  </a>
                </code>
              </div>
            </td>
            <td>${result["success"]}</td>
            <td>${result["failure"]}</td>
            <td>${result["total"]} ${this.options.units}</td>
            <td>${result["average"]} ${this.options.units}</td>
          </tr>
        `;
      });
    } else {
      rows = `<tr><td colspan='5'>${this.options.noDataFound}</td></tr>`
    }

    const table = document.getElementById(this.tableBodyId)
    if (table) {
      table.innerHTML = rows;
      table.querySelectorAll(".metrics-swatch").forEach((el) => {
        this.registerSwatch(el);
      });
    }
  }

  get chartOptions() {
    return {
      ...super.chartOptions,
      aspectRatio: 4,
      scales: {
        ...super.chartOptions.scales,
        y: {
          ...super.chartOptions.scales.y,
          beginAtZero: true,
          title: {
            text: this.options.yLabel,
            display: true,
          },
        },
      },
      plugins: {
        ...super.chartOptions.plugins,
        tooltip: {
          ...super.chartOptions.plugins.tooltip,
          callbacks: {
            title: (items) => `${items[0].label} UTC`,
            label: (item) =>
              `${item.dataset.label}: ${item.parsed.y.toFixed(1)} ` +
              `${this.options.units}`,
            footer: (items) => {
              const bucket = items[0].label;
              const marks = this.options.marks.filter(([b, _]) => b == bucket);
              return marks.map(
                ([b, msg]) => `${this.options.markLabel}: ${msg}`
              );
            },
          },
        },
      },
    };
  }
}

class HistTotalsChart extends BaseChart {
  constructor(el, options) {
    super(el, { ...options, chartType: "bar" });
    this.init();
  }

  get datasets() {
    return [
      {
        data: this.options.series,
        backgroundColor: this.colors.primary,
        borderWidth: 0,
      },
    ];
  }

  get chartOptions() {
    return {
      ...super.chartOptions,
      aspectRatio: 6,
      scales: {
        ...super.chartOptions.scales,
        y: {
          ...super.chartOptions.scales.y,
          beginAtZero: true,
          title: {
            text: this.options.yLabel,
            display: true,
          },
        },
        x: {
          ...super.chartOptions.scales.x,
          title: {
            text: this.options.xLabel,
            display: true,
          },
        },
      },
      plugins: {
        ...super.chartOptions.plugins,
        tooltip: {
          ...super.chartOptions.plugins.tooltip,
          callbacks: {
            label: (item) => `${item.parsed.y} ${this.options.units}`,
          },
        },
      },
    };
  }
}

class HistBubbleChart extends BaseChart {
  constructor(el, options) {
    super(el, { ...options, chartType: "bubble" });
    this.init();
  }

  get datasets() {
    const data = [];
    let maxCount = 0;

    Object.entries(this.options.hist).forEach(([bucket, hist]) => {
      hist.forEach((count, histBucket) => {
        if (count > 0) {
          // histogram data is ordered fastest to slowest, but this.histIntervals is
          // slowest to fastest (so it displays correctly on the chart).
          const index = this.options.histIntervals.length - 1 - histBucket;

          data.push({
            x: bucket,
            y: this.options.histIntervals[index] / 1000,
            count: count,
          });

          if (count > maxCount) maxCount = count;
        }
      });
    });

    // Chart.js will not calculate the bubble size. We have to do that.
    const maxRadius = this.el.offsetWidth / this.options.labels.length;
    const minRadius = 1;
    const multiplier = (maxRadius / maxCount) * 1.5;
    data.forEach((entry) => {
      entry.r = entry.count * multiplier + minRadius;
    });

    return [
      {
        data: data,
        backgroundColor: this.colors.primary,
        borderColor: this.colors.primary,
      },
    ];
  }

  get chartOptions() {
    return {
      ...super.chartOptions,
      aspectRatio: 3,
      scales: {
        ...super.chartOptions.scales,
        x: {
          ...super.chartOptions.scales.x,
          type: "category",
          labels: this.options.labels,
        },
        y: {
          ...super.chartOptions.scales.y,
          title: {
            text: this.options.yLabel,
            display: true,
          },
        },
      },
      plugins: {
        ...super.chartOptions.plugins,
        tooltip: {
          ...super.chartOptions.plugins.tooltip,
          callbacks: {
            title: (items) => `${items[0].raw.x} UTC`,
            label: (item) =>
              `${item.parsed.y} ${this.options.yUnits}: ${item.raw.count} ${this.options.zUnits}`,
            footer: (items) => {
              const bucket = items[0].raw.x;
              const marks = this.options.marks.filter(([b, _]) => b == bucket);
              return marks.map(
                ([b, msg]) => `${this.options.markLabel}: ${msg}`
              );
            },
          },
        },
      },
    };
  }
}
