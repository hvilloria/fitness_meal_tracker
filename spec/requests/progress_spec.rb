require "rails_helper"

RSpec.describe "Progress", type: :request do
  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ALLOWED_EMAILS").and_return("a@example.com")
  end

  def sign_in
    @user = sign_in_via_google(email: "a@example.com")
  end

  def log_day(date, goal:, kcal:)
    day_log = create(:day_log, user: @user, goal: goal, date: date)
    create(:entry, :ad_hoc, day_log: day_log, protein_g: kcal / 4.0, carbs_g: 0, fat_g: 0)
    day_log
  end

  it "shows a friendly empty state instead of a blank screen or an error" do
    sign_in

    get progress_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Todavía no registraste ningún día esta semana.")
    expect(response.body).to include("Todavía no registraste ningún día este mes.")
  end

  it "sums each logged day's own goal into the week budget" do
    sign_in
    travel_to Time.zone.local(2026, 9, 16, 10, 0) do
      old_goal = create(:goal, user: @user, is_default: false, protein_g: 100, carbs_g: 100, fat_g: 20) # kcal 980
      new_goal = create(:goal, user: @user, is_default: true, protein_g: 150, carbs_g: 150, fat_g: 50) # kcal 1650
      log_day(Date.new(2026, 9, 14), goal: old_goal, kcal: 500) # Monday, under the old goal
      log_day(Date.new(2026, 9, 16), goal: new_goal, kcal: 500) # Wednesday (today), under the new goal

      get progress_path

      expect(response.body).to include("2.630") # 980 + 1650
    end
  end

  it "shows a negative remaining balance rather than clamping it at zero" do
    sign_in
    travel_to Time.zone.local(2026, 9, 16, 10, 0) do
      goal = create(:goal, user: @user, is_default: true, protein_g: 250, carbs_g: 0, fat_g: 0) # kcal 1000
      log_day(Date.new(2026, 9, 16), goal: goal, kcal: 1500)

      get progress_path

      expect(response.body).to include("-500")
      expect(response.body).to include("negative")
    end
  end

  it "states how many of the week's days the balance is based on" do
    sign_in
    travel_to Time.zone.local(2026, 9, 16, 10, 0) do
      goal = create(:goal, user: @user, is_default: true)
      log_day(Date.new(2026, 9, 14), goal: goal, kcal: 100)

      get progress_path

      expect(response.body).to include("Sobre 1 de 7 días registrados.")
    end
  end

  it "labels the +/-10% on-target convention in the UI" do
    sign_in
    travel_to Time.zone.local(2026, 9, 16, 10, 0) do
      goal = create(:goal, user: @user, is_default: true)
      log_day(Date.new(2026, 9, 1), goal: goal, kcal: 100)

      get progress_path

      expect(response.body).to include("±10%")
    end
  end

  it "shows the fourth tab in the bottom bar" do
    sign_in

    get progress_path

    expect(response.body).to include(">Progreso<")
  end

  it "does not issue a query per logged day when building the month view" do
    sign_in
    travel_to Time.zone.local(2026, 9, 30, 10, 0) do
      goal = create(:goal, user: @user, is_default: true, protein_g: 250, carbs_g: 0, fat_g: 0)
      30.times { |i| log_day(Date.new(2026, 9, i + 1), goal: goal, kcal: 900) }

      query_count = 0
      counter = ->(*, payload) { query_count += 1 unless payload[:sql].match?(/\A(BEGIN|COMMIT|SAVEPOINT|RELEASE)/) }

      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { get progress_path }

      expect(response).to have_http_status(:ok)
      # 1 (current_user) + 3 per section (day_logs, their goals, grouped
      # entry sums) for the week and 3 more for the month — flat regardless
      # of how many of the 30 days are logged, never one query per day.
      expect(query_count).to eq(7)
    end
  end
end
