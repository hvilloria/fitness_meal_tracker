module NormalizesDecimalParams
  extend ActiveSupport::Concern

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
end
