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

  it "does not 500 on an array-shaped kcal query param" do
    user
    get edit_goal_path, params: { kcal: [ "x" ] }

    expect(response).to have_http_status(:ok)
  end

  it "does not 500 on a hash-shaped kcal query param" do
    user
    get edit_goal_path, params: { kcal: { a: 1 } }

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

  it "accepts a comma as the decimal separator for a macro" do
    user

    patch goal_path, params: { goal: { label: "Día normal", protein_g: "180,5", carbs_g: 220, fat_g: 78 } }

    expect(response).to redirect_to(root_path)
    expect(user.default_goal.protein_g).to eq(180)
  end

  it "re-renders when the macros are invalid" do
    user
    patch goal_path, params: { goal: { label: "", protein_g: -5 } }

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "joins multiple validation errors with the Spanish connector, not the English one" do
    user
    patch goal_path, params: { goal: { label: "", protein_g: -5 } }

    expect(response.body).to include(" y ")
    expect(response.body).not_to include(" and ")
  end

  it "recovers when two concurrent first-saves race on the default-goal unique index" do
    user

    # Simulate the loser of a double-tap: our own read finds no default
    # goal, but by the time we insert one, a concurrent request has already
    # created and saved the real default.
    winner = create(:goal, user: user, is_default: true, label: "Día normal", protein_g: 180, carbs_g: 220, fat_g: 78)

    allow(User).to receive(:find_by).and_call_original
    allow(User).to receive(:find_by).with(id: user.id).and_return(user)

    call_count = 0
    allow(user).to receive(:default_goal) do
      call_count += 1
      call_count == 1 ? nil : user.goals.find_by(is_default: true)
    end
    allow(user.goals).to receive(:build).and_wrap_original do |method, *args, &block|
      goal = method.call(*args, &block)
      allow(goal).to receive(:update).and_raise(ActiveRecord::RecordNotUnique)
      goal
    end

    patch goal_path, params: { goal: { label: "Día normal", protein_g: 190, carbs_g: 220, fat_g: 78 } }

    expect(response).to redirect_to(root_path)
    expect(winner.reload.protein_g).to eq(190)
  end

  it "does not 500 when the goal param arrives as a bare scalar" do
    user
    patch goal_path, params: { goal: "boom" }

    expect(response).to have_http_status(:bad_request)
  end

  it "redirects to the day after saving" do
    user
    patch goal_path, params: { goal: { label: "Día normal", protein_g: 180, carbs_g: 220, fat_g: 78 } }

    expect(response).to redirect_to(root_path)
  end
end
