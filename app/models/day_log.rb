class DayLog < ApplicationRecord
  # Raised rather than silently creating a day without a target to measure
  # against. The controller turns this into a redirect to the goal form.
  class MissingGoal < StandardError; end

  belongs_to :user
  belongs_to :goal
  has_many :entries, -> { order(:meal, :position) }, dependent: :destroy, inverse_of: :day_log

  validates :date, presence: true, uniqueness: { scope: :user_id }

  class << self
    # The day does not end at midnight: food logged at 01:00 belongs to the
    # evening before. Shifting back by the cutoff and taking the date does it.
    def logical_date(user, time = Time.current)
      (time.in_time_zone(Time.zone) - user.day_cutoff_hour.hours).to_date
    end

    def for(user, time = Time.current)
      date = logical_date(user, time)
      existing = user.day_logs.find_by(date: date)
      return existing if existing

      goal = user.default_goal
      raise MissingGoal if goal.nil?

      user.day_logs.create!(date: date, goal: goal)
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      # find_by and create! are not atomic: a concurrent request (e.g. a
      # double-tap) can create the same day_log between our lookup and our
      # insert. Whoever loses the race just fetches the row the winner made.
      user.day_logs.find_by!(date: date)
    end
  end

  def totals
    @totals ||= begin
      # The association's default order(:meal, :position) scope isn't valid
      # in an aggregate query without a matching GROUP BY; drop it here.
      sums = entries.reorder(nil).pick(
        Arel.sql("COALESCE(SUM(kcal), 0)"),
        Arel.sql("COALESCE(SUM(protein_g), 0)"),
        Arel.sql("COALESCE(SUM(carbs_g), 0)"),
        Arel.sql("COALESCE(SUM(fat_g), 0)")
      ) || [ 0, 0, 0, 0 ]

      { kcal: sums[0].to_f, protein_g: sums[1].to_f, carbs_g: sums[2].to_f, fat_g: sums[3].to_f }
    end
  end

  # May be negative, and is displayed that way. A day over the goal is
  # information, not an error to hide at zero.
  def remaining
    {
      kcal: goal.kcal - totals[:kcal],
      protein_g: goal.protein_g - totals[:protein_g],
      carbs_g: goal.carbs_g - totals[:carbs_g],
      fat_g: goal.fat_g - totals[:fat_g]
    }
  end

  def entries_for(meal)
    entries.select { |entry| entry.meal == meal }
  end
end
