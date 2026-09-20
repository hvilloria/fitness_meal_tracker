class AddPortionAmountToFoods < ActiveRecord::Migration[8.1]
  # The macro figures a user types describe ONE PORTION of the food, stated
  # in the food's own unit (see Food#unit). Storage stays normalised per 100
  # — this column only records the basis those typed figures were converted
  # from, so the form can show them back as they were entered.
  #
  # 100 is the default and the backfill value: every food that exists today
  # was entered with per-100 figures, so a portion of 100 leaves its stored
  # values meaning exactly what they meant before.
  def change
    add_column :foods, :portion_amount, :decimal, precision: 8, scale: 2, null: false, default: 100
  end
end
