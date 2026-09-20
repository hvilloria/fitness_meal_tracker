class RemoveLabelFromGoals < ActiveRecord::Migration[8.1]
  def change
    remove_column :goals, :label, :string
  end
end
