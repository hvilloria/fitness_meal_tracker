# An Entry is a historical fact, not a view onto the catalog. Its macros are
# computed once, at write time, and frozen. Correcting a food's values later
# must not rewrite what was eaten last month.
class Entry < ApplicationRecord
  MEALS = %w[breakfast lunch snack dinner].freeze

  belongs_to :day_log
  belongs_to :food, optional: true

  # #grams keeps its historical column name, but it stores the amount in the
  # FOOD'S OWN UNIT (see Food#unit) — grams for most foods, millilitres for
  # a liquid. Renaming the column across a live app isn't worth it; anywhere
  # the UI shows "g" for this value, it must read the food's unit instead
  # (Food#unit_abbreviation), not assume grams.

  enum :meal, MEALS.index_with(&:itself), validate: true

  validates :food_name_snapshot, presence: true
  validates :grams, numericality: { greater_than: 0, less_than: DECIMAL_COLUMN_LIMIT }, allow_nil: true
  validates :grams, presence: true, if: :from_catalog?
  validates :protein_g, :carbs_g, :fat_g, presence: true, unless: :from_catalog?
  # kcal is derived, not typed in: bounding only the inputs (grams, or the
  # typed macros) is not enough, because grams * a food's per-100g kcal can
  # still overflow decimal(8, 2) even when grams itself is in range.
  validates :kcal, :protein_g, :carbs_g, :fat_g,
    numericality: { greater_than_or_equal_to: 0, less_than: DECIMAL_COLUMN_LIMIT }, allow_nil: true

  before_validation :set_logged_at
  before_validation :set_position, on: :create
  # Only recompute when the inputs that feed the macros actually changed.
  # Without this guard, any unrelated save (reordering, editing the serving
  # label) would silently rewrite frozen history — see recalculate! below,
  # which is meant to be the only deliberate way that happens.
  before_validation :snapshot_food_name, if: :macro_inputs_changed?
  before_validation :compute_macros, if: :macro_inputs_changed?

  # An entry loses its food_id when the food is deleted, so this asks about
  # the association as it stands right now.
  def from_catalog?
    food_id.present?
  end

  # "g" for an ad-hoc entry (no food to read a unit from) or one whose food
  # was later deleted — a neutral default that matches what every entry
  # showed before Food gained a unit at all.
  def unit_abbreviation
    food&.unit_abbreviation || "g"
  end

  # The only way a stored entry's macros ever change. An orphaned entry (its
  # food was deleted) has no catalog source left to recompute against, so
  # this refuses rather than silently re-deriving with the ad-hoc formula.
  def recalculate!
    # "food was deleted" would be a false message for an entry that was
    # ad-hoc all along — from_catalog? cannot tell the two apart (see
    # #macro_inputs_changed? below), so the message stays neutral about why.
    raise "Cannot recalculate an entry with no catalog food to recalculate from" unless from_catalog?

    compute_macros
    save!
  end

  private
    def macro_inputs_changed?
      # A persisted entry with no food_id is either genuinely ad-hoc or an
      # orphan whose food was deleted — from_catalog? can't tell those apart
      # after the fact. Either way there is no catalog source left to
      # recompute against, so a later write to the macro fields (e.g. a
      # position reorder that happens to touch them, or a future edit form)
      # must not silently re-derive kcal with the ad-hoc 4/4/9 formula and
      # overwrite whatever frozen figure — catalog-derived or label-derived
      # — was there before. Only a brand new record computes from typed
      # macros.
      return false if persisted? && food_id.blank?

      new_record? || food_id_changed? || grams_changed? ||
        protein_g_changed? || carbs_g_changed? || fat_g_changed?
    end

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
      self.kcal = MacroSplit.kcal_from_exact(protein_g: protein_g, carbs_g: carbs_g, fat_g: fat_g)
    end
end
