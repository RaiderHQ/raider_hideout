require "rails_helper"
%w[create_organizations create_memberships create_invitations move_projects_to_organizations].each do |name|
  require Dir[Rails.root.join("db/migrate/*_#{name}.rb")].first
end

# Runs the real migrations against a throwaway in-memory SQLite database seeded
# with the pre-organizations schema, so the test DB's schema is never touched.
RSpec.describe MoveProjectsToOrganizations do
  memory_db = Class.new(ActiveRecord::Base) do
    self.abstract_class = true

    def self.name = "MoveProjectsToOrganizationsSpecDb"
  end

  let(:conn) { memory_db.lease_connection }

  def migrate(migration, direction)
    ActiveRecord::Migration.suppress_messages { migration.new.exec_migration(conn, direction) }
  end

  def rows(sql) = conn.select_all(sql).to_a

  def insert_user(email)
    conn.insert("INSERT INTO users (email_address, password_digest, created_at, updated_at) " \
                "VALUES (#{conn.quote(email)}, 'x', '2026-10-01', '2026-10-01')")
  end

  def insert_project(name, owner_id)
    conn.insert("INSERT INTO projects (name, slug, owner_id, created_at, updated_at) " \
                "VALUES (#{conn.quote(name)}, #{conn.quote(name.parameterize)}, #{owner_id}, '2026-10-01', '2026-10-01')")
  end

  before do
    memory_db.establish_connection(adapter: "sqlite3", database: ":memory:")
    conn.create_table(:users) do |t|
      t.string :email_address, null: false, index: { unique: true }
      t.string :password_digest, null: false
      t.timestamps
    end
    conn.create_table(:projects) do |t|
      t.string :name, null: false
      t.string :slug, null: false, index: { unique: true }
      t.references :owner, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end
    [ CreateOrganizations, CreateMemberships, CreateInvitations ].each { |m| migrate(m, :up) }
  end

  after { memory_db.remove_connection }

  it "moves every project into its owner's personal organization and reverses cleanly" do
    ana = insert_user("ana@x.io")
    bo = insert_user("bo@x.io")
    # A pre-existing organization already taking the slug the backfill would want.
    conn.insert("INSERT INTO organizations (name, slug, personal, created_at, updated_at) " \
                "VALUES ('Taken', 'ana-s-organization', 0, '2026-10-01', '2026-10-01')")
    shop = insert_project("Shop", ana)
    blog = insert_project("Blog", ana)

    migrate(MoveProjectsToOrganizations, :up)

    personal = rows("SELECT * FROM organizations WHERE personal = 1 ORDER BY personal_owner_id")
    expect(personal.map { |o| [ o["personal_owner_id"], o["name"] ] })
      .to eq([ [ ana, "ana's organization" ], [ bo, "bo's organization" ] ])
    expect(personal.map { |o| o["slug"] }).to eq(%w[ana-s-organization-2 bo-s-organization])
    ana_org, bo_org = personal.map { |o| o["id"] }

    expect(rows("SELECT organization_id, user_id, role FROM memberships ORDER BY user_id"))
      .to eq([ { "organization_id" => ana_org, "user_id" => ana, "role" => "owner" },
               { "organization_id" => bo_org, "user_id" => bo, "role" => "owner" } ])
    expect(rows("SELECT id, organization_id FROM projects ORDER BY id"))
      .to eq([ { "id" => shop, "organization_id" => ana_org }, { "id" => blog, "organization_id" => ana_org } ])

    expect(conn.column_exists?(:projects, :owner_id)).to be(false)
    expect(conn.columns(:projects).find { |c| c.name == "organization_id" }.null).to be(false)
    expect(conn.foreign_keys(:projects).map(&:to_table)).to eq([ "organizations" ])

    migrate(MoveProjectsToOrganizations, :down)

    expect(conn.column_exists?(:projects, :organization_id)).to be(false)
    expect(conn.columns(:projects).find { |c| c.name == "owner_id" }.null).to be(false)
    expect(conn.foreign_keys(:projects).map(&:to_table)).to eq([ "users" ])
    expect(rows("SELECT id, owner_id FROM projects ORDER BY id"))
      .to eq([ { "id" => shop, "owner_id" => ana }, { "id" => blog, "owner_id" => ana } ])
  end

  it "restores owner_id from the first owner for a project in a non-personal organization" do
    ana = insert_user("ana@x.io")
    bo = insert_user("bo@x.io")
    project = insert_project("Shop", ana)
    migrate(MoveProjectsToOrganizations, :up)

    team = conn.insert("INSERT INTO organizations (name, slug, personal, created_at, updated_at) " \
                       "VALUES ('Team', 'team', 0, '2026-10-02', '2026-10-02')")
    conn.execute("INSERT INTO memberships (organization_id, user_id, role, created_at, updated_at) VALUES " \
                 "(#{team}, #{ana}, 'admin', '2026-10-02', '2026-10-02'), " \
                 "(#{team}, #{bo}, 'owner', '2026-10-02', '2026-10-02')")
    conn.execute("UPDATE projects SET organization_id = #{team} WHERE id = #{project}")

    migrate(MoveProjectsToOrganizations, :down)

    expect(rows("SELECT owner_id FROM projects")).to eq([ { "owner_id" => bo } ])
  end
end
