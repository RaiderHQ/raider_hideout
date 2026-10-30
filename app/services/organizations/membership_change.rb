module Organizations
  # Role changes and removals for organization memberships. All owner rules live
  # here; checks run inside an organization lock so concurrent changes can't
  # drop the owner count to zero.
  class MembershipChange
    class Forbidden < StandardError
      attr_reader :required_role

      def initialize(required_role = "admin")
        @required_role = required_role
        super("You need the #{required_role} role or higher to do this.")
      end
    end
    class Invalid < StandardError; end

    LAST_OWNER = "An organization needs at least one owner".freeze
    PERSONAL_DEMOTION = "The owner of a personal organization can't be demoted".freeze
    PERSONAL = "You can't leave your personal organization".freeze

    def self.update_role!(actor:, membership:, role:)
      new(actor, membership).update_role!(role.to_s)
    end

    def self.remove!(actor:, membership:)
      new(actor, membership).remove!
    end

    def initialize(actor, membership)
      @actor = actor
      @membership = membership
      @organization = membership.organization
    end

    def update_role!(role)
      with_locked_state do
        authorize_manage!(granting: role)
        raise Invalid, PERSONAL_DEMOTION if role != "owner" && @membership.user_id == @organization.personal_owner_id
        raise Invalid, "Role isn't valid" unless Membership::ROLES.include?(role)

        guard_last_owner! if role != "owner"
        @membership.update!(role: role)
      end
    end

    def remove!
      with_locked_state do
        authorize_manage! unless @membership.user_id == @actor.id
        raise Invalid, PERSONAL if @membership.user_id == @organization.personal_owner_id

        guard_last_owner!
        @membership.destroy!
      end
    end

    private

    def with_locked_state
      @organization.with_lock do
        @membership.reload
        @actor_role = @organization.role_for(@actor)
        yield
      end
    end

    def authorize_manage!(granting: nil)
      raise Forbidden, "admin" unless @actor_role && Membership::RANK.fetch(@actor_role) >= Membership::RANK.fetch("admin")
      return if @actor_role == "owner"

      raise Forbidden, "owner" if @membership.role == "owner" || granting == "owner"
    end

    def guard_last_owner!
      return unless @membership.role == "owner"

      raise Invalid, LAST_OWNER if @organization.memberships.where(role: "owner").count <= 1
    end
  end
end
