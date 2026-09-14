class CreateServings < ActiveRecord::Migration[8.1]
  def change
    create_table :servings, id: :uuid do |t|
      t.references :food, null: false, foreign_key: true, type: :uuid
      t.string :label, null: false
      t.decimal :grams, precision: 8, scale: 2, null: false
      t.boolean :is_default, null: false, default: false

      t.timestamps
    end
  end
end
