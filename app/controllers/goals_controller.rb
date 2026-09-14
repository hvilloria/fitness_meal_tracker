class GoalsController < ApplicationController
  def edit
    @goal = current_user.default_goal || build_seeded_goal
  end

  def update
    @goal = current_user.default_goal || current_user.goals.build(effective_from: Date.current, is_default: true)

    if @goal.update(goal_params)
      redirect_to root_path, notice: "Meta guardada."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    # A brand new goal has no split to preserve. Seeding from a calorie figure
    # uses MacroSplit's evidence-backed default rather than leaving the form
    # blank; the user overwrites it from there.
    def build_seeded_goal
      seed = MacroSplit.from_kcal(params[:kcal].to_i)

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
