if (window.matchMedia("(prefers-color-scheme: dark)").matches) {
  Chart.defaults.borderColor = "oklch(28% 0.01 269)";
  Chart.defaults.color = "oklch(71% 0.01 269)";
}

class Colors {
  constructor() {
    this.assignments = {};
    this.success = "oklch(0.5 0.18 179)";
    this.failure = "oklch(0.5 0.18 29)";
    this.fallback = "oklch(0.5 0.02 269)";
    this.primary = "oklch(0.5 0.18 269)";
    this.available = [
      "oklch(0.5 0.18 269)",
      "oklch(0.5 0.18 209)",
      "#oklch(0.5 0.18 59)",
      "oklch(0.5 0.18 329)",
      "oklch(0.5 0.18 119)",
      "oklch(0.5 0.18 239)",
      "oklch(0.5 0.18 149)",
      "oklch(50% 0.02 269)",
      "oklch(0.5 0.18 299)",
      "oklch(0.5 0.18 29)",
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
          borderColor: "oklch(91% 0.002 269)",
          borderWidth: 2,
        };
      });
    }

    return chartOptions;
  }
}
