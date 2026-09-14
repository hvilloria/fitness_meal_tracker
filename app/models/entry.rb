# An Entry is a historical fact, not a view onto the catalog. Its macros are
# computed once, at write time, and frozen. Correcting a food's values later
# must not rewrite what was eaten last month.
class Entry < ApplicationRecord
  MEALS = %w[breakfast lunch snack dinner].freeze

  belongs_to :day_log
  belongs_to :food, optional: true

  enum :meal, MEALS.index_with(&:itself), validate: true

  validates :food_name_snapshot, presence: true
  validates :grams, numericality: { greater_than: 0 }, if: :from_catalog?
  validates :grams, presence: true, if: :from_catalog?
  validates :protein_g, :carbs_g, :fat_g, presence: true, unless: :from_catalog?
  validates :kcal, :protein_g, :carbs_g, :fat_g,
    numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  before_validation :set_logged_at
  before_validation :set_position, on: :create
  before_validation :snapshot_food_name
  before_validation :compute_macros

  # An entry loses its food_id when the food is deleted, so this asks about
  # the association as it stands right now.
  def from_catalog?
    food_id.present?
  end

  # The only way a stored entry's macros ever change.
  def recalculate!
    compute_macros
    save!
  end

  private
    def set_logged_at
      self.logged_at ||= Time.current
    end

    def set_position
      return if position.present? && position.positive?

      self.position = (day_log&.entries&.where(meal: meal)&.maximum(:position) || 0) + 1
    end

    def snapshot_food_name
      self.food_name_snapshot = food.display_name if food.present?
    end

    def compute_macros
      food.present? ? compute_from_food : compute_from_typed_macros
    end

    def compute_from_food
      return if grams.blank?

      factor = grams.to_d / 100
      self.kcal = (food.kcal_per_100 * factor).round(2)
      self.protein_g = (food.protein_per_100 * factor).round(2)
      self.carbs_g = (food.carbs_per_100 * factor).round(2)
      self.fat_g = (food.fat_per_100 * factor).round(2)
    end

    def compute_from_typed_macros
      self.kcal = MacroSplit.kcal_from(protein_g: protein_g, carbs_g: carbs_g, fat_g: fat_g)
    end
end
