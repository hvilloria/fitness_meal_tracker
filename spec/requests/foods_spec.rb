require "rails_helper"

RSpec.describe "Foods", type: :request do
  let(:user) { sign_in_via_google(email: "a@example.com") }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ALLOWED_EMAILS").and_return("a@example.com")
  end

  # The portion field lives inside its own label, which is the whole
  # sentence "Los valores son por cada [30] g" — asserting on the page as a
  # whole would match those letters anywhere.
  def portion_label(body)
    body[/<label[^>]*class="portion".*?<\/label>/m].to_s
  end

  it "lists every active food in the shared catalog, including another user's" do
    mine = create(:food, user: user, name: "Mi queso")
    create(:food, user: user, name: "Archivado", archived_at: Time.current)
    other = create(:food, name: "De otro")

    get foods_path

    expect(response.body).to include(mine.name)
    expect(response.body).to include(other.name)
    expect(response.body).not_to include("Archivado")
  end

  it "shows the edit control for your own food" do
    mine = create(:food, user: user, name: "Mi queso")

    get foods_path

    expect(response.body).to include(edit_food_path(mine))
  end

  it "hides the edit control and names the owner for a food you do not own" do
    user
    owner = create(:user, name: "Ana")
    other = create(:food, user: owner, name: "De otro")

    get foods_path

    expect(response.body).not_to include(edit_food_path(other))
    expect(response.body).to include("de Ana")
  end

  it "creates a food from the figures for one portion" do
    user

    expect {
      post foods_path, params: {
        food: {
          name: "Port Salut light", brand: "La Serenísima", portion_amount: "30",
          kcal_per_portion: 150, protein_per_portion: 10, carbs_per_portion: 5, fat_per_portion: 10
        }
      }
    }.to change(Food, :count).by(1)

    food = Food.find_by!(name: "Port Salut light")
    expect(food.user).to eq(user)
    expect(food.portion_amount).to eq(30)
  end

  describe "the portion the typed figures describe" do
    it "normalises the portion's macros to per-100 storage" do
      user

      post foods_path, params: {
        food: {
          name: "Queso", portion_amount: "30",
          protein_per_portion: "10", carbs_per_portion: "5", fat_per_portion: "10"
        }
      }

      food = Food.find_by(name: "Queso")
      expect(food.protein_per_100).to eq(33.33)
      expect(food.carbs_per_100).to eq(16.67)
      expect(food.fat_per_100).to eq(33.33)
    end

    it "shows the edit form the same figures that were typed" do
      user

      post foods_path, params: {
        food: {
          name: "Queso", portion_amount: "30",
          protein_per_portion: "10", carbs_per_portion: "5", fat_per_portion: "10"
        }
      }

      get edit_food_path(Food.find_by(name: "Queso"))

      expect(response.body).to include('value="30"')
      expect(response.body).to include('value="10"')
      expect(response.body).to include('value="5"')
    end

    it "defaults the portion to 100, so a per-100 label needs no thought" do
      user

      post foods_path, params: {
        food: {
          name: "Etiqueta por 100",
          kcal_per_portion: 220, protein_per_portion: 27, carbs_per_portion: 0, fat_per_portion: 12
        }
      }

      food = Food.find_by(name: "Etiqueta por 100")
      expect(food.portion_amount).to eq(100)
      expect(food.protein_per_100).to eq(27)
      expect(food.kcal_per_100).to eq(220)
    end

    it "offers 100 as the portion on a brand new food's form" do
      user

      get new_food_path

      expect(response.body[/<label[^>]*class="portion".*?<\/label>/m]).to include('value="100"')
    end

    it "takes the number out of a portion typed with its unit" do
      user

      post foods_path, params: {
        food: {
          name: "Con unidad", portion_amount: "30 g",
          protein_per_portion: "10", carbs_per_portion: "5", fat_per_portion: "10"
        }
      }

      expect(Food.find_by(name: "Con unidad").portion_amount).to eq(30)
    end

    it "accepts a comma as the decimal separator for the portion" do
      user

      post foods_path, params: {
        food: {
          name: "Coma y unidad", portion_amount: "1,5 g",
          protein_per_portion: "1", carbs_per_portion: "0", fat_per_portion: "0"
        }
      }

      expect(Food.find_by(name: "Coma y unidad").portion_amount).to eq(1.5)
    end

    it "rejects a portion that is not a number at all" do
      user

      post foods_path, params: {
        food: {
          name: "Sin número", portion_amount: "treinta",
          protein_per_portion: "10", carbs_per_portion: "5", fat_per_portion: "10"
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(Food.find_by(name: "Sin número")).to be_nil
    end

    it "rejects a portion of zero rather than dividing by it" do
      user

      expect {
        post foods_path, params: {
          food: {
            name: "Porción cero", portion_amount: "0",
            protein_per_portion: "10", carbs_per_portion: "5", fat_per_portion: "10"
          }
        }
      }.not_to raise_error

      expect(response).to have_http_status(:unprocessable_content)
      expect(Food.find_by(name: "Porción cero")).to be_nil
    end

    it "derives the optional calories from the portion's macros, not from per-100 figures" do
      user

      post foods_path, params: {
        food: {
          name: "Sin calorías por porción", portion_amount: "30",
          protein_per_portion: "10", carbs_per_portion: "5", fat_per_portion: "10"
        }
      }

      food = Food.find_by(name: "Sin calorías por porción")
      # 10 P + 5 C + 10 G is 150 kcal for the portion, which is 500 per 100 g.
      expect(food.kcal_per_100).to eq(500)
      expect(food.kcal_per_portion).to eq(150)
    end
  end

  it "creates a food without calories, deriving them from the macros" do
    user

    post foods_path, params: {
      food: { name: "Sin calorías", protein_per_portion: 10, carbs_per_portion: 10, fat_per_portion: 10 }
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

  it "rejects an out-of-range decimal instead of raising on save" do
    user

    expect {
      post foods_path, params: {
        food: {
          name: "Fuera de rango",
          kcal_per_portion: "1234567.89", protein_per_portion: 27, carbs_per_portion: 0, fat_per_portion: 12
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
        kcal_per_portion: "220", protein_per_portion: "12,5", carbs_per_portion: 0, fat_per_portion: 12
      }
    }

    expect(Food.find_by(name: "Coma decimal").protein_per_100).to eq(12.5)
  end

  it "creates a food with the milliliters unit and saves it" do
    user

    post foods_path, params: {
      food: {
        name: "Coca-Cola", unit: "milliliters",
        kcal_per_portion: 42, protein_per_portion: 0, carbs_per_portion: 10.6, fat_per_portion: 0
      }
    }

    expect(Food.find_by(name: "Coca-Cola").unit).to eq("milliliters")
  end

  it "defaults a food's unit to grams when none is submitted" do
    user

    post foods_path, params: {
      food: { name: "Sin unidad", kcal_per_portion: 220, protein_per_portion: 27, carbs_per_portion: 0, fat_per_portion: 12 }
    }

    expect(Food.find_by(name: "Sin unidad").unit).to eq("grams")
  end

  it "names the portion's unit after the food's own unit" do
    create(:food, :milliliters, user: user, name: "Coca-Cola")

    get new_food_path

    expect(portion_label(response.body)).to include("Los valores son por cada")
    expect(portion_label(response.body)).to match(/>\s*g\s*</)

    get edit_food_path(Food.find_by(name: "Coca-Cola"))

    expect(portion_label(response.body)).to match(/>\s*ml\s*</)
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
    expect(Food.exists?(food.id)).to be(true)
  end

  it "does not 500 when the food param arrives as a bare scalar" do
    user

    post foods_path, params: { food: "boom" }

    expect(response).to have_http_status(:bad_request)
  end

  it "refuses to edit another user's food" do
    user
    other = create(:food)

    # config.action_dispatch.show_exceptions = :rescuable in test env means
    # ActiveRecord::RecordNotFound is rescued into a 404 response rather than
    # propagating to the spec, so assert on the response instead of the raise.
    get edit_food_path(other)

    expect(response).to have_http_status(:not_found)
  end

  it "refuses to update another user's food" do
    user
    other = create(:food, name: "De otro")

    patch food_path(other), params: { food: { name: "Hackeado" } }

    expect(response).to have_http_status(:not_found)
    expect(other.reload.name).to eq("De otro")
  end

  it "refuses to archive another user's food" do
    user
    other = create(:food)

    delete food_path(other)

    expect(response).to have_http_status(:not_found)
    expect(other.reload.archived_at).to be_nil
  end
end
