if (window.matchMedia("(prefers-color-scheme: dark)").matches) {
  Chart.defaults.borderColor = "#333";
  Chart.defaults.color = "#aaa";
}

class Colors {
  constructor() {
    this.assigments = {};
    this.success = "#006f68";
    this.failure = "#af0014";
    this.fallback = "#999";
    this.primary = "#537bc4";
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
  constructor(el, options) {
    this.el = el;
    this.options = options;
    this.colors = new Colors();

    this.chart = new Chart(this.el, {
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
      plugins: this.plugins,
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
