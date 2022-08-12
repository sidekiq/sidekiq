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

    this.addMarksToChart();
    this.chart.update();
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

class HistBubbleChart {
  constructor(id, options) {
    this.ctx = document.getElementById(id);
    this.hist = options.hist;
    this.marks = options.marks;
    this.labels = options.labels;
    this.histBuckets = options.histBuckets;
    console.log(this.histBuckets);
    console.log(this.dataset);

    this.chart = new Chart(this.ctx, {
      type: "bubble",
      data: { datasets: [this.dataset] },
      options: this.chartOptions,
    });

    this.addMarksToChart();
    this.chart.update();
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

  get dataset() {
    const data = [];
    let maxCount = 0;

    Object.entries(this.hist).forEach(([bucket, hist]) => {
      hist.forEach((count, histBucket) => {
        if (count > 0) {
          data.push({
            x: bucket,
            // histogram data is ordered fastest to slowest, but this.histBuckets is
            // slowest to fastest (so it displays correctly on the chart).
            y: this.histBuckets[this.histBuckets.length - 1 - histBucket],
            // TODO: scale this based on the largest overall count
            count: count,
          });

          if (count > maxCount) maxCount = count
        }
      });
    });

    // Chart.js will not calculate the bubble size. We have to do that.
    const maxRadius = this.ctx.offsetWidth / this.labels.length
    const multiplier = maxRadius / maxCount * 1.5
    data.forEach((entry) => {
      entry.r = entry.count * multiplier
    })

    return {
      data: data,
      backgroundColor: "#537bc4",
      borderColor: "#537bc4",
    };
  }

  get chartOptions() {
    return {
      aspectRatio: 3,
      scales: {
        x: {
          type: "category",
          labels: this.labels,
        },
        y: {
          type: "category",
          labels: this.histBuckets,
          // title: {
          //   text: "Total execution time (sec)",
          //   display: true,
          // },
        },
      },
      interaction: {
        mode: "x",
      },
      plugins: {
        legend: {
          display: false,
        },
        // tooltip: {
        //   callbacks: {
        //     title: (items) => `${items[0].label} UTC`,
        //     label: (item) =>
        //       `${item.dataset.label}: ${item.parsed.y.toFixed(1)} seconds`,
        //     footer: (items) => {
        //       const bucket = items[0].label;
        //       const marks = this.marks.filter(([b, _]) => b == bucket);
        //       return marks.map(([b, msg]) => `Deploy: ${msg}`);
        //     },
        //   },
        // },
      },
    };
  }
}
