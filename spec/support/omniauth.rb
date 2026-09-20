OmniAuth.config.test_mode = true

module OmniAuthHelpers
  # uid must NOT match the :user factory's `uid-#{n}` sequence pattern — the
  # factory's first record also produces "uid-1", and colliding on the
  # (provider, uid) unique index raises PG::UniqueViolation whenever a spec
  # signs in and separately creates a factory user (e.g. via an association).
  def sign_in_via_google(email:, name: "Hosward", uid: "signed-in-user")
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
