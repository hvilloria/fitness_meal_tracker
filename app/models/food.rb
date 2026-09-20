class Food < ApplicationRecord
  # A food consumed in two states is two catalog records: raw and cooked
  # chicken differ by roughly 30%. Anything else — a packaged good like
  # cheese or protein powder — leaves state blank; raw/cooked is the only
  # distinction that actually changes the macros.
  STATES = %w[raw cooked].freeze
  MACRO_FIELDS = %i[kcal_per_100 protein_per_100 carbs_per_100 fat_per_100].freeze

  # A liquid (Coca-Cola, milk) is labelled per 100 ml on the package, not per
  # 100 g — treating 330 ml as 330 g is off by a few percent for a sugary
  # drink, and conceptually wrong besides. This changes LABELS ONLY: every
  # calculation is already proportional to a per-100 basis (see Entry
  # #compute_from_food), so no arithmetic anywhere depends on the unit.
  UNITS = %w[grams milliliters].freeze
  UNIT_ABBREVIATIONS = { "grams" => "g", "milliliters" => "ml" }.freeze

  belongs_to :user
  has_many :servings, -> { order(:label) }, dependent: :destroy, inverse_of: :food
  has_many :entries, dependent: :nullify

  accepts_nested_attributes_for :servings, allow_destroy: true, reject_if: :all_blank

  before_validation :nilify_blank_state

  validates :name, presence: true
  validates :state, inclusion: { in: STATES }, allow_nil: true
  validates :unit, inclusion: { in: UNITS }
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

  # Raw and cooked chicken differ by roughly 30%: rendering both as "Pollo"
  # would make them indistinguishable everywhere this is used, including
  # food_name_snapshot, which freezes it into entry history forever. A blank
  # state (packaged food, not applicable) is left off entirely rather than
  # naming a state that doesn't apply.
  def display_name
    # compact_blank, not compact: the food form's brand field is optional
    # and posts "" rather than nil, and nothing normalises that to nil —
    # a bare compact would let an empty brand through as a stray ", " or
    # empty parens.
    extras = [ brand, state_label ].compact_blank
    extras.any? ? "#{name} (#{extras.join(", ")})" : name
  end

  def archived?
    archived_at.present?
  end

  # "g" or "ml" — the abbreviation used everywhere an amount is shown next
  # to this food (the entry form, entry rows, the day view).
  def unit_abbreviation
    UNIT_ABBREVIATIONS.fetch(unit)
  end

  # "por cada 100 g" / "por cada 100 ml" — the food form's per-100 header.
  def per_100_label
    "por cada 100 #{unit_abbreviation}"
  end

  private
    def state_label
      return nil if state.blank?

      # food.states.* is capitalized for standalone use (a select option);
      # lower-cased here since it reads inline, parenthetical to the name.
      I18n.t("food.states.#{state}").downcase
    end

    # The form's select posts "" for the blank "No aplica" option; nothing
    # else normalises that to nil, and "" would fail the inclusion check
    # that allow_nil is meant to exempt it from.
    def nilify_blank_state
      self.state = nil if state.blank?
    end
end
