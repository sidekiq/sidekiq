#!/bin/bash
# Start Redis in background
redis-server --daemonize yes

# Run the load test
ruby bin/sidekiqload
