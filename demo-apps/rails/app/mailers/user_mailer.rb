class UserMailer < ActionMailer::Base
  default from: "sidekiq@example.com"

  def greetings(now)
    @now = now
    @hostname = `hostname`.strip
    mail(:to => 'mperham@gmail.com', :subject => 'Ahoy Matey!')
  end
end
