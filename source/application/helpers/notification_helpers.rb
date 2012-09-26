module Sinatra
  module NotificationHelpers
    def notify_devs(err)
      exception = err
      from      = Settings.notifications.sender
      subject   = "A #{ exception.class.to_s } Occurred on Your Rack Application"
      body      = ERB.new(EMAIL_TEMPLATE).result(binding) # not sure about this (binding) thing
      html_body = ERB.new(HTML_EMAIL_TEMPLATE).result(binding)
    
      # loop and email
      Settings.notifications.recipients.each do |email|
        Pony.mail :to => email, :from => from, :subject => subject, :body => body, :html_body => html_body, :via => :sendmail
      end
    rescue
      # shhhh
    end
  end
  
  helpers NotificationHelpers
end
