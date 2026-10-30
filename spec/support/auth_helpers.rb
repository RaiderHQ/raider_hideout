module AuthHelpers
  def sign_in(user, password: "password123")
    post session_path, params: { email_address: user.email_address, password: password }
  end
end

RSpec.configure { |c| c.include AuthHelpers, type: :request }
