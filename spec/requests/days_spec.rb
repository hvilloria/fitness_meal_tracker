require "rails_helper"

RSpec.describe "Days", type: :request do
  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ALLOWED_EMAILS").and_return("a@example.com")
  end

  def sign_in
    @user = sign_in_via_google(email: "a@example.com")
  end

  it "redirects to the goal form when the user has no default goal" do
    sign_in

    get root_path

    expect(response).to redirect_to(edit_goal_path)
    expect(flash[:notice]).to be_present
  end

  it "shows the day and creates it for a user with a default goal" do
    create(:user) # unrelated user already in the table; must not affect whose goal is picked up
    sign_in
    create(:goal, user: @user, is_default: true)

    expect { get root_path }.to change(DayLog, :count).by(1)

    expect(response).to have_http_status(:ok)
  end

  it "renders the requested date instead of today" do
    sign_in
    create(:goal, user: @user, is_default: true)

    get root_path, params: { date: "2026-09-01" }

    expect(response.body).to include("2026-09-01")
  end

  describe "hostile date params fall back to today instead of erroring" do
    before do
      sign_in
      create(:goal, user: @user, is_default: true)
    end

    it "handles an array param" do
      get root_path, params: { date: [ "x" ] }

      expect(response).to have_http_status(:ok)
    end

    it "handles a hash param" do
      get root_path, params: { date: { k: "v" } }

      expect(response).to have_http_status(:ok)
    end

    it "handles an over-long string" do
      get root_path, params: { date: "a" * 200 }

      expect(response).to have_http_status(:ok)
    end

    it "handles plain garbage" do
      get root_path, params: { date: "notadate" }

      expect(response).to have_http_status(:ok)
    end
  end

  it "labels the prev/next day links for screen readers" do
    sign_in
    create(:goal, user: @user, is_default: true)

    get root_path

    expect(response.body).to include('aria-label="Día anterior"')
    expect(response.body).to include('aria-label="Día siguiente"')
  end

  it "recovers when DayLog.for loses a create race" do
    user = create(:user, day_cutoff_hour: 4)
    goal = create(:goal, user: user, is_default: true)

    travel_to Time.zone.local(2026, 9, 14, 10, 0) do
      date = DayLog.logical_date(user, Time.current)
      # Simulate another request winning the race: the row exists by the
      # time we insert, so our find_by "misses" once before the create.
      existing = create(:day_log, user: user, goal: goal, date: date)
      day_logs = user.day_logs
      allow(user).to receive(:day_logs).and_return(day_logs)
      allow(day_logs).to receive(:find_by).with(date: date).and_return(nil)
      allow(day_logs).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique)
      allow(day_logs).to receive(:find_by!).with(date: date).and_return(existing)

      expect(DayLog.for(user)).to eq(existing)
    end
  end

  describe "the dashboard" do
    def user = @user

    before do
      sign_in
    end

    it "shows the goal total" do
      goal = create(:goal, user: @user, is_default: true, protein_g: 156, carbs_g: 313, fat_g: 69)

      get root_path

      expect(response.body).to include(goal.kcal.to_s)
    end

    it "groups entries under their meal" do
      create(:goal, user: @user, is_default: true, protein_g: 156, carbs_g: 313, fat_g: 69)
      food = create(:food, user: user, name: "Pechuga de pollo")
      post entries_path, params: { entry: { food_id: food.id, meal: "lunch", grams: 190 } }

      get root_path

      expect(response.body).to include("Almuerzo")
      expect(response.body).to include("Pechuga de pollo")
    end

    it "computes totals and remaining once each instead of once per ring" do
      create(:goal, user: @user, is_default: true, protein_g: 156, carbs_g: 313, fat_g: 69)
      food = create(:food, user: user, kcal_per_100: 100, protein_per_100: 10, carbs_per_100: 10, fat_per_100: 1)
      post entries_path, params: { entry: { food_id: food.id, meal: "lunch", grams: 100 } }

      sum_queries = 0
      counter = ->(*, payload) { sum_queries += 1 if payload[:sql].include?("SUM(") }

      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { get root_path }

      # One for the totals local, one more inside #remaining (which calls
      # #totals again internally) — down from 6, since #totals/#remaining
      # are deliberately not memoised on the model (see DayLog#totals).
      expect(sum_queries).to eq(2)
    end

    it "shows the real overage under 'kcal excedidas' rather than clamping at zero" do
      create(:goal, user: @user, is_default: true, protein_g: 156, carbs_g: 313, fat_g: 69) # kcal 2497
      food = create(:food, user: user, kcal_per_100: 1000, protein_per_100: 0, carbs_per_100: 0, fat_per_100: 0)
      post entries_path, params: { entry: { food_id: food.id, meal: "dinner", grams: 1000 } } # 10000 kcal

      get root_path

      expect(response.body).to include("7503") # |2497 - 10000|, never clamped at zero
      expect(response.body).to include("kcal excedidas")
      expect(response.body).to include("negative")
    end

    it "still says 'kcal restantes' under the goal" do
      create(:goal, user: @user, is_default: true, protein_g: 156, carbs_g: 313, fat_g: 69)

      get root_path

      expect(response.body).to include("kcal restantes")
    end
  end
end
