class JobMetricsOverviewChart extends BaseChart {
  constructor(el, options) {
    super(el, { ...options, chartType: "line" });
    this.swatches = [];
    this.visibleKls = options.visibleKls;

    this.init();
  }

  get datasets() {
    return Object.entries(this.options.series)
      .filter(([kls, _]) => this.visibleKls.includes(kls))
      .map(([kls, _]) => this.buildDataset(kls));
  }

  get metric() {
    return this._metric || this.options.initialMetric;
  }

  set metric(m) {
    this._metric = m;
  }

  registerSwatch(id) {
    const el = document.getElementById(id);
    el.addEventListener("change", () => this.toggleKls(el.value, el.checked));
    this.swatches[el.value] = el;
    this.updateSwatch(el.value, el.checked);
  }

  updateSwatch(kls, checked) {
    const el = this.swatches[kls];
    el.checked = checked;
    el.style.accentColor = this.colors.assignments[kls] || "";
  }

  toggleKls(kls, visible) {
    if (visible) {
      this.chart.data.datasets.push(this.buildDataset(kls));
    } else {
      const i = this.chart.data.datasets.findIndex((ds) => ds.label == kls);
      this.colors.checkIn(kls);
      this.chart.data.datasets.splice(i, 1);
    }

    this.updateSwatch(kls, visible);
    this.update();
  }

  buildDataset(kls) {
    const color = this.colors.checkOut(kls);

    return {
      label: kls,
      data: this.dataFromSeries(this.options.series[kls]),
      borderColor: color,
      backgroundColor: color,
      borderWidth: 2,
      pointRadius: 2,
    };
  }

  dataFromSeries(series) {
    // Chart.js expects `data` to be an array of objects with `x` and `y` values.
    return Object.entries(series).map(([isoTime, val]) => ({ x: isoTime, y: val }));
  }

  get chartOptions() {
    return {
      ...super.chartOptions,
      aspectRatio: 4,
      scales: {
        ...super.chartOptions.scales,
        x: {
          ...super.chartOptions.scales.x,
          type: "time",
          min: this.options.starts_at,
          max: this.options.ends_at,
        },
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
            label: (item) =>
              `${item.dataset.label}: ${item.parsed.y.toFixed(1)} ` +
              `${this.options.units}`,
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
    const maxRadius = this.el.offsetWidth / 100;
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
          type: "time",
          min: this.options.starts_at,
          max: this.options.ends_at,
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

var ch = document.getElementById("job-metrics-overview-chart");
if (ch != null) {
  var jm = new JobMetricsOverviewChart(ch, JSON.parse(ch.textContent));
  document.querySelectorAll(".metrics-swatch-wrapper > input[type=checkbox]").forEach((imp) => {
    jm.registerSwatch(imp.id)
  });
  window.jobMetricsChart = jm;
}

var htc = document.getElementById("hist-totals-chart");
if (htc != null) {
  var tc = new HistTotalsChart(htc, JSON.parse(htc.textContent));
  window.histTotalsChart = tc
}

var hbc = document.getElementById("hist-bubble-chart");
if (hbc != null) {
  var bc = new HistBubbleChart(hbc, JSON.parse(hbc.textContent));
  window.histBubbleChart = bc
}

var form = document.getElementById("metrics-form")
document.querySelectorAll("#period-selector").forEach(node => {
  node.addEventListener("input", debounce(() => form.submit()))
})

function debounce(func, timeout = 300) {
  let timer;
  return (...args) => {
    clearTimeout(timer);
    timer = setTimeout(() => { func.apply(this, args); }, timeout);
  };
}