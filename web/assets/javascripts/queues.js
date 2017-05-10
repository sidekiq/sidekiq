var getQueueSizes = function() {
  return $('table.queues tbody tr').map(function(index, item) {
    return parseInt(item.cells[1].innerHTML.match(/[0-9,]+/, '')[0].replace(',', ''), 10);
  });
};

var updateQueueChange = function(queueSizes) {
  $('table.queues tbody tr').map(function(index, item) {
    var $cell = $(item.cells[1]),
        count = parseInt(item.cells[1].innerHTML.replace(/\D/g, ''), 10),
        diff = count - queueSizes[index],
        percent, span;

    queueSizes[index] = count;

    if (diff === 0) { return; }

    percent = (Math.round(diff / queueSizes[index] * 1000) / 10);
    span  = '<span class="queue-change" style="color: ' + (diff > 0 ? '#AC1203' : '#7c9b27') + ';">';
    span += '(' + diff + ' ' + (diff > 0 ? '&#9650; ' : '&#9660; ') + percent + '%)</span>';
    span += '</span>';

    $cell.width($cell.width());
    item.cells[1].innerHTML = item.cells[1].innerHTML + span;
  });
};

$(function(){
  var currentQueueSizes = getQueueSizes();

  $(document).ajaxComplete(function(event, jqxhr, settings) {
    if (window.location.pathname != '/sidekiq/queues') { return; }
    if (settings.url != '/sidekiq/queues') { return; }

    window.setTimeout(function() {
      updateQueueChange(currentQueueSizes);
      currentQueueSizes = getQueueSizes();
    }, 0);
  });
});
