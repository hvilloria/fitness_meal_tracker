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
  # The same unit a thousand times over, offered beside the base one so a
  # bulk amount is typed as "0.5 kg" instead of "500". It is a multiplier on
  # the way in and nothing else: #grams still stores the base unit.
  UNIT_MULTIPLES = { "grams" => "kg", "milliliters" => "l" }.freeze
  MULTIPLE_FACTOR = 1000

  # #portion_amount is how much of the food's own unit one portion is, and
  # the macro figures the user types describe THAT portion — "1 unidad of
  # this is 30 g and contains 10 P / 5 C / 10 G". Storage stays normalised
  # per 100 (see PORTION_MACRO_SOURCES): a label already stating per-100
  # values simply declares a portion of 100, which is the default, so the
  # common case needs no thought at all.
  DEFAULT_PORTION_AMOUNT = 100

  # The form's four macro fields — per portion — mapped to the per-100
  # column each is normalised into on the way in and derived back from on
  # the way out. The per-100 columns are the spine of the app; nothing
  # downstream (Entry#compute_from_food, the dashboard, ProgressSummary)
  # knows portions exist.
  PORTION_MACRO_SOURCES = {
    kcal_per_portion: :kcal_per_100,
    protein_per_portion: :protein_per_100,
    carbs_per_portion: :carbs_per_100,
    fat_per_portion: :fat_per_100
  }.freeze

  # The per-100 columns are decimal(8, 2), so the round trip through them is
  # lossy: 10 g of protein per 30 g stores 33.33 and converts back to 9.999.
  # Two decimals is far coarser than that drift for any realistic portion,
  # so the value the user typed comes back unchanged at this precision.
  PORTION_DISPLAY_PRECISION = 2

  belongs_to :user
  has_many :entries, dependent: :nullify

  before_validation :nilify_blank_state
  before_validation :convert_portion_macros
  before_validation :derive_kcal_per_100_if_blank

  validates :name, presence: true
  validates :state, inclusion: { in: STATES }, allow_nil: true
  validates :unit, inclusion: { in: UNITS }
  validates :portion_amount, presence: true,
    numericality: { greater_than: 0, less_than: DECIMAL_COLUMN_LIMIT }
  validates(*MACRO_FIELDS, presence: true,
    numericality: { greater_than_or_equal_to: 0, less_than: DECIMAL_COLUMN_LIMIT })
  validates :fiber_per_100, :sodium_per_100, :sugar_per_100,
    numericality: { greater_than_or_equal_to: 0, less_than: DECIMAL_COLUMN_LIMIT, allow_nil: true }

  scope :active, -> { where(archived_at: nil) }

  PORTION_MACRO_SOURCES.each do |portion_field, per_100_field|
    # Reads back what was typed for one portion. A value typed in this same
    # request wins over the stored one, so a form re-rendered after a
    # validation error still shows exactly what the user entered — including
    # a blank, and including something that is not a number at all.
    define_method(portion_field) do
      return portion_macro_inputs[portion_field] if portion_macro_inputs.key?(portion_field)

      per_100 = public_send(per_100_field)
      return nil if per_100.blank? || portion_amount.blank?

      (per_100.to_d * portion_amount.to_d / 100).round(PORTION_DISPLAY_PRECISION)
    end

    define_method("#{portion_field}=") do |value|
      portion_macro_inputs[portion_field] = value
    end
  end

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

  # Rereading the row drops what was typed into the portion fields, so the
  # readers go back to deriving from storage. Without this a reloaded record
  # would keep answering with the values of a request that is over.
  def reload(...)
    @portion_macro_inputs = nil
    super
  end

  # "g" or "ml" — the abbreviation used everywhere an amount is shown next
  # to this food (the entry form, entry rows, the day view).
  def unit_abbreviation
    UNIT_ABBREVIATIONS.fetch(unit)
  end

  # "kg" or "l" — the ×1000 unit offered beside the base one on the entry
  # form (see EntriesHelper#entry_unit_options).
  def multiple_unit_abbreviation
    UNIT_MULTIPLES.fetch(unit)
  end

  # "por cada 100 g" / "por cada 100 ml" — how the stored figures read on
  # the catalog card, which shows them as they are normalised rather than
  # per portion.
  def per_100_label
    "por cada 100 #{unit_abbreviation}"
  end

  # Declaring a portion that is not simply 100 is the signal that the user
  # thinks of this food in portions ("1 unidad son 30 g"), so that is what
  # the entry form counts in by default — see EntriesHelper#default_entry_unit.
  def counts_in_portions?
    portion_amount.present? && portion_amount != DEFAULT_PORTION_AMOUNT
  end

  private
    def portion_macro_inputs
      @portion_macro_inputs ||= {}
    end

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

    # Portion figures in, per-100 figures stored. Only the fields actually
    # assigned in this request are converted: a caller that sets a per-100
    # column directly (the seeds, a factory, a data fix) is writing the
    # normalised value itself and must not have it scaled again.
    #
    # An unusable portion (blank, zero, not a number) converts nothing: the
    # per-100 columns keep whatever they held, and #portion_amount's own
    # validation reports the problem rather than this inventing a basis.
    def convert_portion_macros
      return if portion_macro_inputs.empty?

      return if portion_amount.blank?

      portion = portion_amount.to_d
      return unless portion.positive?

      typed = portion_macro_inputs.to_h { |field, value| [ field, casted_portion_value(field, value) ] }

      typed.each do |portion_field, value|
        per_100_field = PORTION_MACRO_SOURCES.fetch(portion_field)
        public_send("#{per_100_field}=", value.nil? ? nil : (value * 100 / portion).round(2))
      end

      derive_kcal_from_portion(typed, portion)
    end

    # Cast as assigning the column would, except that a string which is not
    # a number at all lands as nil rather than as the silent zero the decimal
    # type would read it as — the presence validation then reports it, and
    # the form shows the user their own text back.
    def casted_portion_value(portion_field, value)
      return nil if value.blank?
      return nil if value.is_a?(::String) && Float(value, exception: false).nil?

      self.class.type_for_attribute(PORTION_MACRO_SOURCES.fetch(portion_field)).cast(value)
    end

    # The optional calorie figure is derived from the macros AS TYPED, for
    # the portion, and only then scaled: deriving it from the rounded per-100
    # figures instead would answer 499.97 where the portion's own 150 kcal is
    # exactly 500. Runs only when the calorie field was left blank and all
    # three macros are there to derive it from — #derive_kcal_per_100_if_blank
    # still covers a caller that assigns the per-100 columns directly.
    def derive_kcal_from_portion(typed, portion)
      return if kcal_per_100.present?
      return if %i[protein_per_portion carbs_per_portion fat_per_portion].any? { |field| typed[field].nil? }

      per_portion = MacroSplit.kcal_from_exact(
        protein_g: typed[:protein_per_portion], carbs_g: typed[:carbs_per_portion], fat_g: typed[:fat_per_portion]
      )
      self.kcal_per_100 = (per_portion * 100 / portion).round(2)
    end

    # kcal_per_100 is taken from the label rather than computed, because
    # labels account for fiber, sugar alcohols and rounding that the 4/4/9
    # calculation does not (see docs/superpowers/specs — the macro-tracker
    # design doc). When there is no label, it is derived once here and
    # stored, so every downstream reader still finds a plain number.
    #
    # Runs after #convert_portion_macros, so the macros it reads are already
    # normalised per 100 — the 4/4/9 split is linear, so deriving from the
    # per-100 figures gives the same answer as deriving from the portion's
    # and converting.
    #
    # `.blank?` (not `.nil?`) is deliberate: an unsubmitted number_field
    # posts "", which the decimal type casts to nil, so this must catch
    # both. A genuinely supplied 0 is not blank and is left untouched —
    # a label really can round a trace amount down to 0 kcal.
    def derive_kcal_per_100_if_blank
      return unless kcal_per_100.blank?
      return if protein_per_100.blank? || carbs_per_100.blank? || fat_per_100.blank?

      self.kcal_per_100 = MacroSplit.kcal_from_exact(
        protein_g: protein_per_100, carbs_g: carbs_per_100, fat_g: fat_per_100
      )
    end
end
