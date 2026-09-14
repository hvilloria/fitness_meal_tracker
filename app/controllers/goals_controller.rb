class GoalsController < ApplicationController
  def edit
    @goal = current_user.default_goal || build_seeded_goal
  end

  def update
    @goal = current_user.default_goal || current_user.goals.build(effective_from: Date.current, is_default: true)
    save_goal
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    # @goal.update and the partial unique index on is_default are not
    # atomic: two concurrent first-saves (e.g. a double-tap over a slow
    # connection) can both find no default goal and both try to insert one
    # as default. Whoever loses the race applies the same edits to the
    # goal the winner just created, mirroring DayLog.for's recovery.
    @goal = current_user.default_goal
    save_goal
  end

  private
    def save_goal
      if @goal.update(goal_params)
        redirect_to root_path, notice: "Meta guardada."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # A brand new goal has no split to preserve. Seeding from a calorie figure
    # uses MacroSplit's evidence-backed default rather than leaving the form
    # blank; the user overwrites it from there.
    def build_seeded_goal
      seed = MacroSplit.from_kcal(params[:kcal].to_s.to_i)

      current_user.goals.build(
        label: "Día normal",
        effective_from: Date.current,
        is_default: true,
        **seed
      )
    end

    def goal_params
      params.require(:goal).permit(:label, :protein_g, :carbs_g, :fat_g)
    end
end
