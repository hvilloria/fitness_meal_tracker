OmniAuth.config.test_mode = true

module OmniAuthHelpers
  def sign_in_via_google(email:, name: "Hosward", uid: "uid-1")
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: uid,
      info: { email: email, name: name, image: "http://example.com/a.jpg" }
    )
    get "/auth/google_oauth2/callback"
    User.find_by(provider: "google_oauth2", uid: uid)
  end
end

RSpec.configure do |config|
  config.include OmniAuthHelpers, type: :request
  config.before { OmniAuth.config.mock_auth.clear }
end
