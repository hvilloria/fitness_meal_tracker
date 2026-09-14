class Food < ApplicationRecord
  # A food consumed in two states is two catalog records: raw and cooked
  # chicken differ by roughly 30%.
  STATES = %w[raw cooked dry as_sold].freeze
  MACRO_FIELDS = %i[kcal_per_100 protein_per_100 carbs_per_100 fat_per_100].freeze

  belongs_to :user
  has_many :servings, -> { order(:label) }, dependent: :destroy, inverse_of: :food
  has_many :entries, dependent: :nullify

  accepts_nested_attributes_for :servings, allow_destroy: true, reject_if: :all_blank

  validates :name, presence: true
  validates :state, presence: true, inclusion: { in: STATES }
  validates(*MACRO_FIELDS, presence: true, numericality: { greater_than_or_equal_to: 0 })
  validates :fiber_per_100, :sodium_per_100, :sugar_per_100,
    numericality: { greater_than_or_equal_to: 0, allow_nil: true }

  scope :active, -> { where(archived_at: nil) }

  def default_serving
    servings.find_by(is_default: true)
  end

  def display_name
    brand.present? ? "#{name} (#{brand})" : name
  end

  def archived?
    archived_at.present?
  end
end
