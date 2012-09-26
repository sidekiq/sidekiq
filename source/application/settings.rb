require 'settingslogic'

class Settings < Settingslogic
  env = ENV['RACK_ENV']
  source "#{PROJECT_ROOT}/config/settings.yml"
  namespace env
  load!
end
