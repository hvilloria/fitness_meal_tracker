class AddUnitToFoods < ActiveRecord::Migration[8.1]
  # Grams was the only unit until now, so it is the safe default and
  # backfill value for existing rows — not nullable, because every food
  # (including catalog entries created before this migration) must resolve
  # to a definite unit for its "per 100 g"/"per 100 ml" label.
  def change
    add_column :foods, :unit, :string, null: false, default: "grams"
  end
end
