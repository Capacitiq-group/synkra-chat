# frozen_string_literal: true

require 'rack-timeout'

# Define the middleware inline (not via autoload) so it is guaranteed to be
# available at the exact moment this initializer runs. Loading from
# app/middleware/ depends on autoload paths being set up first, which is not
# guaranteed inside config/initializers.
class CaptainLlmTimeout
  LLM_PATH = %r{\A/api/v1/accounts/\d+/captain/tasks/}.freeze
  LLM_SERVICE_TIMEOUT = 60

  def initialize(app)
    @app = app
  end

  def call(env)
    if env['PATH_INFO'].to_s.match?(LLM_PATH)
      env['rack-timeout.service_timeout'] = LLM_SERVICE_TIMEOUT
    end
    @app.call(env)
  end
end

# rack-timeout's railtie adds Rack::Timeout::Middleware during boot, before
# config/initializers run, so it is present here. If for any reason it is
# not, fail loudly rather than silently skipping the timeout extension.
unless defined?(Rack::Timeout::Middleware)
  raise 'Rack::Timeout::Middleware is not loaded; cannot extend LLM timeouts'
end

Rails.application.config.middleware.insert_before(
  Rack::Timeout::Middleware,
  CaptainLlmTimeout
)

Rack::Timeout::Logger.level = Logger::ERROR if defined?(Rack::Timeout::Logger)
