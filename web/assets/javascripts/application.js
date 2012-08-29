//= require vendor/jquery
//= require vendor/jquery.timeago
//= require bootstrap
//= require_tree .

$(function() {
  $.timeago.settings.allowFuture = true
  $("time").timeago();
});

$(function() {
  $('.check_all').live('click', function() {
    var checked = $(this).attr('checked');
    if (checked == 'checked') {
      $('input[type=checkbox]', $(this).closest('table')).attr('checked', checked);
    } else {
      $('input[type=checkbox]', $(this).closest('table')).removeAttr('checked');
    }
  });
});

$(function() {
  function pad(n) { return ('0' + n).slice(-2); }

  $('a[name=poll]').data('polling', false);

  $('a[name=poll]').on('click', function(e) {
    e.preventDefault();
    var pollLink = $(this);
    if (pollLink.data('polling')) {
      clearInterval(pollLink.data('interval'));
      pollLink.text('Live Poll');
      $('.poll-status').text('');
    }
    else {
      var href = pollLink.attr('href');
      pollLink.data('interval', setInterval(function() {
        $.get(href, function(data) {
          var responseHtml = $(data);
          $('.hero-unit').replaceWith(responseHtml.find('.hero-unit'));
          $('.workers').replaceWith(responseHtml.find('.workers'));
          $('time').timeago();
        });
        var currentTime = new Date();
        $('.poll-status').text('Last polled at: ' + currentTime.getHours() + ':' + pad(currentTime.getMinutes()) + ':' + pad(currentTime.getSeconds()));
      }, 2000));
      $('.poll-status').text('Starting to poll...');
      pollLink.text('Stop Polling');
    }
    pollLink.data('polling', !pollLink.data('polling'));
  })
});

$(function() {
  $('[data-confirm]').click(function() {
    return confirm($(this).attr('data-confirm'));
  });
});
