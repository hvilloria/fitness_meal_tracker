require "rails_helper"

RSpec.describe "Sessions", type: :request do
  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ALLOWED_EMAILS").and_return("a@example.com")
  end

  it "signs in an allowed user and redirects to the day" do
    sign_in_via_google(email: "a@example.com")

    expect(response).to redirect_to(root_path)
    expect(session[:user_id]).to eq(User.last.id)
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
end
