class MakeFoodStateOptional < ActiveRecord::Migration[8.1]
  # Blank now means "not applicable" for a packaged food (cheese, protein
  # powder, ...) rather than forcing a wrong raw/cooked answer. No production
  # data exists yet, so there is nothing to backfill.
  def change
    change_column_null :foods, :state, true
  end
end
