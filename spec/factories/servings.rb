FactoryBot.define do
  factory :serving do
    food
    label { "1 feta" }
    grams { 30 }
    is_default { false }
  end
end
