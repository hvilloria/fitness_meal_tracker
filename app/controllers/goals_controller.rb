class GoalsController < ApplicationController
  include NormalizesDecimalParams

  def edit
    @goal = current_user.default_goal || build_seeded_goal
  end

  def update
    attrs = goal_params
    previous = current_user.default_goal

    if previous && unchanged?(previous, attrs)
      redirect_to root_path, notice: "Meta guardada."
      return
    end

    build_and_save_version(attrs)
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    # A concurrent edit (e.g. a double-tap over a slow connection) can win
    # the race for the default-goal unique index between our read and our
    # insert. Versioning off whatever is now the default keeps history
    # honest instead of mutating the row that won.
    build_and_save_version(attrs)
  end

  private
    # A version is only worth creating when it actually changes a macro.
    # Assigning to a dup lets ActiveRecord typecast the submitted strings
    # the same way a real save would, without touching the persisted row.
    def unchanged?(goal, attrs)
      candidate = goal.dup
      candidate.assign_attributes(attrs)
      Goal::MACRO_FIELDS.all? { |field| candidate.public_send(field) == goal.public_send(field) }
    end

    def build_and_save_version(attrs)
      @goal = current_user.goals.build(attrs.merge(
        effective_from: DayLog.logical_date(current_user),
        is_default: true
      ))

      if @goal.save
        repoint_today_log
        redirect_to root_path, notice: "Meta guardada."
      else
        render :edit, status: :unprocessable_content
      end
    end

    # Past days must keep measuring against the goal that was in force when
    # they were logged. The day still in progress hasn't finished being
    # measured, so it moves to whatever the user just set.
    def repoint_today_log
      today = DayLog.logical_date(current_user)
      current_user.day_logs.find_by(date: today)&.update!(goal: @goal)
    end

    # A brand new goal has no split to preserve. Seeding from a calorie figure
    # uses MacroSplit's evidence-backed default rather than leaving the form
    # blank; the user overwrites it from there.
    def build_seeded_goal
      seed = MacroSplit.from_kcal(params[:kcal].to_s.to_i)

      current_user.goals.build(
        effective_from: DayLog.logical_date(current_user),
        is_default: true,
        **seed
      )
    end

    def goal_params
      permitted = require_params_hash(:goal).permit(:protein_g, :carbs_g, :fat_g)
      normalize_decimals(permitted, :protein_g, :carbs_g, :fat_g)
      permitted
    end
end
