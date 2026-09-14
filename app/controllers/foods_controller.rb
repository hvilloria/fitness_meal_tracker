class FoodsController < ApplicationController
  include NormalizesDecimalParams

  before_action :set_food, only: %i[edit update destroy]

  def index
    @foods = current_user.foods.active.order(:name)
  end

  def new
    @food = current_user.foods.build(state: "as_sold")
    @food.servings.build
  end

  def create
    @food = current_user.foods.build(food_params)

    if @food.save
      redirect_to foods_path, notice: "Alimento guardado."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @food.servings.build if @food.servings.empty?
  end

  def update
    if @food.update(food_params)
      redirect_to foods_path, notice: "Alimento actualizado."
    else
      render :edit, status: :unprocessable_entity
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
      permitted = params.require(:food).permit(
        :name, :brand, :state,
        :kcal_per_100, :protein_per_100, :carbs_per_100, :fat_per_100,
        :fiber_per_100, :sodium_per_100, :sugar_per_100,
        servings_attributes: %i[id label grams is_default _destroy]
      )
      normalize_decimals(permitted,
        :kcal_per_100, :protein_per_100, :carbs_per_100, :fat_per_100,
        :fiber_per_100, :sodium_per_100, :sugar_per_100)
      permitted[:servings_attributes]&.each_value { |serving| normalize_decimals(serving, :grams) }
      permitted
    end
end
