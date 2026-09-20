class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # decimal(8, 2) columns across the schema hold at most 999999.99; a value at
  # or above this passes Ruby-level numericality validation but raises
  # ActiveRecord::RangeError on save. Shared here so every model bounding a
  # decimal(8, 2) column — including derived columns like Entry#kcal — uses
  # the same number rather than redefining it.
  DECIMAL_COLUMN_LIMIT = 1_000_000

  # integer columns (e.g. Goal's macro grams) hold at most 2147483647 (4-byte
  # signed); a value at or above this passes Ruby-level numericality
  # validation but raises ActiveModel::RangeError on save. 100_000 g of a
  # single macronutrient is already absurd, so it leaves generous headroom
  # while keeping the derived kcal (macro grams × up to 9) well inside range.
  INTEGER_COLUMN_LIMIT = 100_000
end
