class Serving < ApplicationRecord
  belongs_to :food

  validates :label, presence: true
  validates :grams, numericality: { greater_than: 0 }

  before_save :clear_other_defaults, if: :is_default?

  private
    def clear_other_defaults
      food.servings.where.not(id: id).where(is_default: true).update_all(is_default: false)
    end
end
