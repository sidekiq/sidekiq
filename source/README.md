# Foreword : Sixdegrees's Additions

* Migrated many things to Settings, using [Settingslogic](https://github.com/binarylogic/settingslogic)
* Memcached made optional (using settings.yml)
* Made sprockets configuration a bit more flexible (using settings.yml)
* Added `lib` and `vendor` search paths for Sprockets. Add your extensions & libs, and reference them in vendor.css & vendor.js
* Vendored [bootstrap](http://twitter.github.com/bootstrap/)
* Added crossdomain.xml & 404 static file
* Migrated email notification sender & receiver in settings.yml
* Examples for compass spriting, and webfonts inclusion
* Ready for Pow…


# Sinatra Boilerplate

A great place to start with [Sinatra](http://www.sinatrarb.com/), [HTML5 Boilerplate](http://html5boilerplate.com/), [Compass](http://compass-style.org/), [CoffeeScript](http://coffeescript.org/) and [Sprockets (aka the asset pipeline)](https://github.com/sstephenson/sprockets) all cooked together.

## TL;DR: Get me up and running

1. Grab the code and `bundle` the gems.
2. Make sure you have [memcached](http://www.memcached.org/) installed.
3. Run `rake s` to start the development server.

# What's in the Box

## HTML5 Boilerplate

sinatra-boilerplate uses *some* of the utter uber-hawtness that is the [HTML5 Boilerplate](http://html5boilerplate.com/) but *not all*. I opted not to use the build script stuff because I feel like it adds an extra layer of trouble when working with Sinatra.

The base layout file is pretty compliant with what the Boilerplate puts out except for a few minor tweaks. Most of the comments have been left in place as well.

Direct implementations from HTML5BP:

* `html` scoping by class.
* Viewport settings for mobile browsers.
* Better analytics script.
* More awesome CSS base.
* ... probably more that I've forgotten :)

## Modernizr

[Modernizr](http://www.modernizr.com/) is fantastic and I threw it in because... well, it's fantastic!

## Modernizr.load

*There's an [outstanding bug in Yepnope](https://github.com/SlexAxton/yepnope.js/issues/100) that's made `Modernizr.load` a lot less useful so I've decided to stop including it here.* Feel free to use it in your own build but I won't include it here again until that issue gets fixed.

## Compass

Because CSS sucks and SASS + Compass doesn't.

Compass + SASS gives you all kinds of great mixins and nesting stuff that would surely make anyone who's done a lot of CSS quiver in schoolgirl-like delight. Take, for example, some CSS:

```css
#content { border: 1px solid red; }
#content p { font-size: 34em; }
#content p.small { font-size: 12em; }
#content em { color: white; }
```

Not so great. You have to write `#content` each time you want to address that element. How about with Compass?

```scss
#content {
  border: 1px solid red;
  
  p {
    font-size: 34em;
    
    &.small {
      font-size: 12em;
    }
  }
  em {
    color: white;
  }
}
```

Wait, **what**? Yeah, you can nest it all. If you do any CSS at all in your life ever then you should be using Compass.

[Scope the docs and get crackin'.](http://compass-style.org/)


## Sinatra Addons

### Run Later

After filters are great and all, but they block the rendering of the page and that sucks. I want to be able to, mid-render, tell Ruby to go off and do some stuff that I know will take a long time without it stopping the current page. Think of it as an asynchronous (ya know, like AJAX) Ruby request!

This is a plain insert of my [Sinatra run_later module](https://github.com/l3ck/sinatra_run_later), which I based off of [this run_later module](https://github.com/pmamediagroup/sinatra_run_later) which is based off of [THIS run_later module](https://github.com/mattmatt/run_later). Use it like so:

```ruby
require 'rubygems'
require 'sinatra'
require 'run_later'

get '/' do
  run_later do
    # some task that you don't want to block.
    sleep 20
  end

  "Hello World"
end
```








### Form Tag Helpers

The thing I missed most in Sinatra was the glorious `input_for` kind of stuff you get with Rails, so I made some!

```ruby
# input_for
input_for :first_name # => <input type='text' name='first_name' id='first_name' value=''>

# input_for with options
input_for :email, :type => 'email', :required => nil # => <input type='email' name='email' id='email' required value=''>

# select_for
select_for 'days', { :monday => 'Monday', :myday => 'MY DAY!' }

# yields
# <select name='days' id='days' size='1'>
#   <option value='monday'>Monday</option>
#     <option value='myday'>MY DAY!</option>
# </select>
```







## Extra Hawt Sauce

I've added a bunch of modules and helper functions that I use all the time to this to (hopefully) make your life easier when you're getting your app first setup. Some of the helpers methods I've added include:

* **SPROCKETS**
  * holy crap that's nice!!
* **core extensions**
  * extended Hash class with some useful methods for the web
* **Sinatra extensions**
  * a better `erb` method so you don't have to do crap like `erb :"folder/file"` anymore


## How to Use It

You like it? **Awesome!** Here's how to use it:

1. Download the sauce (either through git or the download button).
2. `bundle`
3. Make sure you have [memcached](http://www.memcached.org/) installed.
4. Run `rake s` from the directory of the sauce.
5. Profit!

If you have suggestions or think I goofed please let me know or send a pull request.

## Acknowledgements

All the stuff used here is either open source or donation ware and totally the work of the people who made it, not me. I just put the pieces together and bundled it up all pretty-like. This little starter package wouldn't be possible without the awesome work these guys have done and their generosity in sharing their code with the rest of us.

Oh, and...

<pre>
# . . . . . . . . . . . . . . . . _,,,--~~~~~~~~--,_
# . . . . . . . . . . . . . . ,-' : : : :::: :::: :: : : : : :º '-, ITS A TRAP!
# . . . . . . . . . . . . .,-' :: : : :::: :::: :::: :::: : : :o : '-,
# . . . . . . . . . . . ,-' :: ::: :: : : :: :::: :::: :: : : : : :O '-,
# . . . . . . . . . .,-' : :: :: :: :: :: : : : : : , : : :º :::: :::: ::';
# . . . . . . . . .,-' / / : :: :: :: :: : : :::: :::-, ;; ;; ;; ;; ;; ;; ;\
# . . . . . . . . /,-',' :: : : : : : : : : :: :: :: : '-, ;; ;; ;; ;; ;; ;;|
# . . . . . . . /,',-' :: :: :: :: :: :: :: : ::_,-~~,_'-, ;; ;; ;; ;; |
# . . . . . _/ :,' :/ :: :: :: : : :: :: _,-'/ : ,-';'-'''''~-, ;; ;; ;;,'
# . . . ,-' / : : : : : : ,-''' : : :,--'' :|| /,-'-'--'''__,''' \ ;; ;,-'/
# . . . \ :/,, : : : _,-' --,,_ : : \ :\ ||/ /,-'-'x### ::\ \ ;;/
# . . . . \/ /---'''' : \ #\ : :\ : : \ :\ \| | : (O##º : :/ /-''
# . . . . /,'____ : :\ '-#\ : \, : :\ :\ \ \ : '-,___,-',-`-,,
# . . . . ' ) : : : :''''--,,--,,,,,,¯ \ \ :: ::--,,_''-,,'''¯ :'- :'-,
# . . . . .) : : : : : : ,, : ''''~~~~' \ :: :: :: :'''''¯ :: ,-' :,/\
# . . . . .\,/ /|\\| | :/ / : : : : : : : ,'-, :: :: :: :: ::,--'' :,-' \ \
# . . . . .\\'|\\ \|/ '/ / :: :_--,, : , | )'; :: :: :: :,-'' : ,-' : : :\ \,
# . . . ./¯ :| \ |\ : |/\ :: ::----, :\/ :|/ :: :: ,-'' : :,-' : : : : : : ''-,,
# . . ..| : : :/ ''-(, :: :: :: '''''~,,,,,'' :: ,-'' : :,-' : : : : : : : : :,-'''\\
# . ,-' : : : | : : '') : : :¯''''~-,: : ,--''' : :,-'' : : : : : : : : : ,-' :¯'''''-,_ .
# ./ : : : : :'-, :: | :: :: :: _,,-''''¯ : ,--'' : : : : : : : : : : : / : : : : : : :''-,
# / : : : : : -, :¯'''''''''''¯ : : _,,-~'' : : : : : : : : : : : : : :| : : : : : : : : :
# : : : : : : : :¯''~~~~~~''' : : : : : : : : : : : : : : : : : : | : : : : : : : : :
</pre>

So, ya know, watch out...
