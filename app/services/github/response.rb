module Github
  # `run_id` and `html_url` are set only by a workflow dispatch that GitHub accepted with run
  # details, and only after the client has validated them.
  Response = Data.define(:status, :message, :run_id, :html_url) do
    def initialize(status:, message:, run_id: nil, html_url: nil) = super
  end
end
