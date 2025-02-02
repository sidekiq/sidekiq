#!/bin/bash
# Start Redis in background
redis-server --daemonize yes

# Start CPU monitoring in background
ruby cpu_monitor.rb &

# Run the load test
ruby bin/sidekiqload
