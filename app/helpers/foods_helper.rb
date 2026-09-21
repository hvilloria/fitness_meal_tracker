module FoodsHelper
  # A decimal shown back in a form field: "30" rather than "30.0", "12.5"
  # rather than "12.50". The stored value is a BigDecimal whose #to_s would
  # print trailing zeros the user never typed.
  def food_decimal_field_value(value)
    return value unless value.is_a?(Numeric)

    number_with_precision(value, precision: Food::PORTION_DISPLAY_PRECISION, strip_insignificant_zeros: true)
  end
end
