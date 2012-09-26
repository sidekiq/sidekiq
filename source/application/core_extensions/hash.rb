class Hash
  # converts a Hash to a key value pair for use in a querystring (qs is short for querystring)
  #   Also, it uses CGI to escape the strings
  #
  #   { :id => 22, :me => 'you sucka!' }.to_qs
  #
  # yields
  #
  #   id=22&me=you+sucka%21
  #
  def to_qs
    collect do |key, value|
      "#{ CGI.escape(key.to_s) }=#{ CGI.escape(value.to_s) }"
    end.sort * '&'
  end
  
  # converts a Hash into an HTML attribute where the key is the attribute and the value is the value.
  #   { :id => 'two', :class => 'me', :required => nil }.to_attr
  # yields
  #   id="two" class="me" required
  #
  # Really handy for generating markup
  def to_attr
    collect do |key, value|
      if value.is_a? Hash
        value.collect do |k, v|
          "#{key}-#{k}='#{v}'"
        end
      else
        value.nil? ? key.to_s : "#{key}='#{value}'"
      end
    end.join(' ').chomp
  end
end
