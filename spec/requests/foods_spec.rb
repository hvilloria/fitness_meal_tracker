require "rails_helper"

RSpec.describe "Foods", type: :request do
  let(:user) { sign_in_via_google(email: "a@example.com") }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ALLOWED_EMAILS").and_return("a@example.com")
  end

  it "lists only the signed-in user's active foods" do
    mine = create(:food, user: user, name: "Mi queso")
    create(:food, user: user, name: "Archivado", archived_at: Time.current)
    create(:food, name: "De otro")

    get foods_path

    expect(response.body).to include(mine.name)
    expect(response.body).not_to include("Archivado")
    expect(response.body).not_to include("De otro")
  end

  it "creates a food with a serving" do
    user

    expect {
      post foods_path, params: {
        food: {
          name: "Port Salut light", brand: "La Serenísima", state: "as_sold",
          kcal_per_100: 220, protein_per_100: 27, carbs_per_100: 0, fat_per_100: 12,
          servings_attributes: { "0" => { label: "1 feta", grams: 30, is_default: "1" } }
        }
      }
    }.to change(Food, :count).by(1)

    food = Food.last
    expect(food.user).to eq(user)
    expect(food.servings.first.label).to eq("1 feta")
  end

  it "re-renders the form when the food is invalid" do
    user

    post foods_path, params: { food: { name: "", state: "as_sold" } }

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "shows a real Spanish validation message rather than a missing-translation fallback" do
    user

    post foods_path, params: { food: { name: "", state: "as_sold" } }

    expect(response.body).to include("no puede estar en blanco")
    expect(response.body).not_to include("Translation missing")
  end

  it "rejects an out-of-range decimal instead of raising on save" do
    user

    expect {
      post foods_path, params: {
        food: {
          name: "Fuera de rango", state: "as_sold",
          kcal_per_100: "1234567.89", protein_per_100: 27, carbs_per_100: 0, fat_per_100: 12
        }
      }
    }.not_to raise_error

    expect(response).to have_http_status(:unprocessable_entity)
    expect(Food.where(name: "Fuera de rango")).not_to exist
  end

  it "accepts a comma as the decimal separator for a macro" do
    user

    post foods_path, params: {
      food: {
        name: "Coma decimal", state: "as_sold",
        kcal_per_100: "220", protein_per_100: "12,5", carbs_per_100: 0, fat_per_100: 12
      }
    }

    expect(Food.find_by(name: "Coma decimal").protein_per_100).to eq(12.5)
  end

  it "accepts a comma as the decimal separator for a serving's grams (index-keyed hash shape)" do
    user

    post foods_path, params: {
      food: {
        name: "Porción con coma", state: "as_sold",
        kcal_per_100: 220, protein_per_100: 27, carbs_per_100: 0, fat_per_100: 12,
        servings_attributes: { "0" => { label: "1 feta", grams: "12,5", is_default: "1" } }
      }
    }

    expect(Food.find_by(name: "Porción con coma").servings.first.grams).to eq(12.5)
  end

  it "accepts a comma as the decimal separator for a serving's grams (array shape)" do
    user

    # accepts_nested_attributes_for permits an array of hashes as well as the
    # index-keyed hash that this app's own fields_for generates; a raw HTTP
    # client (not the rendered form) can send this shape.
    post foods_path, params: {
      food: {
        name: "Porción con coma en array", state: "as_sold",
        kcal_per_100: 220, protein_per_100: 27, carbs_per_100: 0, fat_per_100: 12,
        servings_attributes: [ { label: "1 feta", grams: "12,5", is_default: "1" } ]
      }
    }

    expect(response).not_to have_http_status(:internal_server_error)
    expect(Food.find_by(name: "Porción con coma en array").servings.first.grams).to eq(12.5)
  end

  it "updates a food" do
    food = create(:food, user: user)

    patch food_path(food), params: { food: { name: "Nuevo nombre" } }

    expect(food.reload.name).to eq("Nuevo nombre")
  end

  it "archives rather than deletes" do
    food = create(:food, user: user)

    delete food_path(food)

    expect(food.reload.archived_at).to be_present
    expect(Food.count).to eq(1)
  end

  it "refuses to touch another user's food" do
    user
    other = create(:food)

    # config.action_dispatch.show_exceptions = :rescuable in test env means
    # ActiveRecord::RecordNotFound is rescued into a 404 response rather than
    # propagating to the spec, so assert on the response instead of the raise.
    get edit_food_path(other)

    expect(response).to have_http_status(:not_found)
  end
end
