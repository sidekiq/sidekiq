FROM ruby:3.4
RUN apt-get update && apt-get install -y redis-server

# Copy the entire Sidekiq repo
WORKDIR /app
COPY . .

# Install dependencies
RUN bundle install

# Add our CPU monitoring
COPY cpu_monitor.rb /app/cpu_monitor.rb

# Script to start both Redis and run our test
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
