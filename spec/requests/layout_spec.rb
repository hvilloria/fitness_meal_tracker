require "rails_helper"

RSpec.describe "Layout", type: :request do
  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ALLOWED_EMAILS").and_return("a@example.com")
  end

  it "hides the tab bar from an anonymous visitor" do
    get sign_in_path

    expect(response.body).not_to include("tabbar")
    expect(response.body).not_to include("Salir")
  end

  it "shows the three tabs to a signed-in user" do
    user = sign_in_via_google(email: "a@example.com")
    create(:goal, user: user, is_default: true)

    get root_path

    expect(response.body).to include('class="tabbar"')
    expect(response.body).to include(">Hoy<")
    expect(response.body).to include(">Alimentos<")
    expect(response.body).to include(">Meta<")
  end

  it "marks the tab of the screen being shown as the current page" do
    user = sign_in_via_google(email: "a@example.com")
    create(:goal, user: user, is_default: true)

    get foods_path

    expect(response.body).to include("tabbar__tab tabbar__tab--active")
    expect(response.body).to include('aria-current="page"')
  end

  it "keeps Salir out of the navigation and at the foot of the goal screen" do
    user = sign_in_via_google(email: "a@example.com")
    create(:goal, user: user, is_default: true)

    get root_path
    expect(response.body).not_to include("Salir")

    get edit_goal_path
    expect(response.body).to include("Salir")
  end
end
