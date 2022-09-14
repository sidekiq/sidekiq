Sidekiq = {};

var nf = new Intl.NumberFormat();

var updateStatsSummary = function(data) {
  document.getElementById("txtProcessed").innerText = nf.format(data.processed);
  document.getElementById("txtFailed").innerText = nf.format(data.failed);
  document.getElementById("txtBusy").innerText = nf.format(data.busy);
  document.getElementById("txtScheduled").innerText = nf.format(data.scheduled);
  document.getElementById("txtRetries").innerText = nf.format(data.retries);
  document.getElementById("txtEnqueued").innerText = nf.format(data.enqueued);
  document.getElementById("txtDead").innerText = nf.format(data.dead);
}

var updateRedisStats = function(data) {
  document.getElementById('redis_version').innerText = data.redis_version;
  document.getElementById('uptime_in_days').innerText = data.uptime_in_days;
  document.getElementById('connected_clients').innerText = data.connected_clients;
  document.getElementById('used_memory_human').innerText = data.used_memory_human;
  document.getElementById('used_memory_peak_human').innerText = data.used_memory_peak_human;
}

var updateFooterUTCTime = function(time) {
  document.getElementById('serverUtcTime').innerText = time;
}

var pulseBeacon = function() {
  document.getElementById('beacon').classList.add('pulse');
  window.setTimeout(() => { document.getElementById('beacon').classList.remove('pulse'); }, 1000);
}

var setSliderLabel = function(val) {
  document.getElementById('sldr-text').innerText = Math.round(parseFloat(val) / 1000) + ' sec';
}

var ready = (callback) => {
  if (document.readyState != "loading") callback();
  else document.addEventListener("DOMContentLoaded", callback);
}

ready(() => {
  var sldr = document.getElementById('sldr');
  if (typeof localStorage.sidekiqTimeInterval !== 'undefined') {
    sldr.value = localStorage.sidekiqTimeInterval;
    setSliderLabel(localStorage.sidekiqTimeInterval);
  }

  sldr.addEventListener("change", event => {
    localStorage.sidekiqTimeInterval = sldr.value;
    setSliderLabel(sldr.value);
    sldr.dispatchEvent(
      new CustomEvent("interval:update", { bubbles: true, detail: sldr.value })
    );
  });

  sldr.addEventListener("mousemove", event => {
    setSliderLabel(sldr.value);
  });
});
