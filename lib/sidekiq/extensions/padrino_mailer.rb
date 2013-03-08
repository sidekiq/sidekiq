module Padrino
  class Mailer
    include Sidekiq::Worker
  end
end
