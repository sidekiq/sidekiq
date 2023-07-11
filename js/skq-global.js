$(document).ready(function() {

    var body = $('html, body');
    var windowHeight = $(window).height();
    var scrollPos = document.body.scrollTop;
    var mobileBreak = 992;
    var logoCarousel = $(".logo-carousel");
    var navBar = $(".navbar");

    setCarouselHeight('#carousel');
    logoCarousel.addClass('js-carousel');
    logoCarousel.removeClass('noscript-carousel');

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

    collapseHeader();

    function collapseHeader() {
        var pageScroll = $(this).scrollTop();
        var headerHeight = 120;

        // Animate collapse attached to scrolling position
        if(pageScroll > 0 && pageScroll < headerHeight ) {
            $(".navbar, .navbar-header, .skq-header").css({'height' : headerHeight-(pageScroll*0.58333333)});
            navBar.css({'min-height' : 50});
            $(".navbar-toggle").css({'margin-top' : 43-(pageScroll*0.28333333)});

            $(".skq, .skq-nav-link").css({'padding-top' : 49-(pageScroll*0.28333333), 'padding-bottom' : 49-(pageScroll*0.28333333)});

            $(".skq").css({'font-size' : 47-(pageScroll*0.18333333)});
            $(".skq-tagline").css({'opacity' : 1-(pageScroll*0.058333333)});
        }
        // Set to collapsed after scrolling past headerHeight
        if(pageScroll > headerHeight) {
            $(".navbar, .navbar-header, .skq-header").css({'height' : 50});
            navBar.addClass('nav-mini');
            navBar.css({'min-height' : 50});

            $(".skq, .skq-nav-link").css({'padding-top' : 15, 'padding-bottom' : 15});
            $(".navbar-toggle").css({'margin-top' : 8});

            $(".skq").css({'font-size' : 25});
            $(".skq-tagline").css({'opacity' : 0});
        }
        // Reset elements at scrolltop
        if(pageScroll < 5) {
            $(".navbar, .navbar-header, .skq-header").css({'height' : headerHeight});
            navBar.removeClass('nav-mini');

            $(".skq, .skq-nav-link").css({'padding-top' : 49, 'padding-bottom' : 49});
            $(".navbar-toggle").css({'margin-top' : 43});

            $(".skq").css({'font-size' : 47});
            $(".skq-tagline").css({'opacity' : 1});
        }

        subNavOffset = $(".skq-header").height()
        $('.purchase').css({'margin-top' : subNavOffset})
    };

    $('#logo-carousel').scrollingCarousel({
        autoScroll: true,
        scrollSpeed: 'slow',
        autoScrollSpeed: 15000,
        cursorPosition: 0,
      });

      $('.jump-link').click(function(){
        $('html, body').animate({
            scrollTop: $( $.attr(this, 'href') ).offset().top -100}, 400);
        return false;
      });

    $(window).scroll(function(){
        collapseHeader();
    });
});
