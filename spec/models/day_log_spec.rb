require "rails_helper"

RSpec.describe DayLog, type: :model do
  let(:user) { create(:user, day_cutoff_hour: 4) }
  let!(:goal) { create(:goal, user: user, is_default: true) }

  it { is_expected.to belong_to(:user) }
  it { is_expected.to belong_to(:goal) }

  describe ".logical_date" do
    it "counts 01:00 as the previous day" do
      time = Time.zone.local(2026, 9, 14, 1, 0)

      expect(DayLog.logical_date(user, time)).to eq(Date.new(2026, 9, 13))
    end

    it "counts 03:59 as the previous day" do
      time = Time.zone.local(2026, 9, 14, 3, 59)

      expect(DayLog.logical_date(user, time)).to eq(Date.new(2026, 9, 13))
    end

    it "counts 04:00 as the current day" do
      time = Time.zone.local(2026, 9, 14, 4, 0)

      expect(DayLog.logical_date(user, time)).to eq(Date.new(2026, 9, 14))
    end

    it "counts 23:00 as the current day" do
      time = Time.zone.local(2026, 9, 14, 23, 0)

      expect(DayLog.logical_date(user, time)).to eq(Date.new(2026, 9, 14))
    end

    it "honours a different cutoff hour" do
      midnight_user = create(:user, day_cutoff_hour: 0)
      time = Time.zone.local(2026, 9, 14, 1, 0)

      expect(DayLog.logical_date(midnight_user, time)).to eq(Date.new(2026, 9, 14))
    end
  end

  describe ".for" do
    it "creates the day and copies the user's default goal" do
      travel_to Time.zone.local(2026, 9, 14, 10, 0) do
        day_log = DayLog.for(user)

        expect(day_log.date).to eq(Date.new(2026, 9, 14))
        expect(day_log.goal).to eq(goal)
      end
    end

    it "returns the same record on a second call" do
      travel_to Time.zone.local(2026, 9, 14, 10, 0) do
        expect { 2.times { DayLog.for(user) } }.to change(DayLog, :count).by(1)
      end
    end

    it "keeps the goal that was in force even after the default changes" do
      travel_to Time.zone.local(2026, 9, 14, 10, 0) do
        day_log = DayLog.for(user)
        create(:goal, user: user, is_default: true, label: "Nueva")

        expect(day_log.reload.goal).to eq(goal)
      end
    end

    it "raises when the user has no default goal" do
      goal.update!(is_default: false)

      expect { DayLog.for(user) }.to raise_error(DayLog::MissingGoal)
    end
  end

  it "allows only one day log per user and date" do
    create(:day_log, user: user, goal: goal, date: Date.new(2026, 9, 14))
    duplicate = build(:day_log, user: user, goal: goal, date: Date.new(2026, 9, 14))

    expect(duplicate).not_to be_valid
  end
end
