$(document).ready(function() {

	var body = $('html, body');
  var windowHeight = $(window).height()
  var scrollPos = document.body.scrollTop
  var mobileBreak = 992

  setCarouselHeight('#carousel');

  function setCarouselHeight(id) {
    var slideHeight = [];
    $(id+' .carousel-inner .item').each(function() {
        slideHeight.push($(this).height());
    });
    max = (Math.max.apply(null, slideHeight) + 30);
    $(id+' .carousel-inner', '.rule-left').each(function() {
        $(this).css({'height' : max+'px'});
    });
  }
});