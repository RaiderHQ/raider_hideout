require "securerandom"
require "active_support/security_utils"

module Hideout
  # The one-time code that guards /setup (spec 2026-10-29 §5.2): from
  # HIDEOUT_SETUP_CODE, or random per process and printed in the boot log.
  module SetupCode
    ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".chars.freeze
    LENGTH = 8

    class << self
      def current(env = ENV)
        configured = normalize(env["HIDEOUT_SETUP_CODE"])
        return configured unless configured.empty?

        @generated ||= Array.new(LENGTH) { ALPHABET[SecureRandom.random_number(ALPHABET.size)] }.join
      end

      def display(env = ENV)
        code = current(env)
        code.length == LENGTH ? "#{code[0, 4]}-#{code[4, 4]}" : code
      end

      def valid?(candidate, env = ENV)
        given = normalize(candidate)
        !given.empty? && ActiveSupport::SecurityUtils.secure_compare(given, current(env))
      end

      def normalize(value) = value.to_s.upcase.gsub(/[\s-]/, "")

      def announcement(env = ENV, rails_env: Rails.env)
        "[hideout] no users yet: open #{Hideout.base_url(env, rails_env: rails_env)}/setup?code=#{display(env)} " \
          "to create the first admin"
      end

      def reset! = @generated = nil
    end
  end
end
