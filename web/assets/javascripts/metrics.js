class MetricsChart {
  constructor(id, options) {
    this.ctx = document.getElementById(id);
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

    const datasets = Object.entries(this.series)
      .filter(([kls, _]) => options.visible.includes(kls))
      .map(([kls, _]) => this.dataset(kls));

    this.chart = new Chart(this.ctx, {
      type: "line",
      data: { labels: this.labels, datasets: datasets },
      options: this.chartOptions,
    });

    this.update();
  }

  registerSwatch(id) {
    const el = document.getElementById(id);
    el.onchange = () => this.toggle(el.value, el.checked);
    this.swatches[el.value] = el;
    this.updateSwatch(el.value);
  }

  updateSwatch(kls) {
    const el = this.swatches[kls];
    const ds = this.chart.data.datasets.find((ds) => ds.label == kls);
    el.checked = !!ds;
    el.style.color = ds ? ds.borderColor : null;
  }

  toggle(kls, visible) {
    if (visible) {
      this.chart.data.datasets.push(this.dataset(kls));
    } else {
      const i = this.chart.data.datasets.findIndex((ds) => ds.label == kls);
      this.colors.unshift(this.chart.data.datasets[i].borderColor);
      this.chart.data.datasets.splice(i, 1);
    }

    this.updateSwatch(kls);
    this.update();
  }

  update() {
    // We want the deploy annotations to reach the top of the y-axis, but we don't want them
    // to prevent the y-axis from adjusting when datasets change. The only way I've found to do
    // this is removing them and re-adding them.
    this.removeMarksFromChart();
    this.chart.update();
    this.addMarksToChart();
    this.chart.update();
  }

  dataset(kls) {
    const color = this.colors.shift() || this.fallbackColor;

    return {
      label: kls,
      data: this.series[kls],
      borderColor: color,
      backgroundColor: color,
      borderWidth: 2,
      pointRadius: 2,
    };
  }

  removeMarksFromChart() {
    for (const key in this.chart.options.plugins.annotation.annotations) {
      delete this.chart.options.plugins.annotation.annotations[key];
    }
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
      this.chart.options.plugins.annotation.annotations[`label-${i}`] = {
        type: "label",
        position: { x: "center", y: "start" },
        xValue: bucket,
        // There may be a better way to ensure this annotation is positioned at the top of the y-axis.
        // This approach requires us to hide and re-show the annotations whenever the datasets change.
        yValue: (ctx) => ctx.chart && ctx.chart.scales.y.end,
        backgroundColor: "#f3f3f3",
        color: "rgba(220, 38, 38, 0.9)",
        padding: 2,
        content: [label.split(" ")[0]],
        font: {
          size: 14,
          family: "monospace",
        },
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
