FactoryBot.define do
  factory :goal do
    user
    protein_g { 156 }
    carbs_g { 313 }
    fat_g { 69 }
    is_default { true }
    effective_from { Date.current }
  end
end
