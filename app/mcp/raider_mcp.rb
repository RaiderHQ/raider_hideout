# The Raider MCP server (spec §6): read-only tools over the personal-token Reader, so every
# tool returns the same data as its REST endpoint.
module RaiderMcp
  INSTRUCTIONS = "Read-only access to Raider test results. Projects are identified by slug; call list_projects first. " \
                 "search_tests accepts Explore query syntax.".freeze

  def self.tools
    [ Tools::ListProjects, Tools::ProjectHealth, Tools::ListBuilds, Tools::GetBuild, Tools::SearchTests, Tools::GetTest,
      Tools::ListErrorGroups, Tools::GetErrorGroup, Tools::ListFlakyTests, Tools::ListQuarantines ]
  end

  def self.server(user:, base_url:, token_id:)
    MCP::Server.new(name: "raider", version: (Rails.application.config.x.version.presence || "dev").to_s,
                    instructions: INSTRUCTIONS, tools: tools,
                    server_context: { user: user, base_url: base_url, token_id: token_id })
  end

  # Only the host counts: port and scheme are ignored; an Origin that is not a URL never matches.
  def self.same_host?(origin, host)
    origin_host = URI.parse(origin.to_s).host
    origin_host.present? && origin_host.casecmp?(host.to_s)
  rescue URI::InvalidURIError
    false
  end
end
