class CreateGoals < ActiveRecord::Migration[8.1]
  def change
    create_table :goals, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string :label, null: false
      t.integer :kcal, null: false, default: 0
      t.integer :protein_g, null: false, default: 0
      t.integer :carbs_g, null: false, default: 0
      t.integer :fat_g, null: false, default: 0
      t.boolean :is_default, null: false, default: false
      t.date :effective_from, null: false

      t.timestamps
    end

    add_index :goals, [ :user_id, :effective_from ]
  end
end
