PadrinoApp::App.mailer :the_messenger do
  email :greetings do |now|
    from "sidekiq@example.com"
    to "mperham@gmail.com"
    subject "Ahoy Matey!"

    locals :now => now, :hostname => `hostname`.strip
    render 'the_messenger/greetings'
  end
end
