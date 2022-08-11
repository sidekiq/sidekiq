class MetricsChart {
  constructor(id, options) {
    this.ctx = document.getElementById(id);
    this.series = options.series;
    this.labels = options.labels;
    this.swatches = [];
    this.fallbackColor = "#999"
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

    const datasets = Object.entries(this.series)
      .filter(([kls, _]) => options.visible.includes(kls))
      .map(([kls, _]) => this.dataset(kls));

    this.chart = new Chart(this.ctx, {
      type: "line",
      data: { labels: this.labels, datasets: datasets },
      options: this.chartOptions,
    });
  }

  registerSwatch(id) {
    const el = document.getElementById(id);
    el.onchange = () => this.toggle(el.value, el.checked);
    this.swatches[el.value] = el
    this.updateSwatch(el.value)
  }

  updateSwatch(kls) {
    const el = this.swatches[kls];
    const ds = this.chart.data.datasets.find((ds) => ds.label == kls);
    el.checked = !!ds
    el.style.color = ds ? ds.borderColor : null
  }

  toggle(kls, visible) {
    if (visible) {
      this.chart.data.datasets.push(this.dataset(kls));
    } else {
      const i = this.chart.data.datasets.findIndex((ds) => ds.label == kls);
      this.colors.unshift(this.chart.data.datasets[i].borderColor)
      this.chart.data.datasets.splice(i, 1);
    }

    this.updateSwatch(kls);
    this.chart.update();
  }

  dataset(kls) {
    const color = this.colors.shift() || this.fallbackColor

    return {
      label: kls,
      data: this.series[kls],
      borderColor: color,
      backgroundColor: color,
      borderWidth: 2,
      pointRadius: 2,
    };
  }

  get chartOptions() {
    return {
      aspectRatio: 4,
      scales: {
        y: {
          beginAtZero: true,
        },
      },
      interaction: {
        mode: "x",
      },
      plugins: {
        legend: {
          display: false,
        },
      },
    };
  }
}
