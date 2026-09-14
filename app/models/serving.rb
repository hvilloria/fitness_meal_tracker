class Serving < ApplicationRecord
  belongs_to :food

  # decimal(8, 2) holds at most 999999.99; see ApplicationRecord::DECIMAL_COLUMN_LIMIT.
  validates :label, presence: true
  validates :grams, numericality: { greater_than: 0, less_than: DECIMAL_COLUMN_LIMIT }

  before_save :clear_other_defaults, if: :is_default?

  private
    def clear_other_defaults
      food.servings.where.not(id: id).where(is_default: true).update_all(is_default: false)
    end
end
