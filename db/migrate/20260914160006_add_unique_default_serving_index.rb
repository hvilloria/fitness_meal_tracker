class AddUniqueDefaultServingIndex < ActiveRecord::Migration[8.1]
  def change
    add_index :servings, :food_id, unique: true, where: "is_default",
      name: "index_servings_on_one_default_per_food"
  end
end
