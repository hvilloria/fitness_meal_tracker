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
          name: "Port Salut light", brand: "La Serenísima",
          kcal_per_100: 220, protein_per_100: 27, carbs_per_100: 0, fat_per_100: 12,
          servings_attributes: { "0" => { label: "1 feta", grams: 30, is_default: "1" } }
        }
      }
    }.to change(Food, :count).by(1)

    food = Food.last
    expect(food.user).to eq(user)
    expect(food.servings.first.label).to eq("1 feta")
  end

  it "creates a food without calories, deriving them from the macros" do
    user

    post foods_path, params: {
      food: { name: "Sin calorías", protein_per_100: 10, carbs_per_100: 10, fat_per_100: 10 }
    }

    food = Food.find_by(name: "Sin calorías")
    expect(food.kcal_per_100).to eq(170.0)

    get foods_path

    expect(response.body).to include("170")
  end

  it "re-renders the form when the food is invalid" do
    user

    post foods_path, params: { food: { name: "" } }

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "shows a real Spanish validation message rather than a missing-translation fallback" do
    user

    post foods_path, params: { food: { name: "" } }

    expect(response.body).to include("no puede estar en blanco")
    expect(response.body).not_to include("Translation missing")
  end

  it "shows a real Spanish message for an invalid nested serving, not a half-English fallback" do
    user

    post foods_path, params: {
      food: {
        name: "Con porción inválida",
        kcal_per_100: 220, protein_per_100: 27, carbs_per_100: 0, fat_per_100: 12,
        servings_attributes: { "0" => { label: "", grams: 10 } }
      }
    }

    expect(response.body).to include("Etiqueta no puede estar en blanco")
  end

  it "rejects an out-of-range decimal instead of raising on save" do
    user

    expect {
      post foods_path, params: {
        food: {
          name: "Fuera de rango",
          kcal_per_100: "1234567.89", protein_per_100: 27, carbs_per_100: 0, fat_per_100: 12
        }
      }
    }.not_to raise_error

    expect(response).to have_http_status(:unprocessable_content)
    expect(Food.where(name: "Fuera de rango")).not_to exist
  end

  it "accepts a comma as the decimal separator for a macro" do
    user

    post foods_path, params: {
      food: {
        name: "Coma decimal",
        kcal_per_100: "220", protein_per_100: "12,5", carbs_per_100: 0, fat_per_100: 12
      }
    }

    expect(Food.find_by(name: "Coma decimal").protein_per_100).to eq(12.5)
  end

  it "accepts a comma as the decimal separator for a serving's grams (index-keyed hash shape)" do
    user

    post foods_path, params: {
      food: {
        name: "Porción con coma",
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
        name: "Porción con coma en array",
        kcal_per_100: 220, protein_per_100: 27, carbs_per_100: 0, fat_per_100: 12,
        servings_attributes: [ { label: "1 feta", grams: "12,5", is_default: "1" } ]
      }
    }

    expect(response).not_to have_http_status(:internal_server_error)
    expect(Food.find_by(name: "Porción con coma en array").servings.first.grams).to eq(12.5)
  end

  it "creates a food with the milliliters unit and saves it" do
    user

    post foods_path, params: {
      food: {
        name: "Coca-Cola", unit: "milliliters",
        kcal_per_100: 42, protein_per_100: 0, carbs_per_100: 10.6, fat_per_100: 0
      }
    }

    expect(Food.find_by(name: "Coca-Cola").unit).to eq("milliliters")
  end

  it "defaults a food's unit to grams when none is submitted" do
    user

    post foods_path, params: {
      food: { name: "Sin unidad", kcal_per_100: 220, protein_per_100: 27, carbs_per_100: 0, fat_per_100: 12 }
    }

    expect(Food.find_by(name: "Sin unidad").unit).to eq("grams")
  end

  it "labels the per-100 fields according to the food's unit" do
    create(:food, :milliliters, user: user, name: "Coca-Cola")

    get new_food_path

    expect(response.body).to include("por cada 100 g")

    get edit_food_path(Food.find_by(name: "Coca-Cola"))

    expect(response.body).to include("por cada 100 ml")
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

  it "does not 500 when the food param arrives as a bare scalar" do
    user

    post foods_path, params: { food: "boom" }

    expect(response).to have_http_status(:bad_request)
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
