class CreateEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :entries, id: :uuid do |t|
      t.references :day_log, null: false, foreign_key: true, type: :uuid
      # Nullable: an ad-hoc entry has no catalog food, and deleting a food
      # must not take the history with it.
      t.references :food, foreign_key: { on_delete: :nullify }, type: :uuid
      t.string :meal, null: false
      t.decimal :grams, precision: 8, scale: 2
      t.string :serving_label
      t.string :food_name_snapshot, null: false
      t.decimal :kcal, precision: 8, scale: 2, null: false
      t.decimal :protein_g, precision: 8, scale: 2, null: false
      t.decimal :carbs_g, precision: 8, scale: 2, null: false
      t.decimal :fat_g, precision: 8, scale: 2, null: false
      t.integer :position, null: false, default: 0
      t.datetime :logged_at, null: false

      t.timestamps
    end

    add_index :entries, [ :day_log_id, :meal, :position ]
  end
end
