# = Helpers =
helpers do
  # helpers
  include Sprockets::Helpers
  
  alias_method :h, :escape_html
  alias_method :e, :escape
  
  # overrides Sinatra's defaults to allow calling like this:
  #   erb 'partials/flash'
  # 
  # instead of
  #   erb 'partials/flash'.to_sym
  # 
  # or
  #   erb :"partials/flash"
  # 
  # which is just weird and ugly.
  # 
  # also, defaults to not use a layout file when the request is made of XHR

  def erb(template, options = {}, locals = {})
    template = template.to_sym
    options[:layout] = (options[:layout].present? || options[:layout] == false) ? options[:layout] : !request.xhr?
    
    super
  end
  
  # link helper
  # 
  #   <%= link_to 'click here to get awesome hawtness', '/hawtness' %>
  # 
  # with HTML attributes:
  # 
  #   <%= link_to 'Home', '/', :class => 'home-link', :title => 'Click here to go home', :data => { :to => '#home' } %>
  #
  def link_to(text, link, attributes = {})
    if link == (request.url.include?('?') ? "#{ request.path_info }?#{ request.query_string }" : request.path_info)
      attributes[:class] = "#{ attributes[:class] } current"
    end
    
    attributes.merge!({ :href => link })
    
    "<a #{ attributes.to_attr }>#{ text }</a>"
  end
  
  # Returns the url of the referer along with the params posted to that page
  #   Lets you hand back invalid params for correction in the previous page.
  #   You can also add extra params in to send back.
  #
  #   redirect to(back_with_params(:my_extra_param => 'my extra value'))
  #
  def back_with_params(o = {})
    rejected_keys = [:password] # these won't be passed back to the page
    back_to = request.referer ? request.referer : '/'
    params_string = params.blank? ? '' : "?#{ build_query(o.merge(params).delete_if { |k, v| rejected_keys.include?(k.to_sym) }) }"
    
    back_to + params_string
  end
  
  # Handles an unruly `back` method call with an alternate route
  def back_or(new_path)
    if back == '/' || back == request.path_info
      new_path
    else
      back
    end
  end
  
  # Cookie getter / setter
  # 
  # Setter (sets the 'my-cookie' cookie to 'this here is a value'):
  #   
  #   cookie 'my-cookie', 'this here is a value'
  #
  # Getter
  # 
  #   cookie 'my-cookie' # => 'this here is a value'
  # 
  def cookie(name, value = nil, duration = 15)
    if value
      response.set_cookie name, { 
        :value    => value,
        :expires  => Time.now + (60 * duration),
        :path     => "/",
        :httponly => true,
        :secure   => production?
      }
    else
      request.cookies[name]
    end
  end

  # checks the params hash for a single argument as both !nil and !empty
  def ensure_param(arg)
    params[arg.to_sym].present?
  end

  # checks an array of params from the params hash
  def ensure_params(*args)
    return catch(:truthy) {
      args.each do |arg|
        throw(:truthy, false) unless ensure_param(arg)
      end

      throw(:truthy, true)
    }
  end

  # debug log to server log if development
  # else outputs nothing (for production)
  def dlog(*args)
    if development?
      $stdout.puts "\n================================================\n"
      for arg in args
        $stdout.puts arg
        $stdout.puts "================================================\n"
      end
    end
  end
end
