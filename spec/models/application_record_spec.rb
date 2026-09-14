require "rails_helper"

RSpec.describe ApplicationRecord, type: :model do
  it "runs the application in the Buenos Aires time zone" do
    expect(Time.zone.name).to eq("America/Argentina/Buenos_Aires")
  end

  it "stores timestamps in UTC" do
    expect(ActiveRecord.default_timezone).to eq(:utc)
  end
end
