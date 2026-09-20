module NormalizesDecimalParams
  extend ActiveSupport::Concern

  # A number with the unit typed after it: "30g", "30 g", "1.5 ml". The unit
  # carries no information the field does not already state, and the number
  # in front of it is unambiguous, so it is taken and the letters dropped.
  # Anything else — "thirty", "3 0", "30g20" — does not match and is left
  # exactly as typed, so validation still reports it rather than this
  # quietly inventing a value.
  AMOUNT_WITH_UNIT = /\A\s*(\d+(?:\.\d+)?)\s*[[:alpha:]]*\s*\z/

  private
    # Spanish-locale keyboards produce "12,5". Accept it rather than
    # rejecting what the user's own keypad gives them.
    def normalize_decimals(attributes, *keys)
      keys.each do |key|
        value = attributes[key]
        attributes[key] = value.tr(",", ".") if value.is_a?(String)
      end
      attributes
    end

    # Runs after #normalize_decimals, so "1,5 g" is already "1.5 g" by the
    # time the unit is stripped off it.
    def strip_unit_suffixes(attributes, *keys)
      keys.each do |key|
        value = attributes[key]
        next unless value.is_a?(String)

        match = AMOUNT_WITH_UNIT.match(value)
        attributes[key] = match[1] if match
      end
      attributes
    end
end
