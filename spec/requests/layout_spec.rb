require "rails_helper"

RSpec.describe "Layout", type: :request do
  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ALLOWED_EMAILS").and_return("a@example.com")
  end

  it "hides the navigation from an anonymous visitor" do
    get sign_in_path

    expect(response.body).not_to include("Salir")
  end

  it "shows the navigation to a signed-in user" do
    user = sign_in_via_google(email: "a@example.com")
    create(:goal, user: user, is_default: true)

    get root_path

    expect(response.body).to include("Salir")
    expect(response.body).to include("Meta")
  end
end
