if (window.matchMedia("(prefers-color-scheme: dark)").matches) {
  Chart.defaults.borderColor = "oklch(25% 0.01 269)";
  Chart.defaults.color = "oklch(71% 0.01 269)";
}

class Colors {
  constructor() {
    this.assignments = {};
    if (window.matchMedia("(prefers-color-scheme: dark)").matches) {
      this.light = "75%";
      this.chroma = "0.1";
    } else {
      this.light = "50%";
      this.chroma = "0.2";
    }
    this.success = "oklch(" + this.light + " " + this.chroma + " 179)";
    this.failure = "oklch(" + this.light + " " + this.chroma + " 29)";
    this.fallback = "oklch(" + this.light + " 0.02 269)";
    this.primary = "oklch(" + this.light + " " + this.chroma + " 269)";
    this.available = [
      "oklch(" + this.light + " " + this.chroma + " 269)",
      "oklch(" + this.light + " " + this.chroma + " 209)",
      "oklch(" + this.light + " " + this.chroma + " 59)",
      "oklch(" + this.light + " " + this.chroma + " 329)",
      "oklch(" + this.light + " " + this.chroma + " 119)",
      "oklch(" + this.light + " " + this.chroma + " 239)",
      "oklch(" + this.light + " " + this.chroma + " 149)",
      "oklch(" + this.light + " 0.02 269)",
      "oklch(" + this.light + " " + this.chroma + " 299)",
      "oklch(" + this.light + " " + this.chroma + " 29)",
    ];
  }

  checkOut(assignee) {
    const color =
      this.assignments[assignee] || this.available.shift() || this.fallback;
    this.assignments[assignee] = color;
    return color;
  }

  checkIn(assignee) {
    const color = this.assignments[assignee];
    delete this.assignments[assignee];

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
  }

  init() {
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
    let chartOptions = {
      interaction: {
        mode: "nearest",
        axis: "x",
        intersect: false,
      },
      scales: {
        x: {
          ticks: {
            autoSkipPadding: 10,
          },
        },
      },
      plugins: {
        legend: {
          display: false,
        },
        annotation: {
          annotations: {},
        },
        tooltip: {
          animation: false,
        },
      },
    };

    if (this.options.marks) {
      this.options.marks.forEach(([bucket, label], i) => {
        chartOptions.plugins.annotation.annotations[`deploy-${i}`] = {
          type: "line",
          xMin: bucket,
          xMax: bucket,
          borderColor: "oklch(95% 0.006 269)",
          borderWidth: 2,
        };
      });
    }

    return chartOptions;
  }
}
