require "rails_helper"

RSpec.describe "Goals", type: :request do
  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ALLOWED_EMAILS").and_return("a@example.com")
  end

  let(:user) { sign_in_via_google(email: "a@example.com") }

  it "seeds a first goal at 25/50/25 from a calorie figure" do
    user
    get edit_goal_path, params: { kcal: 2500 }

    expect(response.body).to include("156")
    expect(response.body).to include("313")
    expect(response.body).to include("69")
  end

  it "starts blank when no calorie figure is given" do
    user
    get edit_goal_path

    expect(response).to have_http_status(:ok)
  end

  it "creates the goal on first save and marks it default" do
    user

    expect {
      patch goal_path, params: { goal: { label: "Día normal", protein_g: 180, carbs_g: 220, fat_g: 78 } }
    }.to change(Goal, :count).by(1)

    goal = user.default_goal
    expect(goal.kcal).to eq(2302)
    expect(goal.is_default).to be(true)
  end

  it "updates the existing goal in place rather than versioning on every edit" do
    user
    patch goal_path, params: { goal: { label: "Día normal", protein_g: 180, carbs_g: 220, fat_g: 78 } }

    expect {
      patch goal_path, params: { goal: { label: "Día normal", protein_g: 190, carbs_g: 220, fat_g: 78 } }
    }.not_to change(Goal, :count)

    expect(user.default_goal.kcal).to eq(2342)
  end

  it "re-renders when the macros are invalid" do
    user
    patch goal_path, params: { goal: { label: "", protein_g: -5 } }

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "redirects to the day after saving" do
    user
    patch goal_path, params: { goal: { label: "Día normal", protein_g: 180, carbs_g: 220, fat_g: 78 } }

    expect(response).to redirect_to(root_path)
  end
end
