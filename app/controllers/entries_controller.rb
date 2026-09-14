class EntriesController < ApplicationController
  include NormalizesDecimalParams

  rescue_from DayLog::MissingGoal, with: :redirect_to_goal

  def new
    @day_log = DayLog.for(current_user)
    @entry = Entry.new(meal: params[:meal].to_s.presence || "breakfast")
    load_food_options
  end

  def create
    @day_log = DayLog.for(current_user)
    @entry = @day_log.entries.build(entry_attributes)

    if @entry.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to new_entry_path(meal: @entry.meal), notice: "Registrado." }
      end
    else
      load_food_options
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    entry = Entry.joins(:day_log).where(day_logs: { user_id: current_user.id }).find(params[:id])
    entry.destroy
    redirect_back fallback_location: root_path, notice: "Entrada eliminada."
  end

  private
    def load_food_options
      @recent_foods = Food.recent_for(current_user)
      @last_grams = Food.last_grams_for(current_user)
    end

    def entry_attributes
      attributes = entry_params.except(:serving_id, :quantity)
      food = find_food(entry_params[:food_id])
      return attributes.merge(food: nil) if food.nil?

      attributes.merge(food: food, **serving_resolution(food))
    end

    # A serving is a multiplier, never a source of macros: it resolves to
    # grams and the macros follow from the food's per-100 g values.
    def serving_resolution(food)
      serving = food.servings.find_by(id: entry_params[:serving_id])
      return {} if serving.nil?

      quantity = entry_params[:quantity].to_d
      quantity = 1 if quantity.zero?

      { grams: serving.grams * quantity, serving_label: "#{quantity.to_i} × #{serving.label}" }
    end

    def find_food(food_id)
      return nil if food_id.blank?

      current_user.foods.find(food_id)
    end

    def entry_params
      permitted = params.require(:entry).permit(
        :food_id, :meal, :grams, :serving_id, :quantity,
        :food_name_snapshot, :protein_g, :carbs_g, :fat_g
      )
      normalize_decimals(permitted, :grams, :protein_g, :carbs_g, :fat_g, :quantity)
      permitted
    end

    def redirect_to_goal
      redirect_to edit_goal_path, notice: "Primero definí tu meta."
    end
end
