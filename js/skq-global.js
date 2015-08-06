$(document).ready(function() {

    var body = $('html, body');

    collapseHeader();

    function collapseHeader() {
        var pageScroll = $(this).scrollTop();
        var elementPadding = $('a.skq').css('padding-top').replace(/[^-\d\.]/g, '');
        var headerHeight = 120

        // Animate collapse attached to scrolling position
        if(pageScroll > 0 && pageScroll < headerHeight ) {
            $(".navbar, .navbar-header, .skq-header").css({'height' : headerHeight-(pageScroll*0.58333333)});
            $(".navbar").css({'min-height' : 50});
            $(".navbar-toggle").css({'margin-top' : 43-(pageScroll*0.28333333)});

            $(".skq, .skq-nav-link").css({'padding-top' : 49-(pageScroll*0.28333333), 'padding-bottom' : 49-(pageScroll*0.28333333)});

            $(".skq").css({'font-size' : 47-(pageScroll*0.18333333)});
            $(".skq-tagline").css({'opacity' : 1-(pageScroll*0.058333333)});
        }
        // Set to collapsed after scrolling past headerHeight
        if(pageScroll > headerHeight) {
            $(".navbar, .navbar-header, .skq-header").css({'height' : 50});
            $(".navbar").addClass('nav-mini');
            $(".navbar").css({'min-height' : 50});
            
            $(".skq, .skq-nav-link").css({'padding-top' : 15, 'padding-bottom' : 15});
            $(".navbar-toggle").css({'margin-top' : 8});

            $(".skq").css({'font-size' : 25});
            $(".skq-tagline").css({'opacity' : 0});
        }
        // Reset elements at scrolltop
        if(pageScroll < 5) {
            $(".navbar, .navbar-header, .skq-header").css({'height' : headerHeight});
            $(".navbar").removeClass('nav-mini');
            
            $(".skq, .skq-nav-link").css({'padding-top' : 49, 'padding-bottom' : 49});
            $(".navbar-toggle").css({'margin-top' : 43});

            $(".skq").css({'font-size' : 47});
            $(".skq-tagline").css({'opacity' : 1});
        }

        subNavOffset = $(".skq-header").height()
        $('.purchase').css({'margin-top' : subNavOffset})
    };

    $('#logo-carousel').scrollingCarousel({
        scrollSpeed: 'slow'
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