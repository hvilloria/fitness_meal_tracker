class Food < ApplicationRecord
  # A food consumed in two states is two catalog records: raw and cooked
  # chicken differ by roughly 30%.
  STATES = %w[raw cooked dry as_sold].freeze
  MACRO_FIELDS = %i[kcal_per_100 protein_per_100 carbs_per_100 fat_per_100].freeze

  belongs_to :user
  has_many :servings, -> { order(:label) }, dependent: :destroy, inverse_of: :food
  has_many :entries, dependent: :nullify

  accepts_nested_attributes_for :servings, allow_destroy: true, reject_if: :all_blank

  # decimal(8, 2) columns hold at most 999999.99; without this bound an
  # out-of-range value passes validation and raises ActiveRecord::RangeError
  # on save instead of failing the form.
  DECIMAL_COLUMN_LIMIT = 1_000_000

  validates :name, presence: true
  validates :state, presence: true, inclusion: { in: STATES }
  validates(*MACRO_FIELDS, presence: true,
    numericality: { greater_than_or_equal_to: 0, less_than: DECIMAL_COLUMN_LIMIT })
  validates :fiber_per_100, :sodium_per_100, :sugar_per_100,
    numericality: { greater_than_or_equal_to: 0, less_than: DECIMAL_COLUMN_LIMIT, allow_nil: true }

  scope :active, -> { where(archived_at: nil) }

  # Ordered by how often the food was logged recently, then by how recently.
  # This is the whole of the friction reduction in this iteration: the foods
  # eaten daily sit at the top of the entry form without a search.
  def self.recent_for(user, limit: 20)
    active
      .joins(entries: :day_log)
      .where(day_logs: { user_id: user.id })
      .group(:id)
      .order(Arel.sql("COUNT(entries.id) DESC, MAX(entries.logged_at) DESC"))
      .limit(limit)
      .load # .load so .size returns the food count — on an unloaded grouped relation .size returns a per-group Hash
  end

  # One row per food, carrying the weight used most recently. Prefilling the
  # entry form with it means a habitual 190 g of chicken is not retyped daily.
  def self.last_grams_for(user)
    Entry
      .joins(:day_log)
      .where(day_logs: { user_id: user.id })
      .where.not(food_id: nil)
      .order(:food_id, logged_at: :desc, id: :desc)
      .select("DISTINCT ON (entries.food_id) entries.food_id, entries.grams")
      .to_h { |entry| [ entry.food_id, entry.grams ] }
  end

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
