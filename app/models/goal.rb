class Goal < ApplicationRecord
  MACRO_FIELDS = %i[protein_g carbs_g fat_g].freeze

  belongs_to :user
  has_many :day_logs, dependent: :restrict_with_error

  validates :label, presence: true
  validates :effective_from, presence: true
  validates(*MACRO_FIELDS, numericality: { greater_than_or_equal_to: 0 })

  # The calorie target is never entered directly: it is whatever the three
  # macros add up to. Moving any macro moves the total.
  before_validation :derive_kcal
  after_save :clear_other_defaults, if: :is_default?

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
