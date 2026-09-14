require "rails_helper"

RSpec.describe "Entries", type: :request do
  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ALLOWED_EMAILS").and_return("a@example.com")
    sign_in_via_google(email: "a@example.com")
    create(:goal, user: User.last, is_default: true)
  end

  def user = User.last

  it "logs a catalog food by weight" do
    food = create(:food, user: user)

    expect {
      post entries_path, params: { entry: { food_id: food.id, meal: "lunch", grams: 40 } }
    }.to change(Entry, :count).by(1)

    entry = Entry.last
    expect(entry.protein_g).to eq(10.8)
    expect(entry.day_log.user).to eq(user)
  end

  it "resolves a serving into grams" do
    food = create(:food, user: user)
    serving = create(:serving, food: food, label: "1 feta", grams: 30)

    post entries_path, params: { entry: { food_id: food.id, meal: "snack", serving_id: serving.id, quantity: 2 } }

    entry = Entry.last
    expect(entry.grams).to eq(60)
    expect(entry.serving_label).to eq("2 × 1 feta")
  end

  it "logs an ad-hoc entry from typed macros" do
    post entries_path, params: {
      entry: { meal: "dinner", food_name_snapshot: "Pizza muzza", protein_g: 100, carbs_g: 100, fat_g: 100 }
    }

    expect(Entry.last.kcal).to eq(1700)
    expect(Entry.last.food_id).to be_nil
  end

  it "answers a Turbo Stream request without leaving the form" do
    food = create(:food, user: user)

    post entries_path,
      params: { entry: { food_id: food.id, meal: "lunch", grams: 40 } },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include("turbo-stream")
  end

  it "refuses a food belonging to someone else" do
    other_food = create(:food)

    # config.action_dispatch.show_exceptions = :rescuable in test env means
    # ActiveRecord::RecordNotFound is rescued into a 404 response rather than
    # propagating to the spec — see the same note in foods_spec.rb.
    post entries_path, params: { entry: { food_id: other_food.id, meal: "lunch", grams: 40 } }

    expect(response).to have_http_status(:not_found)
  end

  it "deletes an entry" do
    food = create(:food, user: user)
    post entries_path, params: { entry: { food_id: food.id, meal: "lunch", grams: 40 } }
    entry = Entry.last

    expect { delete entry_path(entry) }.to change(Entry, :count).by(-1)
  end

  it "shows recently logged foods on the form" do
    food = create(:food, user: user, name: "Pechuga de pollo")
    post entries_path, params: { entry: { food_id: food.id, meal: "lunch", grams: 190 } }

    get new_entry_path

    expect(response.body).to include("Pechuga de pollo")
  end

  it "carries the last weight used onto the food option" do
    food = create(:food, user: user, name: "Pechuga de pollo")
    post entries_path, params: { entry: { food_id: food.id, meal: "lunch", grams: 190 } }

    get new_entry_path

    expect(response.body).to include("data-last-grams=\"190.0\"")
  end

  it "accepts a comma as the decimal separator for grams" do
    food = create(:food, user: user)

    post entries_path, params: { entry: { food_id: food.id, meal: "lunch", grams: "12,5" } }

    expect(Entry.last.grams).to eq(12.5)
  end

  it "accepts a comma as the decimal separator for typed macros" do
    post entries_path, params: {
      entry: { meal: "dinner", food_name_snapshot: "Pizza muzza", protein_g: "12,5", carbs_g: "10", fat_g: "5" }
    }

    expect(Entry.last.protein_g).to eq(12.5)
  end

  it "does not raise when meal arrives as an Array on the new form" do
    get new_entry_path, params: { meal: [ "lunch", "dinner" ] }

    expect(response).to have_http_status(:ok)
  end

  it "does not raise when meal arrives as a Hash on the new form" do
    get new_entry_path, params: { meal: { "foo" => "bar" } }

    expect(response).to have_http_status(:ok)
  end
end
