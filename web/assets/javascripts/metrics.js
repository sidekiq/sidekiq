if (window.matchMedia("(prefers-color-scheme: dark)").matches) {
  Chart.defaults.borderColor = "#333";
  Chart.defaults.color = "#aaa";
}

class Colors {
  constructor() {
    this.assigments = {};
    this.fallback = "#999";
    this.available = [
      // Colors taken from https://www.chartjs.org/docs/latest/samples/utils.html
      "#537bc4",
      "#4dc9f6",
      "#f67019",
      "#f53794",
      "#acc236",
      "#166a8f",
      "#00a950",
      "#58595b",
      "#8549ba",
      "#991b1b",
    ];
    this.primary = this.available[0];
  }

  checkOutFor(assignee) {
    const color =
      this.assigments[assignee] || this.available.shift() || this.fallback;
    this.assigments[assignee] = color;
    return color;
  }

  checkInFor(assignee) {
    const color = this.assigments[assignee];
    delete this.assigments[assignee];

    if (color && color != this.fallback) {
      this.available.unshift(color);
    }
  }
}

class BaseChart {
  constructor(id, options) {
    this.ctx = document.getElementById(id);
    this.visibleKls = options.visible;
    this.options = options;
    this.colors = new Colors();

    this.chart = new Chart(this.ctx, {
      type: this.options.chartType,
      data: { labels: this.options.labels, datasets: this.datasets },
      options: this.chartOptions,
    });
  }

  update() {
    this.chart.options = this.chartOptions;
    this.chart.update();
  }

  get chartOptions() {
    return {
      interaction: {
        mode: "x",
      },
    };
  }

  get plugins() {
    const plugins = {
      legend: {
        display: false,
      },
      annotation: {
        annotations: {},
      },
    };

    if (this.options.marks) {
      this.options.marks.forEach(([bucket, label], i) => {
        plugins.annotation.annotations[`deploy-${i}`] = {
          type: "line",
          xMin: bucket,
          xMax: bucket,
          borderColor: "rgba(220, 38, 38, 0.4)",
          borderWidth: 2,
        };
      });
    }

    return plugins;
  }
}

class JobMetricsOverviewChart extends BaseChart {
  constructor(id, options) {
    super(id, { ...options, chartType: "line" });
    this.swatches = [];

    this.update();
  }

  get currentSeries() {
    return this.options.series[this.metric];
  }

  get datasets() {
    return Object.entries(this.currentSeries)
      .filter(([kls, _]) => this.visibleKls.includes(kls))
      .map(([kls, _]) => this.buildDataset(kls));
  }

  get metric() {
    return this._metric || this.options.initialMetric;
  }

  set metric(m) {
    this._metric = m;
  }

  selectMetric(metric) {
    this.metric = metric;
    for (const el of document.querySelectorAll("a[data-show-metric]")) {
      this.updateMetricSelector(el);
    }
    this.chart.data.datasets = this.datasets;
    this.update();
  }

  updateMetricSelector(el) {
    const isCurrent = el.getAttribute("data-show-metric") == this.metric;
    el.classList.toggle("current-chart", isCurrent);
  }

  registerMetricSelector(el) {
    this.updateMetricSelector(el);
    el.addEventListener("click", (e) => {
      e.preventDefault();
      this.selectMetric(e.target.getAttribute("data-show-metric"));
      this.sortTableBody(
        e.target.closest("table").querySelector("tbody"),
        [...e.target.closest("tr").children].indexOf(e.target.closest("th"))
      );
    });
  }

  registerSwatch(id) {
    const el = document.getElementById(id);
    el.addEventListener("change", () => this.toggleKls(el.value, el.checked));
    this.swatches[el.value] = el;
    this.updateSwatch(el.value);
  }

  updateSwatch(kls) {
    const el = this.swatches[kls];
    const ds = this.chart.data.datasets.find((ds) => ds.label == kls);
    el.checked = !!ds;
    el.style.color = ds ? ds.borderColor : null;
  }

  toggleKls(kls, visible) {
    if (visible) {
      this.chart.data.datasets.push(this.buildDataset(kls));
    } else {
      const i = this.chart.data.datasets.findIndex((ds) => ds.label == kls);
      this.colors.checkInFor(kls);
      this.chart.data.datasets.splice(i, 1);
    }

    this.updateSwatch(kls);
    this.update();
  }

  sortTableBody(tbody, colNo) {
    const [...rows] = tbody.querySelectorAll("tr");

    rows.sort((r1, r2) => {
      const val1 = parseFloat(r1.children[colNo].innerText);
      const val2 = parseFloat(r2.children[colNo].innerText);

      // Sorting highest to lowest
      return val2 - val1;
    });

    for (const row of rows) {
      tbody.append(row);
    }
  }

  buildDataset(kls) {
    const color = this.colors.checkOutFor(kls);

    return {
      label: kls,
      data: this.currentSeries[kls],
      borderColor: color,
      backgroundColor: color,
      borderWidth: 2,
      pointRadius: 2,
    };
  }

  get chartOptions() {
    return {
      ...super.chartOptions,
      aspectRatio: 4,
      scales: {
        y: {
          beginAtZero: true,
          title: {
            text: this.options.metricLabels[this.metric],
            display: true,
          },
        },
      },
      plugins: {
        ...this.plugins,
        tooltip: {
          callbacks: {
            title: (items) => `${items[0].label} UTC`,
            label: (item) =>
              `${item.dataset.label}: ${item.parsed.y.toFixed(1)} ${
                this.options.metricUnits[this.metric]
              }`,
            footer: (items) => {
              const bucket = items[0].label;
              const marks = this.options.marks.filter(([b, _]) => b == bucket);
              return marks.map(([b, msg]) => `Deploy: ${msg}`);
            },
          },
        },
      },
    };
  }
}

class HistTotalsChart extends BaseChart {
  constructor(id, options) {
    super(id, { ...options, chartType: "bar" });
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
        y: {
          beginAtZero: true,
          title: {
            text: "Total jobs",
            display: true,
          },
        },
      },
      plugins: {
        ...this.plugins,
        tooltip: {
          callbacks: {
            label: (item) => `${item.parsed.y} jobs`,
          },
        },
      },
    };
  }
}

class HistBubbleChart extends BaseChart {
  constructor(id, options) {
    super(id, { ...options, chartType: "bubble" });

    this.update();
  }

  get datasets() {
    const data = [];
    let maxCount = 0;

    Object.entries(this.options.hist).forEach(([bucket, hist]) => {
      hist.forEach((count, histBucket) => {
        if (count > 0) {
          data.push({
            x: bucket,
            // histogram data is ordered fastest to slowest, but this.histIntervals is
            // slowest to fastest (so it displays correctly on the chart).
            y:
              this.options.histIntervals[
                this.options.histIntervals.length - 1 - histBucket
              ] / 1000,
            count: count,
          });

          if (count > maxCount) maxCount = count;
        }
      });
    });

    // Chart.js will not calculate the bubble size. We have to do that.
    const maxRadius = this.ctx.offsetWidth / this.options.labels.length;
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
        x: {
          type: "category",
          labels: this.options.labels,
        },
        y: {
          title: {
            text: "Execution time (sec)",
            display: true,
          },
        },
      },
      plugins: {
        ...this.plugins,
        tooltip: {
          callbacks: {
            title: (items) => `${items[0].raw.x} UTC`,
            label: (item) =>
              `${item.parsed.y} seconds: ${item.raw.count} job${
                item.raw.count == 1 ? "" : "s"
              }`,
            footer: (items) => {
              const bucket = items[0].raw.x;
              const marks = this.options.marks.filter(([b, _]) => b == bucket);
              return marks.map(([b, msg]) => `Deploy: ${msg}`);
            },
          },
        },
      },
    };
  }
}
