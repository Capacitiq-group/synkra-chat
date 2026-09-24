# frozen_string_literal: true

# Rack::Timeout reads its per-request service timeout from
# env['rack-timeout.service_timeout'] inside its middleware, before the
# Rails router runs. A controller-level before_action cannot change it:
# by the time the controller executes, the timeout has already been
# scheduled.
#
# The Captain task endpoints call an LLM synchronously (Ollama on CPU),
# which regularly exceeds Rack::Timeout's default 15s. This middleware
# raises the timeout for those paths only, and must be inserted *before*
# Rack::Timeout::Middleware in the stack.
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
