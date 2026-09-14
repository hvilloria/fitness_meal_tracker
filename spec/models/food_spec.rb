require "rails_helper"

RSpec.describe Food, type: :model do
  subject(:food) { build(:food) }

  it { is_expected.to belong_to(:user) }
  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_presence_of(:state) }

  it "requires the four core macro fields" do
    food = build(:food, kcal_per_100: nil, protein_per_100: nil, carbs_per_100: nil, fat_per_100: nil)

    expect(food).not_to be_valid
    expect(food.errors.attribute_names)
      .to include(:kcal_per_100, :protein_per_100, :carbs_per_100, :fat_per_100)
  end

  it "rejects negative macro values" do
    expect(build(:food, protein_per_100: -1)).not_to be_valid
  end

  it "allows the optional micronutrients to be blank" do
    expect(build(:food, fiber_per_100: nil, sodium_per_100: nil, sugar_per_100: nil)).to be_valid
  end

  describe "#display_name" do
    it "includes the brand when there is one" do
      expect(build(:food, name: "Port Salut light", brand: "La Serenísima").display_name)
        .to eq("Port Salut light (La Serenísima)")
    end

    it "is just the name for a generic food" do
      expect(build(:food, name: "Pechuga de pollo", brand: nil).display_name)
        .to eq("Pechuga de pollo")
    end
  end

  describe ".active" do
    it "excludes archived foods" do
      live = create(:food)
      create(:food, archived_at: Time.current)

      expect(Food.active).to contain_exactly(live)
    end
  end
end
