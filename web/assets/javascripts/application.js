//= require vendor/jquery
//= require vendor/jquery.timeago
//= require bootstrap
//= require_tree .

jQuery(document).ready(function() {
  jQuery.timeago.settings.allowFuture = true
  jQuery("time").timeago();
});
