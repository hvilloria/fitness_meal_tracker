class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users, id: :uuid do |t|
      t.string :email, null: false
      t.string :name, null: false
      t.string :avatar_url
      t.string :provider, null: false
      t.string :uid, null: false
      t.integer :day_cutoff_hour, null: false, default: 4

      t.timestamps
    end

    add_index :users, :email, unique: true
    add_index :users, [ :provider, :uid ], unique: true
  end
end
