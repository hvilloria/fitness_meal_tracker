require "rails_helper"

RSpec.describe ProgressSummary, type: :model do
  let(:user) { create(:user, day_cutoff_hour: 4) }
  # Wednesday: leaves both earlier days (Mon/Tue) and later days (Thu..Sun)
  # in the same calendar week to exercise both halves of the week logic.
  let(:today) { Date.new(2026, 9, 16) }
  let(:monday) { Date.new(2026, 9, 14) }
  let(:tuesday) { Date.new(2026, 9, 15) }

  def log_day(date, goal:, kcal:)
    day_log = create(:day_log, user: user, goal: goal, date: date)
    # Ad-hoc entries derive kcal from typed macros (4 kcal/g protein), so
    # protein_g = kcal / 4 lands the entry's kcal exactly on the value the
    # test asks for without coupling every test to the 4/4/9 formula itself.
    create(:entry, :ad_hoc, day_log: day_log, protein_g: kcal / 4.0, carbs_g: 0, fat_g: 0)
    day_log
  end

  describe "week arithmetic" do
    it "sums each logged day's own goal, not today's goal times seven" do
      old_goal = create(:goal, user: user, is_default: false, protein_g: 100, carbs_g: 100, fat_g: 20) # kcal 980
      new_goal = create(:goal, user: user, is_default: true, protein_g: 150, carbs_g: 150, fat_g: 50) # kcal 1650
      log_day(monday, goal: old_goal, kcal: 500)
      log_day(today, goal: new_goal, kcal: 500)

      summary = ProgressSummary.new(user, today: today)

      expect(summary.week_budget).to eq(980 + 1650)
      expect(summary.week_consumed).to eq(1000)
      expect(summary.week_remaining).to eq(980 + 1650 - 1000)
    end

    it "excludes an unlogged day from both sides of the balance" do
      goal = create(:goal, user: user, is_default: true, protein_g: 500, carbs_g: 0, fat_g: 0) # kcal 2000
      log_day(monday, goal: goal, kcal: 1000)
      # A day_log row exists (as it would after simply opening the app) but
      # has no entries — it must still count as unlogged, not as "ate zero".
      create(:day_log, user: user, goal: goal, date: tuesday)

      summary = ProgressSummary.new(user, today: today)

      expect(summary.week_logged_count).to eq(1)
      expect(summary.week_total_days).to eq(7)
      expect(summary.week_budget).to eq(2000)
      expect(summary.week_consumed).to eq(1000)
    end

    it "renders a negative remaining balance rather than clamping at zero" do
      goal = create(:goal, user: user, is_default: true, protein_g: 250, carbs_g: 0, fat_g: 0) # kcal 1000
      log_day(monday, goal: goal, kcal: 1500)

      summary = ProgressSummary.new(user, today: today)

      expect(summary.week_remaining).to eq(-500)
    end

    it "lists only the days still ahead, leaving today to the Hoy tab" do
      goal = create(:goal, user: user, is_default: true)
      log_day(monday, goal: goal, kcal: 100)

      summary = ProgressSummary.new(user, today: today)

      expect(summary.week_upcoming_label).to eq("jueves, viernes, sábado y domingo")
    end
  end

  describe "month averages" do
    it "averages only over logged days" do
      goal_a = create(:goal, user: user, is_default: false, protein_g: 500, carbs_g: 0, fat_g: 0) # kcal 2000
      goal_b = create(:goal, user: user, is_default: true, protein_g: 750, carbs_g: 0, fat_g: 0) # kcal 3000
      log_day(Date.new(2026, 9, 1), goal: goal_a, kcal: 1800)
      log_day(Date.new(2026, 9, 10), goal: goal_b, kcal: 3200)
      # An unlogged day_log row in between must not drag the average toward
      # zero.
      create(:day_log, user: user, goal: goal_b, date: Date.new(2026, 9, 5))

      summary = ProgressSummary.new(user, today: today)

      expect(summary.month_logged_count).to eq(2)
      expect(summary.month_average_kcal).to eq((1800 + 3200) / 2.0)
      expect(summary.month_average_goal_kcal).to eq((2000 + 3000) / 2.0)
    end
  end

  describe "#month_on_target_count" do
    it "counts a day inside +/-10% of its own goal and excludes one outside it" do
      goal = create(:goal, user: user, is_default: true, protein_g: 250, carbs_g: 0, fat_g: 0) # kcal 1000
      log_day(Date.new(2026, 9, 1), goal: goal, kcal: 1100) # exactly +10%: on target
      log_day(Date.new(2026, 9, 2), goal: goal, kcal: 1150) # outside: not on target

      summary = ProgressSummary.new(user, today: today)

      expect(summary.month_on_target_count).to eq(1)
    end
  end

  describe "empty states" do
    it "reports empty week and month for a user with no logged days at all" do
      create(:goal, user: user, is_default: true)

      summary = ProgressSummary.new(user, today: today)

      expect(summary.week_empty?).to be(true)
      expect(summary.month_empty?).to be(true)
      expect(summary.week_remaining).to eq(0)
      expect(summary.month_average_kcal).to eq(0.0)
      expect(summary.month_on_target_count).to eq(0)
    end
  end
end
