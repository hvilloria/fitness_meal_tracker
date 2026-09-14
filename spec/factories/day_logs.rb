FactoryBot.define do
  factory :day_log do
    user
    goal { association :goal, user: user }
    date { Date.current }
  end
end
