require "rails_helper"
require "rake"

RSpec.describe "hideout rake tasks" do
  include LogCapture

  before(:all) { Rails.application.load_tasks if Rake::Task.tasks.none? { |t| t.name == "hideout:setup" } }

  def run(name, env)
    with_env(env)
    Rake::Task[name].execute
  end

  def exits_with(message)
    raise_error(SystemExit) { |error| expect(error.status).to eq(1) }.and output(message).to_stderr
  end

  describe "hideout:setup" do
    let(:env) do
      { "EMAIL" => "admin@example.com", "ORG" => "Acme QA", "PROJECT" => "Checkout", "PASSWORD" => "password123",
        "APP_HOST" => "localhost:3010" }
    end

    it "creates the instance and prints the CI settings" do
      expect { run("hideout:setup", env) }
        .to output(%r{\ARAIDER_ENDPOINT=http://localhost:3010\nRAIDER_TOKEN=rdr_\S+\n\z}).to_stdout
      expect(User.find_by!(email_address: "admin@example.com").organizations.pluck(:name)).to include("Acme QA")
    end

    it "generates and prints a password when none is given and there is no terminal" do
      allow($stdin).to receive(:tty?).and_return(false)
      out = capture_stdout { run("hideout:setup", env.except("PASSWORD")) }
      password = out[/\Apassword: ([A-Za-z0-9]{20})\n/, 1]
      expect(User.authenticate_by(email_address: "admin@example.com", password: password)).to be_present
    end

    it "exits 1 when users already exist" do
      create(:user)
      expect { run("hideout:setup", env) }.to exits_with("hideout:setup: users already exist\n")
    end

    it "refuses before asking for a password when users already exist" do
      create(:user)
      allow($stdin).to receive(:tty?).and_return(true)
      allow(IO).to receive(:console).and_call_original
      expect { run("hideout:setup", env.except("PASSWORD")) }.to exits_with("hideout:setup: users already exist\n")
      expect(IO).not_to have_received(:console)
    end

    it "asks twice on a terminal and uses the password typed" do
      console = instance_double(IO)
      allow($stdin).to receive(:tty?).and_return(true)
      allow(IO).to receive(:console).and_return(console)
      allow(console).to receive(:getpass).and_return("typed-password-1")
      out = capture_stdout { run("hideout:setup", env.except("PASSWORD")) }
      expect(out).not_to include("password:")
      expect(console).to have_received(:getpass).twice
      expect(User.authenticate_by(email_address: "admin@example.com", password: "typed-password-1")).to be_present
    end

    it "generates a password when stdin is a tty but there is no console" do
      allow($stdin).to receive(:tty?).and_return(true)
      allow(IO).to receive(:console).and_return(nil)
      out = capture_stdout { run("hideout:setup", env.except("PASSWORD")) }
      expect(out).to match(/\Apassword: [A-Za-z0-9]{20}\n/)
    end

    it "exits 1 with the validation messages" do
      expect { run("hideout:setup", env.except("ORG")) }.to exits_with(/hideout:setup: Organization name can't be blank/)
    end

    it "keeps the password and the token out of the log" do
      out = nil
      log = capture_log { out = capture_stdout { run("hideout:setup", env) } }
      expect(log).not_to include("password123")
      expect(log).not_to include(out[/RAIDER_TOKEN=(\S+)/, 1])
    end
  end

  describe "hideout:token" do
    let(:project) { create(:project) }

    it "prints a new upload token for the project" do
      out = capture_stdout { run("hideout:token", "PROJECT" => project.slug, "NAME" => "nightly") }
      token = ApiToken.authenticate(out[/\ARAIDER_TOKEN=(\S+)\n\z/, 1])
      expect([ token.project, token.name ]).to eq([ project, "nightly" ])
    end

    it "exits 1 for an unknown project or a missing slug" do
      expect { run("hideout:token", "PROJECT" => "nope") }.to exits_with("hideout:token: no project with slug nope\n")
      expect { run("hideout:token", "PROJECT" => nil) }.to exits_with(/Usage: bin\/rails hideout:token PROJECT=<slug>/)
    end
  end

  describe "hideout:password_link" do
    it "prints a reset link that works" do
      user = create(:user, email_address: "dev@example.com")
      out = capture_stdout { run("hideout:password_link", "EMAIL" => " DEV@example.com ", "APP_HOST" => "localhost:3010") }
      url = URI(out.chomp)
      expect("#{url.scheme}://#{url.host}:#{url.port}#{url.path}").to eq("http://localhost:3010/passwords/edit")
      expect(User.find_by_password_reset_token(Rack::Utils.parse_query(url.query)["token"])).to eq(user)
    end

    it "exits 1 for an unknown email" do
      expect { run("hideout:password_link", "EMAIL" => "nobody@example.com") }
        .to exits_with("hideout:password_link: no user with email nobody@example.com\n")
    end
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end
