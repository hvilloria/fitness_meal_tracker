class CreateFoods < ActiveRecord::Migration[8.1]
  def change
    create_table :foods, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string :name, null: false
      t.string :brand
      t.string :state, null: false
      t.decimal :kcal_per_100, precision: 8, scale: 2, null: false
      t.decimal :protein_per_100, precision: 8, scale: 2, null: false
      t.decimal :carbs_per_100, precision: 8, scale: 2, null: false
      t.decimal :fat_per_100, precision: 8, scale: 2, null: false
      t.decimal :fiber_per_100, precision: 8, scale: 2
      t.decimal :sodium_per_100, precision: 8, scale: 2
      t.decimal :sugar_per_100, precision: 8, scale: 2
      t.datetime :archived_at

      t.timestamps
    end

    add_index :foods, [ :user_id, :name ]
  end
end
