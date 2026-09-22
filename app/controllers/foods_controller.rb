class FoodsController < ApplicationController
  include NormalizesDecimalParams

  before_action :set_food, only: %i[edit update destroy]

  # The catalog is shared for reading: every active food is listed, not
  # just current_user's own. #includes(:user) avoids an N+1 from the owner
  # name shown on a food that isn't yours (see app/views/foods/_food.html.erb).
  def index
    @foods = Food.active.includes(:user).order(:name)
  end

  def new
    @food = current_user.foods.build
  end

  def create
    @food = current_user.foods.build(food_params)

    if @food.save
      redirect_to foods_path, notice: "Alimento guardado."
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @food.update(food_params)
      redirect_to foods_path, notice: "Alimento actualizado."
    else
      render :edit, status: :unprocessable_content
    end
  end

  # Soft delete: entries reference this food, and the catalog is history too.
  def destroy
    @food.update!(archived_at: Time.current)
    redirect_to foods_path, notice: "Alimento archivado."
  end

  private
    def set_food
      @food = current_user.foods.find(params[:id])
    end

    def food_params
      permitted = require_params_hash(:food).permit(
        :name, :brand, :state, :unit, :portion_amount,
        :kcal_per_portion, :protein_per_portion, :carbs_per_portion, :fat_per_portion,
        :fiber_per_100, :sodium_per_100, :sugar_per_100
      )
      normalize_decimals(permitted, :portion_amount,
        :kcal_per_portion, :protein_per_portion, :carbs_per_portion, :fat_per_portion,
        :fiber_per_100, :sodium_per_100, :sugar_per_100)
      # The portion is typed by hand with the unit habitually alongside it
      # ("30 g") — the same field, and the same reason, as the serving grams
      # this replaced. See NormalizesDecimalParams::AMOUNT_WITH_UNIT.
      strip_unit_suffixes(permitted, :portion_amount)
      permitted
    end
end
