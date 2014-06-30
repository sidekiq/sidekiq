$(window).bind("load resize", function () {
    'use strict';
    var width = $(window).width();
    if (width >= 992) {
        var names = $('#features .names .entry');
        var slider = $('#slider').not(".slick-initialized")
        slider.slick({
                onAfterChange: function () {
                    var current_index = slider.slickCurrentSlide();
                    names.removeClass('selected');
                    $(names[current_index]).addClass('selected');
                },
                onInit: function () {
                    names.click(function () {
                        var slide = names.index(this);
                        slider.slickGoTo(slide);
                    });
                }

            }
        );

    }
    else {
        $('#slider.slick-initialized').unslick();
    }
});