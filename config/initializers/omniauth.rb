Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2,
    ENV["GOOGLE_CLIENT_ID"],
    ENV["GOOGLE_CLIENT_SECRET"],
    scope: "email,profile"
end

# omniauth-rails_csrf_protection requires the request phase to be a POST.
OmniAuth.config.allowed_request_methods = [ :post ]
