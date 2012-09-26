require "./application/core_extensions/sprockets"

set :sprockets, SPROCKETS
configure do
  configure_sprockets
end

