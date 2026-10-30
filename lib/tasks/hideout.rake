require "securerandom"

# First-run and admin commands for headless installs (spec 2026-10-29 §5.4).
# They print secrets to stdout only, never to the Rails log.
namespace :hideout do
  # On a terminal, ask instead of taking PASSWORD= (shell history, ps). Scripts keep PASSWORD= or get one generated,
  # and so does a tty with no console device.
  prompt_password = lambda do
    next unless $stdin.tty?

    require "io/console"
    console = IO.console
    next unless console

    first = console.getpass("Password for #{ENV['EMAIL']}: ")
    second = console.getpass("Same password again: ")
    abort("hideout:setup: the passwords did not match") unless first == second
    first.presence
  end

  desc "Create the first admin, organization, project and CI token (EMAIL= ORG= PROJECT= [PASSWORD=])"
  task setup: :environment do
    raise InstanceSetup::AlreadyDone unless InstanceSetup.pending?

    password = ENV["PASSWORD"].presence || prompt_password.call
    generated = password.nil?
    password ||= SecureRandom.alphanumeric(20)
    setup = InstanceSetup.new(email_address: ENV["EMAIL"], password: password, password_confirmation: password,
                              organization_name: ENV["ORG"], project_name: ENV["PROJECT"])
    result = setup.save
    abort("hideout:setup: #{setup.errors.full_messages.to_sentence}") unless result

    puts "password: #{password}" if generated
    puts "RAIDER_ENDPOINT=#{Hideout.base_url}"
    puts "RAIDER_TOKEN=#{result.token}"
  rescue InstanceSetup::AlreadyDone
    abort("hideout:setup: users already exist")
  end

  desc "Create another CI upload token for a project (PROJECT=<slug> [NAME=CI])"
  task token: :environment do
    slug = ENV["PROJECT"].presence || abort("Usage: bin/rails hideout:token PROJECT=<slug> [NAME=CI]")
    project = Project.find_by(slug: slug) || abort("hideout:token: no project with slug #{slug}")
    _token, plaintext = ApiToken.issue!(project: project, name: ENV["NAME"].presence || "CI")
    puts "RAIDER_TOKEN=#{plaintext}"
  end

  desc "Print a password reset link for a user, for servers without email (EMAIL=)"
  task password_link: :environment do
    email = ENV["EMAIL"].to_s.strip.presence || abort("Usage: bin/rails hideout:password_link EMAIL=<address>")
    user = User.find_by(email_address: email.downcase) || abort("hideout:password_link: no user with email #{email}")
    path = Rails.application.routes.url_helpers.edit_password_path(token: user.password_reset_token)
    puts "#{Hideout.base_url}#{path}"
  end
end
