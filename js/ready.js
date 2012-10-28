$(document).ready(function() {
  if (document.documentElement.clientWidth >= 768) {

    var names = $('#features .names .entry');
    var slider = $('#features .slider').bxSlider({
      controls: false,
      onBeforeSlide: function(slide) {
        names.removeClass('selected');
        $(names[slide]).addClass('selected');
      }
    });
    names.click(function(e) {
      var slide = names.index(this);
      slider.goToSlide(slide);
    });
  }

});
