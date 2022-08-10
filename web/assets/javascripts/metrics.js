// Colors taken from https://www.chartjs.org/docs/latest/samples/utils.html
const COLORS = [
  "#4dc9f6",
  "#f67019",
  "#f53794",
  "#537bc4",
  "#acc236",
  "#166a8f",
  "#00a950",
  "#58595b",
  "#8549ba",
];

function init() {
  const ctx = document.getElementById("metrics-chart");
  const labels = JSON.parse(ctx.getAttribute("data-labels"));
  const datasets = Object.entries(
    JSON.parse(ctx.getAttribute("data-series"))
  ).map(([k, v], i) => {
    return {
      label: k,
      data: v,
      borderColor: COLORS[i],
      backgroundColor: COLORS[i],
      borderWidth: 2,
      pointRadius: 2,
    };
  });
  const options = {
    aspectRatio: 4,
    scales: {
      y: {
        beginAtZero: true,
      },
    },
    interaction: {
      mode: "x",
    }
  };

  const chart = new Chart(ctx, {
    type: "line",
    data: { labels: labels, datasets: datasets },
    options: options,
  });
}

document.addEventListener("DOMContentLoaded", init);
