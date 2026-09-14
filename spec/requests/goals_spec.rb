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

  it "renders no name field, since there is only ever one goal" do
    user
    get edit_goal_path

    expect(response.body).not_to include("goal_label")
    expect(response.body).not_to include("Nombre")
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
      patch goal_path, params: { goal: { protein_g: 180, carbs_g: 220, fat_g: 78 } }
    }.to change(Goal, :count).by(1)

    goal = user.default_goal
    expect(goal.kcal).to eq(2302)
    expect(goal.is_default).to be(true)
  end

  it "versions the goal on every edit instead of updating it in place" do
    user
    patch goal_path, params: { goal: { protein_g: 180, carbs_g: 220, fat_g: 78 } }
    first = user.default_goal

    expect {
      patch goal_path, params: { goal: { protein_g: 190, carbs_g: 220, fat_g: 78 } }
    }.to change(Goal, :count).by(1)

    expect(first.reload.protein_g).to eq(180)
    expect(first.is_default).to be(false)
    expect(user.default_goal.kcal).to eq(2342)
  end

  it "does not create a new row when the submitted macros match the current default" do
    user
    patch goal_path, params: { goal: { protein_g: 180, carbs_g: 220, fat_g: 78 } }

    expect {
      patch goal_path, params: { goal: { protein_g: 180, carbs_g: 220, fat_g: 78 } }
    }.not_to change(Goal, :count)
  end

  it "leaves a day logged before the edit pointing at the old goal" do
    user
    patch goal_path, params: { goal: { protein_g: 180, carbs_g: 220, fat_g: 78 } }

    travel_to 2.days.ago do
      DayLog.for(user)
    end
    past_log = user.day_logs.find_by(date: DayLog.logical_date(user, 2.days.ago))

    patch goal_path, params: { goal: { protein_g: 190, carbs_g: 220, fat_g: 78 } }

    expect(past_log.reload.goal.kcal).to eq(2302)
  end

  it "re-points today's day log at the new version" do
    user
    patch goal_path, params: { goal: { protein_g: 180, carbs_g: 220, fat_g: 78 } }
    today_log = DayLog.for(user)

    patch goal_path, params: { goal: { protein_g: 190, carbs_g: 220, fat_g: 78 } }

    expect(today_log.reload.goal).to eq(user.default_goal)
    expect(today_log.goal.protein_g).to eq(190)
  end

  it "accepts a comma as the decimal separator for a macro" do
    user

    patch goal_path, params: { goal: { protein_g: "180,5", carbs_g: 220, fat_g: 78 } }

    expect(response).to redirect_to(root_path)
    expect(user.default_goal.protein_g).to eq(180)
  end

  it "re-renders when the macros are invalid" do
    user
    patch goal_path, params: { goal: { protein_g: -5 } }

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "recovers when two concurrent first-saves race on the default-goal unique index" do
    user

    # Simulate the loser of a double-tap: our own read finds no default
    # goal, but by the time we insert one, a concurrent request has already
    # created and saved a default with different macros. The loser must
    # still end up versioned off whatever is now the default, not mutate it.
    winner = create(:goal, user: user, is_default: true, protein_g: 180, carbs_g: 220, fat_g: 78)

    allow(User).to receive(:find_by).and_call_original
    allow(User).to receive(:find_by).with(id: user.id).and_return(user)

    # Our own read finds no default (it ran before the winner's insert
    # committed); only the first insert we attempt should fail the race.
    allow(user).to receive(:default_goal).and_return(nil)

    build_count = 0
    allow(user.goals).to receive(:build).and_wrap_original do |method, *args, &block|
      goal = method.call(*args, &block)
      build_count += 1
      allow(goal).to receive(:save).and_raise(ActiveRecord::RecordNotUnique) if build_count == 1
      goal
    end

    patch goal_path, params: { goal: { protein_g: 190, carbs_g: 220, fat_g: 78 } }

    expect(response).to redirect_to(root_path)
    expect(winner.reload.protein_g).to eq(180)
    expect(winner.is_default).to be(false)
    expect(Goal.find_by(user: user, is_default: true).protein_g).to eq(190)
  end

  it "does not 500 when the goal param arrives as a bare scalar" do
    user
    patch goal_path, params: { goal: "boom" }

    expect(response).to have_http_status(:bad_request)
  end

  it "redirects to the day after saving" do
    user
    patch goal_path, params: { goal: { protein_g: 180, carbs_g: 220, fat_g: 78 } }

    expect(response).to redirect_to(root_path)
  end
end
