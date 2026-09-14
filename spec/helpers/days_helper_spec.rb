require "rails_helper"

RSpec.describe DaysHelper, type: :helper do
  describe "#ring_dash_array" do
    it "fills half the ring at half the goal" do
      expect(helper.ring_dash_array(50, 100, 100)).to eq("50.0 100")
    end

    it "fills nothing at zero" do
      expect(helper.ring_dash_array(0, 100, 100)).to eq("0.0 100")
    end

    it "caps the arc at a full ring when the goal is exceeded" do
      expect(helper.ring_dash_array(150, 100, 100)).to eq("100.0 100")
    end

    it "fills nothing when the goal is zero rather than dividing by it" do
      expect(helper.ring_dash_array(50, 0, 100)).to eq("0.0 100")
    end
  end
end
