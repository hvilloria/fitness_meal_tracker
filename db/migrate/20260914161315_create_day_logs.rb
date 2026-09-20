class CreateDayLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :day_logs, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.references :goal, null: false, foreign_key: true, type: :uuid
      t.date :date, null: false

      t.timestamps
    end

    add_index :day_logs, [ :user_id, :date ], unique: true
  end
end
