# Aggregates a user's history into the two horizons the "Progreso" screen
# reports: an actionable weekly balance and a monthly summary. The two
# horizons use different bases, on purpose:
#
# The WEEK's budget is the full seven days, each against its OWN goal (goals
# are versioned, see DayLog#goal_id; an unlogged day falls back to the user's
# current default goal, since there is no day_log to read a goal from).
# Consumed stays the sum over logged days only — a day with no entries is
# never treated as a day the user ate zero calories. The gap between "logged
# days" and "seven" is real information (the figure is only exact once
# everything is logged), so the screen shows it as a small secondary line
# rather than hiding it.
#
# The MONTH stays an average over logged days only, on both sides. An
# average that counted unlogged days as zero would be meaningless (it would
# just fall as the month goes on), so #days_in still excludes them from both
# sides there.
#
# Dates always come from DayLog.logical_date, never Date.current: the day's
# own cutoff hour decides which calendar date an entry belongs to, and
# week/month boundaries must agree with that.
class ProgressSummary
  # A day counts as "on target" when its calories land within this share of
  # THAT DAY'S OWN goal (goals are versioned, see DayLog#goal_id). This is a
  # display convention chosen so the figure reads at a glance on a small
  # screen, not a nutritional claim about what +/-10% means metabolically.
  ON_TARGET_TOLERANCE = 0.10

  FULL_DAY_NAMES = %w[lunes martes miércoles jueves viernes sábado domingo].freeze
  DAY_ABBREVIATIONS = %w[Lun Mar Mié Jue Vie Sáb Dom].freeze

  Day = Struct.new(:date, :logged, :kcal, :protein_g, :carbs_g, :fat_g,
    :goal_kcal, :goal_protein_g, :goal_carbs_g, :goal_fat_g, keyword_init: true)

  attr_reader :user, :today

  def initialize(user, today: DayLog.logical_date(user))
    @user = user
    @today = today
  end

  # ------------------------------------------------------------------ week

  def week_start
    today.beginning_of_week(:monday)
  end

  def week_end
    today.end_of_week(:monday)
  end

  def week_days
    @week_days ||= days_in(week_start..week_end, fallback_goal: default_goal)
  end

  def week_logged_days
    @week_logged_days ||= week_days.select(&:logged)
  end

  def week_logged_count
    week_logged_days.size
  end

  def week_total_days
    week_days.size
  end

  def week_empty?
    week_logged_count.zero?
  end

  # All seven days, each against its own goal — see the class comment.
  def week_budget
    week_days.sum(&:goal_kcal)
  end

  def week_consumed
    week_logged_days.sum(&:kcal)
  end

  def week_remaining
    week_budget - week_consumed
  end

  def week_protein_consumed
    week_logged_days.sum(&:protein_g)
  end

  def week_protein_goal
    week_days.sum(&:goal_protein_g)
  end

  def week_carbs_consumed
    week_logged_days.sum(&:carbs_g)
  end

  def week_carbs_goal
    week_days.sum(&:goal_carbs_g)
  end

  def week_fat_consumed
    week_logged_days.sum(&:fat_g)
  end

  def week_fat_goal
    week_days.sum(&:goal_fat_g)
  end

  # The days still ahead of today within the week. Today itself is left out
  # on purpose: it isn't finished yet and the "Hoy" tab already owns it, so
  # the budget here is framed as what's left for the rest of the week.
  def week_upcoming_days
    week_days.select { |day| day.date > today }
  end

  def week_upcoming_label
    names = week_upcoming_days.map { |day| FULL_DAY_NAMES[day.date.wday.zero? ? 6 : day.date.wday - 1] }
    return "hoy, que es el último día de la semana" if names.empty?

    # config/locales/es.yml wires the ", " / " y " connectors for #to_sentence.
    names.to_sentence
  end

  # ----------------------------------------------------------------- month

  def month_start
    today.beginning_of_month
  end

  # Only up to today: future days in the month have no logs yet, and
  # "días registrados de N" should compare against days that could have
  # been logged so far, not against days that haven't happened.
  def month_days
    @month_days ||= days_in(month_start..today)
  end

  def month_logged_days
    @month_logged_days ||= month_days.select(&:logged)
  end

  def month_elapsed_days
    month_days.size
  end

  def month_logged_count
    month_logged_days.size
  end

  def month_empty?
    month_logged_count.zero?
  end

  def month_average_kcal
    average(month_logged_days, :kcal)
  end

  def month_average_goal_kcal
    average(month_logged_days, :goal_kcal)
  end

  def month_average_protein_g
    average(month_logged_days, :protein_g)
  end

  def month_average_goal_protein_g
    average(month_logged_days, :goal_protein_g)
  end

  def month_on_target_count
    month_logged_days.count { |day| on_target?(day) }
  end

  private
    # Fetched once and memoised: week_days is itself memoised, so this runs
    # at most one query regardless of how many unlogged days the week has.
    def default_goal
      @default_goal ||= user.default_goal
    end

    def average(days, field)
      return 0.0 if days.empty?

      days.sum(&field) / days.size
    end

    def on_target?(day)
      return false unless day.goal_kcal.positive?

      (day.kcal - day.goal_kcal).abs <= day.goal_kcal * ON_TARGET_TOLERANCE
    end

    # One query for the range's day_logs plus their goal (via includes, so
    # every goal in the range is fetched once regardless of how many days
    # there are — never one SUM per day), and one grouped query for that
    # range's entry totals. A day with no rows in the second query simply
    # never becomes a key in `sums`, which is exactly how "no entries at
    # all" is told apart from "logged, totalling zero".
    #
    # fallback_goal supplies the goal fields for an unlogged day (there is no
    # day_log to read a goal from). The week passes the user's current
    # default goal so every one of its seven days carries a real goal; the
    # month passes nothing, because an unlogged day's goal is never read
    # there (month_logged_days excludes it from both sides — see the class
    # comment).
    def days_in(range, fallback_goal: nil)
      day_logs_by_date = user.day_logs.where(date: range).includes(:goal).index_by(&:date)
      sums = entry_sums_for(day_logs_by_date.values.map(&:id))

      range.map do |date|
        day_log = day_logs_by_date[date]
        totals = day_log && sums[day_log.id]

        if totals
          Day.new(
            date: date, logged: true,
            kcal: totals[:kcal], protein_g: totals[:protein_g],
            carbs_g: totals[:carbs_g], fat_g: totals[:fat_g],
            goal_kcal: day_log.goal.kcal.to_f, goal_protein_g: day_log.goal.protein_g.to_f,
            goal_carbs_g: day_log.goal.carbs_g.to_f, goal_fat_g: day_log.goal.fat_g.to_f
          )
        else
          Day.new(
            date: date, logged: false, kcal: 0.0, protein_g: 0.0, carbs_g: 0.0, fat_g: 0.0,
            goal_kcal: fallback_goal&.kcal.to_f, goal_protein_g: fallback_goal&.protein_g.to_f,
            goal_carbs_g: fallback_goal&.carbs_g.to_f, goal_fat_g: fallback_goal&.fat_g.to_f
          )
        end
      end
    end

    def entry_sums_for(day_log_ids)
      return {} if day_log_ids.empty?

      Entry.where(day_log_id: day_log_ids)
        .group(:day_log_id)
        .pluck(:day_log_id, Arel.sql("SUM(kcal)"), Arel.sql("SUM(protein_g)"), Arel.sql("SUM(carbs_g)"), Arel.sql("SUM(fat_g)"))
        .to_h { |id, kcal, protein, carbs, fat| [ id, { kcal: kcal.to_f, protein_g: protein.to_f, carbs_g: carbs.to_f, fat_g: fat.to_f } ] }
    end
end
