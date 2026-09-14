require "rails_helper"

RSpec.describe "Days", type: :request do
  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ALLOWED_EMAILS").and_return("a@example.com")
  end

  def sign_in
    sign_in_via_google(email: "a@example.com")
  end

  it "redirects to the goal form when the user has no default goal" do
    sign_in

    get root_path

    expect(response).to redirect_to(edit_goal_path)
    expect(flash[:notice]).to be_present
  end

  it "shows the day and creates it for a user with a default goal" do
    sign_in
    create(:goal, user: User.last, is_default: true)

    expect { get root_path }.to change(DayLog, :count).by(1)

    expect(response).to have_http_status(:ok)
  end

  it "renders the requested date instead of today" do
    sign_in
    create(:goal, user: User.last, is_default: true)

    get root_path, params: { date: "2026-09-01" }

    expect(response.body).to include("2026-09-01")
  end

  describe "hostile date params fall back to today instead of erroring" do
    before do
      sign_in
      create(:goal, user: User.last, is_default: true)
    end

    it "handles an array param" do
      get root_path, params: { date: [ "x" ] }

      expect(response).to have_http_status(:ok)
    end

    it "handles a hash param" do
      get root_path, params: { date: { k: "v" } }

      expect(response).to have_http_status(:ok)
    end

    it "handles an over-long string" do
      get root_path, params: { date: "a" * 200 }

      expect(response).to have_http_status(:ok)
    end

    it "handles plain garbage" do
      get root_path, params: { date: "notadate" }

      expect(response).to have_http_status(:ok)
    end
  end

  it "recovers when DayLog.for loses a create race" do
    user = create(:user, day_cutoff_hour: 4)
    goal = create(:goal, user: user, is_default: true)

    travel_to Time.zone.local(2026, 9, 14, 10, 0) do
      date = DayLog.logical_date(user, Time.current)
      # Simulate another request winning the race: the row exists by the
      # time we insert, so our find_by "misses" once before the create.
      existing = create(:day_log, user: user, goal: goal, date: date)
      day_logs = user.day_logs
      allow(user).to receive(:day_logs).and_return(day_logs)
      allow(day_logs).to receive(:find_by).with(date: date).and_return(nil)
      allow(day_logs).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique)
      allow(day_logs).to receive(:find_by!).with(date: date).and_return(existing)

      expect(DayLog.for(user)).to eq(existing)
    end
  end
end
