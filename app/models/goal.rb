class Goal < ApplicationRecord
  MACRO_FIELDS = %i[protein_g carbs_g fat_g].freeze

  belongs_to :user
  has_many :day_logs, dependent: :restrict_with_error

  validates :effective_from, presence: true
  # integer(4-byte) columns: a value at or above INTEGER_COLUMN_LIMIT passes
  # here but the derived kcal (macro grams × up to 9, see #derive_kcal) can
  # still raise ActiveModel::RangeError on save even when the raw macro
  # itself is within the 4-byte limit — the same lesson Entry already
  # learned for decimal(8, 2) columns. Bounding the inputs generously below
  # the column limit keeps the derived kcal safely inside it too.
  validates(*MACRO_FIELDS,
    numericality: { greater_than_or_equal_to: 0, less_than: INTEGER_COLUMN_LIMIT })

  # The calorie target is never entered directly: it is whatever the three
  # macros add up to. Moving any macro moves the total.
  before_validation :derive_kcal
  before_save :clear_other_defaults, if: :is_default?

  def percentages
    MacroSplit.percentages(protein_g: protein_g, carbs_g: carbs_g, fat_g: fat_g)
  end

  private
    def derive_kcal
      self.kcal = MacroSplit.kcal_from(protein_g: protein_g, carbs_g: carbs_g, fat_g: fat_g)
    end

    def clear_other_defaults
      user.goals.where.not(id: id).where(is_default: true).update_all(is_default: false)
    end
end
