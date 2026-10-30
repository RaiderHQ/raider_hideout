module Api
  module V1
    # §5.10 one active quarantine.
    class QuarantinePresenter < BasePresenter
      def initialize(quarantine, url_options:)
        super(url_options: url_options)
        @quarantine = quarantine
      end

      def to_h
        { test_case_id: @quarantine.test_case_id, full_name: @quarantine.test_case.full_name, reason: @quarantine.reason,
          expires_at: time(@quarantine.expires_at), quarantined_by: @quarantine.created_by&.email_address,
          created_at: time(@quarantine.created_at) }
      end
    end
  end
end
