# ================
# = Form Helpers =
# ================
module Sinatra
  module FormTagHelpers
    
    # input_for creates an <input> tag with a number of configurable options
    #   if `param` is set in the `params` hash, the values from the `params` hash will be populated in the tag.
    #
    #   <%= input_for 'something_hidden', :type => 'hidden', :value => 'Shhhhhh' %>
    # 
    # Yields:
    # 
    #   <input type='hidden' name='something_hidden' id='something_hidden' value='Shhhhhh'>
    # 
    def input_for(param, attributes = {})
      # default values when not specified.
      attributes = {
        :type  => 'text', # can be any HTML input type ('email', 'submit', 'password', etc.)
        :value => h(params[param.to_sym]) || '',
        :name  => param,
        :id    => attributes[:id] || param
      }.merge(attributes)

      "<input #{ attributes.to_attr }>"
    end
    
    # radio_for creates an input tag of type radio and marks it `checked` if the param argument is set to the same value in the `params` hash
    def radio_for(param, attributes = {})
      attributes = {
        :type => 'radio'
      }.merge(attributes)
  
      if params[param.to_sym].to_s == attributes[:value].to_s
        attributes.merge!({ :checked => nil })
      end
  
      input_for param, attributes
    end
    
    # checkbox_for creates an input of type checkbox with a `checked_if` argument to determine if it should be checked
    # 
    #   <%= checkbox_for 'is_cool', User.is_cool? %>
    # 
    # Yields:
    #
    #   <input type='checkbox' name='is_cool' id='is_cool' value='true'>
    # 
    # Which will be marked with `checked` if `User.is_cool?` evaluates to true
    # 
    def checkbox_for(param, checked_if, attributes = {})
      attributes = {
        :type    => 'checkbox',
        :value   => 'true'
      }.merge(attributes)
  
      if checked_if || params[param.to_sym] == 'true'
        attributes.merge!({ :checked => nil })
      end
  
      input_for param, attributes
    end
    
    # creates a simple <textarea> tag
    def textarea_for(param, attributes = {})
      # default values to include
      attributes = {
        :name    => param,
        :id      => attributes[:id] || param
      }.merge(attributes)
  
      "<textarea #{ attributes.to_attr }>#{ h(params[param.to_sym]) || '' }</textarea>"
    end
    
    
    # option_for creates an <option> element with the specified attributes
    #   if the param specified is set to the value of this option tag then it is marked as 'selected'
    #   designed to be used within a <select> element
    #
    #   <%= option_for 'turtles', :key => 'I love them', :value => 'love' %>
    # 
    # Yields:
    # 
    #   <option value='love'>I love them</option>
    #
    # If params[:turtle] is set to 'love' this yields:
    #
    #   <option value='love' selected>I love them</option>
    # 
    def option_for(param, attributes = {})
      if params[param.to_sym]
        default = params[param].to_s
      elsif attributes[:default]
        default = attributes.delete(:default).to_s
      else
        default = ''
      end
      
      attributes.merge!({ :selected => nil }) if default == attributes[:value].to_s
  
      "<option #{ attributes.to_attr }>#{ attributes.delete(:key) }</option>"
    end
    
    
    # select_for creates a <select> element with the specified attributes
    #   options are the available <option> tags within the <select> box
    #
    #   <%= select_for 'days', { :monday => 'Monday', :myday => 'MY DAY!' } %>
    # 
    # Yields:
    # 
    #   <select name='days' id='days' size='1'>
    #     <option value='monday'>Monday</option>
    #     <option value='myday'>MY DAY!</option>
    #   </select>
    #
    def select_for(param, options, attributes = {})
      "<select #{ attributes.to_attr } name='#{ param }' id='#{ param }' size='1'>
        #{ options.collect { |key, val| option_for(param, :key => key, :value => val, :default => attributes[:default]) }.join(' ').chomp }
      </select>"
    end
  end
  
  # comment this out if you don't want these methods included
  # or want to include them on your own
  helpers FormTagHelpers
end
