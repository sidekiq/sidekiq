# further requires (models, helpers, core extensions etc. { but not 'middleware' because that should be grabbed up by Rack when appropriate })
Dir.glob('./application/**/*.rb') do |file|
  require file
end

before do
  # opt into the future
  response['X-UA-Compatible'] = "IE=edge,chrome=1"
end

get '/' do
  @title = Settings.app_title
  @description = Settings.app_title
  erb :index
end

get '/alt' do
  @title = Settings.app_title
  @description = Settings.app_title
  erb :alt
end
