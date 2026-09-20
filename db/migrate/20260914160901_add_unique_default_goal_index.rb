class AddUniqueDefaultGoalIndex < ActiveRecord::Migration[8.1]
  def change
    add_index :goals, :user_id, unique: true, where: "is_default",
      name: "index_goals_on_one_default_per_user"
  end
end
