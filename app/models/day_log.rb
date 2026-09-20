class DayLog < ApplicationRecord
  # Raised rather than silently creating a day without a target to measure
  # against. The controller turns this into a redirect to the goal form.
  class MissingGoal < StandardError; end

  belongs_to :user
  belongs_to :goal
  # Ordered by position within the day, not by :meal — meal is a string enum
  # and would sort alphabetically (breakfast, dinner, lunch, snack). Views
  # that need meal grouping must use Entry::MEALS with #entries_for, never
  # rely on this association's order for that.
  has_many :entries, -> { order(:position, :logged_at) }, dependent: :destroy, inverse_of: :day_log

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

  # Not memoised: a SUM over a handful of rows doesn't need caching, and a
  # controller that creates an entry and then renders totals in the same
  # request needs this to see it.
  def totals
    # The association's default order(:position, :logged_at) scope isn't
    # valid in an aggregate query without a matching GROUP BY; drop it here.
    sums = entries.reorder(nil).pick(
      Arel.sql("COALESCE(SUM(kcal), 0)"),
      Arel.sql("COALESCE(SUM(protein_g), 0)"),
      Arel.sql("COALESCE(SUM(carbs_g), 0)"),
      Arel.sql("COALESCE(SUM(fat_g), 0)")
    ) || [ 0, 0, 0, 0 ]

    { kcal: sums[0].to_f, protein_g: sums[1].to_f, carbs_g: sums[2].to_f, fat_g: sums[3].to_f }
  end

  # May be negative, and is displayed that way. A day over the goal is
  # information, not an error to hide at zero.
  def remaining
    current = totals

    {
      kcal: goal.kcal - current[:kcal],
      protein_g: goal.protein_g - current[:protein_g],
      carbs_g: goal.carbs_g - current[:carbs_g],
      fat_g: goal.fat_g - current[:fat_g]
    }
  end

  def entries_for(meal)
    entries.select { |entry| entry.meal == meal }
  end
end
