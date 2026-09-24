# frozen_string_literal: true

require 'rack-timeout'

# Insert the Captain LLM timeout shim *before* Rack::Timeout::Middleware
# so the value it writes into env['rack-timeout.service_timeout'] is
# visible when Rack::Timeout schedules its kill.
#
# rack-timeout's railtie inserts its own middleware at boot; by the time
# this initializer runs, Rack::Timeout::Middleware is already in the
# stack. If for any reason it is not (e.g. the gem stops using a railtie),
# we fall back to inserting at position 0, which still places us ahead
# of any default middleware rack-timeout might add later.
begin
  Rails.application.config.middleware.insert_before(
    Rack::Timeout::Middleware,
    CaptainLlmTimeout
  )
rescue StandardError => e
  warn "[rack_timeout] insert_before(Rack::Timeout::Middleware) failed: #{e.message}; " \
       'falling back to insert_before(0, CaptainLlmTimeout)'
  Rails.application.config.middleware.insert_before(0, CaptainLlmTimeout)
end

Rack::Timeout::Logger.level = Logger::ERROR if defined?(Rack::Timeout::Logger)
