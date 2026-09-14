require "rails_helper"

RSpec.describe "Sessions", type: :request do
  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ALLOWED_EMAILS").and_return("a@example.com")
  end

  it "signs in an allowed user and redirects to the day" do
    create(:user) # unrelated user already in the table; must not affect which id lands in the session
    user = sign_in_via_google(email: "a@example.com")

    expect(response).to redirect_to(root_path)
    expect(session[:user_id]).to eq(user.id)
  end

  it "refuses a disallowed user" do
    sign_in_via_google(email: "intruder@example.com")

    expect(session[:user_id]).to be_nil
    expect(response).to redirect_to(sign_in_path)
    expect(flash[:alert]).to be_present
  end

  it "signs out" do
    sign_in_via_google(email: "a@example.com")
    delete sign_out_path

    expect(session[:user_id]).to be_nil
  end

  it "redirects an anonymous visitor to the sign-in page" do
    get root_path

    expect(response).to redirect_to(sign_in_path)
  end

  it "renders the sign-in page without a session" do
    get sign_in_path

    expect(response).to have_http_status(:ok)
  end

  # Turbo would submit this form with fetch(), which follows the redirect to
  # accounts.google.com and dies on CORS. Only a full navigation works.
  it "opts the sign-in button out of Turbo" do
    get sign_in_path

    expect(response.body).to match(/<form[^>]*data-turbo="false"/)
  end

  it "does not blow up on a callback with no omniauth data" do
    # No sign_in_via_google call, so OmniAuth.config.mock_auth is empty and
    # the callback reaches the controller with omniauth.auth set to nil.
    get "/auth/google_oauth2/callback"

    expect(response).to redirect_to(sign_in_path)
    expect(flash[:alert]).to be_present
  end

  it "404s on a callback for a provider other than google_oauth2" do
    get "/auth/other_provider/callback"

    expect(response).to have_http_status(:not_found)
  end
end
