class MoveProjectsToOrganizations < ActiveRecord::Migration[8.1]
  # Frozen copy of the slug rule from Project/Organization at the time of writing.
  RESERVED_SLUGS = %w[new edit].freeze

  # Plain SQL through the migration's connection, independent of app models.
  def up
    add_reference :projects, :organization, foreign_key: true, null: true
    backfill_personal_organizations
    execute <<~SQL
      UPDATE projects
      SET organization_id = (SELECT o.id FROM organizations o WHERE o.personal_owner_id = projects.owner_id)
      WHERE organization_id IS NULL
    SQL
    change_column_null :projects, :organization_id, false
    remove_reference :projects, :owner, foreign_key: { to_table: :users }, index: true
  end

  def down
    add_reference :projects, :owner, foreign_key: { to_table: :users }, null: true
    execute <<~SQL
      UPDATE projects
      SET owner_id = COALESCE(
        (SELECT o.personal_owner_id FROM organizations o
         WHERE o.id = projects.organization_id AND o.personal = #{quoted_true}),
        (SELECT m.user_id FROM memberships m
         WHERE m.organization_id = projects.organization_id AND m.role = 'owner'
         ORDER BY m.id LIMIT 1)
      )
    SQL
    change_column_null :projects, :owner_id, false
    remove_reference :projects, :organization, foreign_key: true, index: true
  end

  private

  def backfill_personal_organizations
    taken = connection.select_values("SELECT slug FROM organizations").to_set
    users = connection.select_rows(<<~SQL)
      SELECT u.id, u.email_address FROM users u
      WHERE NOT EXISTS (SELECT 1 FROM organizations o WHERE o.personal_owner_id = u.id)
      ORDER BY u.id
    SQL
    now = quote(Time.current.utc)
    users.each do |id, email|
      name = "#{email.split('@').first}'s organization"
      slug = unique_slug(name, taken)
      taken << slug
      org_id = connection.insert(<<~SQL)
        INSERT INTO organizations (name, slug, personal, personal_owner_id, created_at, updated_at)
        VALUES (#{quote(name)}, #{quote(slug)}, #{quoted_true}, #{Integer(id)}, #{now}, #{now})
      SQL
      connection.execute <<~SQL
        INSERT INTO memberships (organization_id, user_id, role, created_at, updated_at)
        VALUES (#{Integer(org_id)}, #{Integer(id)}, 'owner', #{now}, #{now})
      SQL
    end
  end

  def unique_slug(name, taken)
    base = name.parameterize.presence || "organization"
    candidate = base
    suffix = 1
    while RESERVED_SLUGS.include?(candidate) || taken.include?(candidate)
      suffix += 1
      candidate = "#{base}-#{suffix}"
    end
    candidate
  end

  def quote(value) = connection.quote(value)

  def quoted_true = connection.quoted_true
end
