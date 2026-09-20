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

  it "budgets the week's full seven days, each against its own goal" do
    sign_in
    travel_to Time.zone.local(2026, 9, 16, 10, 0) do
      old_goal = create(:goal, user: @user, is_default: false, protein_g: 100, carbs_g: 100, fat_g: 20) # kcal 980
      new_goal = create(:goal, user: @user, is_default: true, protein_g: 150, carbs_g: 150, fat_g: 50) # kcal 1650
      log_day(Date.new(2026, 9, 14), goal: old_goal, kcal: 500) # Monday, under the old (non-default) goal
      log_day(Date.new(2026, 9, 16), goal: new_goal, kcal: 500) # Wednesday (today), under the new goal

      get progress_path

      # Monday's own goal of 980, plus the other six days of the week at the
      # current default of 1650 (Wednesday's own goal happens to match it):
      # 980 + 1650 * 6 = 10.880 -- not 1650 * 7 = 11.550, which is what an
      # implementation that used the current default for every day, ignoring
      # goal versioning, would show instead.
      expect(response.body).to include("10.880")
      expect(response.body).not_to include("11.550")
    end
  end

  it "shows a negative remaining balance rather than clamping it at zero" do
    sign_in
    travel_to Time.zone.local(2026, 9, 16, 10, 0) do
      goal = create(:goal, user: @user, is_default: true, protein_g: 25, carbs_g: 0, fat_g: 0) # kcal 100
      log_day(Date.new(2026, 9, 16), goal: goal, kcal: 1000) # week budget: 100 * 7 = 700

      get progress_path

      expect(response.body).to include("300")
      expect(response.body).to include("kcal excedidas")
      expect(response.body).to include("negative")
    end
  end

  it "still says 'kcal restantes' in the week card under the goal" do
    sign_in
    travel_to Time.zone.local(2026, 9, 16, 10, 0) do
      goal = create(:goal, user: @user, is_default: true)
      log_day(Date.new(2026, 9, 16), goal: goal, kcal: 100)

      get progress_path

      expect(response.body).to include("kcal restantes")
    end
  end

  it "states how many of the week's days the balance is based on" do
    sign_in
    travel_to Time.zone.local(2026, 9, 16, 10, 0) do
      goal = create(:goal, user: @user, is_default: true)
      log_day(Date.new(2026, 9, 14), goal: goal, kcal: 100)

      get progress_path

      expect(response.body).to include("Registrados 1 de 7 días.")
    end
  end

  it "shows weekly macro totals as consumed over the week's own-goal sum" do
    sign_in
    travel_to Time.zone.local(2026, 9, 16, 10, 0) do
      goal = create(:goal, user: @user, is_default: true, protein_g: 100, carbs_g: 200, fat_g: 50)
      day_log = create(:day_log, user: @user, goal: goal, date: Date.new(2026, 9, 16))
      create(:entry, :ad_hoc, day_log: day_log, protein_g: 40, carbs_g: 60, fat_g: 10)

      get progress_path

      expect(response.body).to include("Macros de la semana")
      expect(response.body).to include("40")
      expect(response.body).to include("700") # protein goal: 100 * 7
      expect(response.body).to include("60")
      expect(response.body).to include("1400") # carbs goal: 200 * 7
      expect(response.body).to include("10")
      expect(response.body).to include("350") # fat goal: 50 * 7
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
      # 1 (current_user) + 4 for the week (day_logs, their goals, grouped
      # entry sums, and the user's default goal — fetched once, not once
      # per unlogged day, for the days that fall back to it) + 3 for the
      # month (day_logs, their goals, grouped entry sums) — flat regardless
      # of how many of the 30 days are logged, never one query per day.
      expect(query_count).to eq(8)
    end
  end
end
