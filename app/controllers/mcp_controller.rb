# POST /mcp (spec §6): the MCP endpoint for Claude and other agents. Stateless: every request
# builds a server for the token's user and answers through the mcp gem's streamable-HTTP
# transport as one buffered body. GET and DELETE answer 405 before authentication.
class McpController < ActionController::API
  # The gem's DNS-rebinding check would reject every non-loopback Host; the Origin check below
  # and Rails host authorization cover it (plan ruling "Transport options").
  TRANSPORT_OPTIONS = { stateless: true, enable_json_response: true, serve_subscriptions_listen: false,
                        dns_rebinding_protection: false }.freeze

  # First, so 403, 401 and 429 are covered: the app-wide CSP nonce lives in the session, and a
  # JSON response has no use for a policy; without this every response sets a cookie.
  before_action { request.content_security_policy = nil }
  before_action :reject_foreign_origin, only: :create
  include Api::PersonalAuthentication
  include Api::RateLimited
  api_rate_limit to: Api::RateLimited::PERSONAL_LIMIT, only: :create, scope: Api::RateLimited::PERSONAL_SCOPE
  skip_before_action :authenticate_personal_token, only: :method_not_allowed

  def create
    server = RaiderMcp.server(user: Current.user, base_url: request.base_url, token_id: @personal_token.id)
    transport = MCP::Server::Transports::StreamableHTTPTransport.new(server, **TRANSPORT_OPTIONS)
    status, headers, body = transport.handle_request(request)
    headers.except("content-type").each { |name, value| response.set_header(name, value) }
    text = body.join
    return head(status) if text.empty?

    render body: text, status: status, content_type: headers.fetch("content-type", "application/json")
  end

  def method_not_allowed
    response.set_header("Allow", "POST")
    render json: { error: "method not allowed" }, status: :method_not_allowed
  end

  private

  # A page on another site must not drive a user's token through their browser. CLI clients
  # send no Origin, and that is allowed.
  def reject_foreign_origin
    origin = request.headers["Origin"]
    return if origin.nil? || RaiderMcp.same_host?(origin, app_host)

    render json: { error: "forbidden origin" }, status: :forbidden
  end

  # In production only APP_HOST counts; blank, no Origin matches (nil), so every Origin is refused.
  def app_host
    Rails.env.production? ? ENV["APP_HOST"].presence : request.host
  end
end
