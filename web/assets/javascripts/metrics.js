function init() {
  const ctx = document.getElementById("metrics-chart");
  const colors = JSON.parse(ctx.getAttribute("data-colors"));
  const labels = JSON.parse(ctx.getAttribute("data-labels"));
  const datasets = Object.entries(
    JSON.parse(ctx.getAttribute("data-series"))
  ).map(([k, v], i) => {
    return {
      label: k,
      data: v,
      borderColor: colors[i],
      backgroundColor: colors[i],
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
    },
    plugins: {
      legend: {
        display: false,
      },
    },
  };

  const chart = new Chart(ctx, {
    type: "line",
    data: { labels: labels, datasets: datasets },
    options: options,
  });
}

document.addEventListener("DOMContentLoaded", init);
