class DropServings < ActiveRecord::Migration[8.1]
  # Named servings are replaced by Food#portion_amount: a portion needs a
  # size, not a name. The nested-fields UI they required was the most
  # confusing part of the food form, and the unnamed portion covers the
  # same ground. Entries keep their serving_label — it is frozen history.
  def change
    drop_table :servings, id: :uuid do |t|
      t.references :food, null: false, foreign_key: true, type: :uuid
      t.string :label, null: false
      t.decimal :grams, precision: 8, scale: 2, null: false
      t.boolean :is_default, null: false, default: false

      t.timestamps

      t.index :food_id, unique: true, where: "is_default",
        name: "index_servings_on_one_default_per_food"
    end
  end
end
