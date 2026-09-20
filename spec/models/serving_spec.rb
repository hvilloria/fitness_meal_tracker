require "rails_helper"

RSpec.describe Serving, type: :model do
  subject(:serving) { build(:serving) }

  it { is_expected.to belong_to(:food) }
  it { is_expected.to validate_presence_of(:label) }

  it "requires grams above zero" do
    expect(build(:serving, grams: 0)).not_to be_valid
    expect(build(:serving, grams: -5)).not_to be_valid
  end

  describe "the default serving" do
    let(:food) { create(:food) }

    it "clears the previous default when another is set" do
      first = create(:serving, food: food, label: "1 feta", is_default: true)
      second = create(:serving, food: food, label: "1 porción", is_default: true)

      expect(first.reload.is_default).to be(false)
      expect(second.reload.is_default).to be(true)
    end

    it "leaves other foods alone" do
      other_food_serving = create(:serving, is_default: true)
      create(:serving, food: food, is_default: true)

      expect(other_food_serving.reload.is_default).to be(true)
    end

    it "is exposed through Food#default_serving" do
      create(:serving, food: food, label: "1 feta", is_default: false)
      chosen = create(:serving, food: food, label: "1 porción", is_default: true)

      expect(food.reload.default_serving).to eq(chosen)
    end


    it "allows each food to have its own default serving independently" do
      other_food = create(:food)
      food_default = create(:serving, food: food, label: "1 feta", is_default: true)
      other_default = create(:serving, food: other_food, label: "1 slice", is_default: true)

      expect(food.reload.default_serving).to eq(food_default)
      expect(other_food.reload.default_serving).to eq(other_default)
    end

    it "is rejected by the database when the callback is bypassed via update_column" do
      # Create one default serving
      first = create(:serving, food: food, label: "1 feta", is_default: true)
      second = create(:serving, food: food, label: "1 porción", is_default: false)

      # Attempt to set the second serving as default by bypassing the before_save callback
      # The partial unique index should prevent this
      expect {
        second.update_column(:is_default, true)
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
