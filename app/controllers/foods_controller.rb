class FoodsController < ApplicationController
  include NormalizesDecimalParams

  before_action :set_food, only: %i[edit update destroy]

  def index
    @foods = current_user.foods.active.order(:name)
  end

  def new
    @food = current_user.foods.build
    @food.servings.build
  end

  def create
    @food = current_user.foods.build(food_params)

    if @food.save
      redirect_to foods_path, notice: "Alimento guardado."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
    @food.servings.build if @food.servings.empty?
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
        :name, :brand, :state, :unit,
        :kcal_per_100, :protein_per_100, :carbs_per_100, :fat_per_100,
        :fiber_per_100, :sodium_per_100, :sugar_per_100,
        servings_attributes: %i[id label grams is_default _destroy]
      )
      normalize_decimals(permitted,
        :kcal_per_100, :protein_per_100, :carbs_per_100, :fat_per_100,
        :fiber_per_100, :sodium_per_100, :sugar_per_100)
      normalize_nested_servings(permitted)
      permitted
    end

    # accepts_nested_attributes_for permits servings_attributes both as the
    # index-keyed Hash this app's own fields_for generates ({"0" => {...}})
    # and as an Array of hashes ([{...}]) — a raw HTTP client can send either.
    # Handle both explicitly rather than assuming the Hash shape.
    def normalize_nested_servings(permitted)
      nested = permitted[:servings_attributes]
      return permitted if nested.blank?

      entries = nested.respond_to?(:each_value) ? nested.each_value : nested
      entries.each { |serving| normalize_decimals(serving, :grams) if serving.respond_to?(:[]=) }
      permitted
    end
end
