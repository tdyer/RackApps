require 'rubygems'
require 'logger'
require 'rack/async'
require './em_async_app'
require './tracker_heartbeat'
require './promo_judge'

use Rack::ShowExceptions

# Set the development, test or production environment
# development (the default)
# thin --rackup config.ru start -p 8111
# production
# thin --rackup config.ru start -p 8111 -e production
environment = ENV['RACK_ENV']
valid_environments = %w{development test production}
unless valid_environments.include?(environment)
  raise ArgumentError.new("Invalid environment #{environment}, must be #{valid_environments.join(' OR ')}") 
end

# set up the Apache-like logger
log = Logger.new("log/#{environment}.log", File::WRONLY | File::APPEND)
case environment
when 'development'
  log.level = Logger::DEBUG
when 'test'
  log.level = Logger::DEBUG
when 'production'
  log.level = Logger::INFO
else
  raise ArgumentError.new("Invalid environment #{environment}, must be #{valid_environments.join(' OR ')}") 
end
use Rack::CommonLogger, log

# for handling asyn requests
use Rack::Async

# damn dumb Rack endpoint, blocking request
map "/rack" do
  # ab -n 100 -c 50 http://127.0.0.1:8111/rack
  # Requests per second:    3512.10 [#/sec] (mean)
  run EMAsyncApp.new(:method => 'rack_standard')
end

# Non-blocking Rack endpoint that returns immediately.
# It runs a logging statement in a EM timer that simulates
# a really slow blocking call that get's run asynchronously.
map "/rack_async" do
  # ab -n 100 -c 50 http://127.0.0.1:8111/rack_async
  # Requests per second:    5224.39 [#/sec] (mean)
  run EMAsyncApp.new(:method => 'rack_async', :logger => log)
end

# Non-blocking Rack endpoint that returns immediately.
# Runs a SQL query asynchronously.
map "/db_async" do
  # ab -n 100 -c 50 http://127.0.0.1:8111/db_async
  # Requests per second:    4955.40 [#/sec] (mean)
  run EMAsyncApp.new(:method => 'db_async', :query => 'select count(*) from categories', :logger => log)
end

# Health Check Rack endpoint, doesn't get much simpler that this.
map "/health_check" do
  run lambda{ |env| [200, {"Content-Type"=> "text/plain"}, ["Good to go!"]] }
end

# Heart Beat Rack endpoint
# insert into the stats DB, heartbeats table
map "/tracker/heartbeat/" do
  # ab -n 100 -c 50 -p test/tracker_heartbeat_data -T 'application/x-www-form-urlencoded' http://127.0.0.1:8111/tracker/heartbeat 
  # Requests per second:    1987.83 [#/sec] (mean)
  run TrackerHeartbeat.new(:logger => log, :environment => environment)
end

# Promo Judge Click Rack endpoint
# insert into the ourstage DB, promo_data_judge_clicks table
map "/api/promo_judge/click" do
  # ab -n 100 -c 50 -C promo_code='noisepop' -p test/promo_click_data -T 'application/x-www-form-urlencoded' -H "X-Requested-With: XMLHttpRequest" http://127.0.0.1:8111/api/promo_judge/click
  # Requests per second:    397.84 [#/sec] (mean)
  run PromoJudge.new(:method => :click, :logger => log, :environment => environment)
end

# start this rack app with thin on port 8111
#  thin --rackup config.ru start -p 8111

# same as above but logging request/response (much slower!)
# thin --rackup config.ru start -p 8111 -V


