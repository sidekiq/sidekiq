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
