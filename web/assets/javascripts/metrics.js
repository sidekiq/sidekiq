class MetricsChart {
  constructor(id, options) {
    this.ctx = document.getElementById(id);
    this.metric = "s";
    this.visibleKls = options.visible;
    this.series = options.series;
    this.marks = options.marks;
    this.labels = options.labels;
    this.swatches = [];
    this.fallbackColor = "#999";
    this.colors = [
      // Colors taken from https://www.chartjs.org/docs/latest/samples/utils.html
      "#4dc9f6",
      "#f67019",
      "#f53794",
      "#537bc4",
      "#acc236",
      "#166a8f",
      "#00a950",
      "#58595b",
      "#8549ba",
      "#991b1b",
    ];

    this.chart = new Chart(this.ctx, {
      type: "line",
      data: { labels: this.labels, datasets: this.datasets },
      options: this.chartOptions,
    });

    this.addMarksToChart();
    this.chart.update();
  }

  get currentSeries() {
    return this.series[this.metric];
  }

  get datasets() {
    return Object.entries(this.currentSeries)
      .filter(([kls, _]) => this.visibleKls.includes(kls))
      .map(([kls, _]) => this.dataset(kls));
  }

  selectMetric(e) {
    e.preventDefault()
    this.metric = e.target.getAttribute("data-show-metric")
    // TODO: maintain current visible job classes and colors
    this.chart.data.datasets = this.datasets;
    this.chart.update();

    // TODO: sort the table by the new metric
  }

  registerMetricSelector(el) {
    el.addEventListener('click', this.selectMetric.bind(this));
  }

  registerSwatch(id) {
    const el = document.getElementById(id);
    el.addEventListener('change', () => this.toggleKls(el.value, el.checked));
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
      this.chart.data.datasets.push(this.dataset(kls));
    } else {
      const i = this.chart.data.datasets.findIndex((ds) => ds.label == kls);
      this.colors.unshift(this.chart.data.datasets[i].borderColor);
      this.chart.data.datasets.splice(i, 1);
    }

    this.updateSwatch(kls);
    this.chart.update();
  }

  dataset(kls) {
    const color = this.colors.shift() || this.fallbackColor;

    return {
      label: kls,
      data: this.currentSeries[kls],
      borderColor: color,
      backgroundColor: color,
      borderWidth: 2,
      pointRadius: 2,
    };
  }

  addMarksToChart() {
    this.marks.forEach(([bucket, label], i) => {
      this.chart.options.plugins.annotation.annotations[`deploy-${i}`] = {
        type: "line",
        xMin: bucket,
        xMax: bucket,
        borderColor: "rgba(220, 38, 38, 0.4)",
        borderWidth: 2,
      };
    });
  }

  get chartOptions() {
    return {
      aspectRatio: 4,
      scales: {
        y: {
          beginAtZero: true,
          title: {
            text: "Total execution time (sec)",
            display: true,
          },
        },
      },
      interaction: {
        mode: "x",
      },
      plugins: {
        legend: {
          display: false,
        },
        tooltip: {
          callbacks: {
            title: (items) => `${items[0].label} UTC`,
            label: (item) =>
              `${item.dataset.label}: ${item.parsed.y.toFixed(1)} seconds`,
            footer: (items) => {
              const bucket = items[0].label;
              const marks = this.marks.filter(([b, _]) => b == bucket);
              return marks.map(([b, msg]) => `Deploy: ${msg}`);
            },
          },
        },
      },
    };
  }
}
