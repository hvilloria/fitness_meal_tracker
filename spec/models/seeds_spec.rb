require "rails_helper"

# The starter catalog is quoted from USDA figures PER 100 g, so loading it
# must leave a portion of 100 and the stored values untouched — the portion
# model must not have quietly rescaled the seeds.
RSpec.describe "db/seeds", type: :model do
  it "seeds the starter catalog per 100 g, with a portion of 100" do
    user = create(:user)

    Rails.application.load_seed

    chicken = user.foods.find_by(name: "Pechuga de pollo")
    expect(chicken).to have_attributes(
      portion_amount: 100, kcal_per_100: 165, protein_per_100: 31.0,
      carbs_per_100: 0, fat_per_100: 3.6, state: "cooked"
    )

    expect(user.foods.pluck(:name, :portion_amount))
      .to contain_exactly(
        [ "Pechuga de pollo", 100 ], [ "Muslo de pollo", 100 ], [ "Bola de lomo", 100 ]
      )
  end

  it "is idempotent" do
    create(:user)

    2.times { Rails.application.load_seed }

    expect(Food.count).to eq(3)
  end
end
