require "rails_helper"

RSpec.describe "Entries", type: :request do
  let(:user) { sign_in_via_google(email: "a@example.com") }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ALLOWED_EMAILS").and_return("a@example.com")
    create(:goal, user: user, is_default: true)
  end

  it "logs a catalog food by weight" do
    food = create(:food, user: user)

    expect {
      post entries_path, params: { entry: { food_id: food.id, meal: "lunch", grams: 40 } }
    }.to change(Entry, :count).by(1)

    entry = Entry.last
    expect(entry.protein_g).to eq(10.8)
    expect(entry.day_log.user).to eq(user)
  end

  describe "counting an amount in unidades" do
    # 10 P / 5 C / 10 G over a 30 g portion, as the food form stores them.
    let(:food) do
      create(:food, user: user, name: "Queso", portion_amount: 30,
        kcal_per_100: 500, protein_per_100: 33.33, carbs_per_100: 16.67, fat_per_100: 33.33)
    end

    it "multiplies the portion and records what was counted" do
      post entries_path, params: {
        entry: { food_id: food.id, meal: "snack", quantity: "2", unit: "portion" }
      }

      entry = Entry.last
      expect(entry.grams).to eq(60)
      expect(entry.protein_g).to eq(20)
      expect(entry.carbs_g).to eq(10)
      expect(entry.fat_g).to eq(20)
      expect(entry.serving_label).to eq("2 unidades")
    end

    it "labels a single unit in the singular" do
      post entries_path, params: {
        entry: { food_id: food.id, meal: "snack", quantity: "1", unit: "portion" }
      }

      entry = Entry.last
      expect(entry.grams).to eq(30)
      expect(entry.serving_label).to eq("1 unidad")
    end

    it "keeps the label consistent with a fractional quantity" do
      post entries_path,
        params: { entry: { food_id: food.id, meal: "snack", quantity: "0,5", unit: "portion" } }

      entry = Entry.last
      expect(entry.grams).to eq(15)
      expect(entry.serving_label).to eq("0.5 unidades")
    end

    it "counts one portion when no quantity is typed at all" do
      post entries_path, params: { entry: { food_id: food.id, meal: "snack", unit: "portion" } }

      entry = Entry.last
      expect(entry.grams).to eq(30)
      expect(entry.serving_label).to eq("1 unidad")
    end
  end

  describe "the amount's unit selector" do
    it "stores the base unit as typed, with no label" do
      food = create(:food, user: user)

      post entries_path, params: { entry: { food_id: food.id, meal: "lunch", quantity: "47", unit: "base" } }

      entry = Entry.last
      expect(entry.grams).to eq(47)
      expect(entry.serving_label).to be_blank
    end

    it "logs a weight in the base unit of a per-100 food exactly as before" do
      food = create(:food, user: user)

      post entries_path, params: { entry: { food_id: food.id, meal: "lunch", quantity: "200", unit: "base" } }

      entry = Entry.last
      expect(entry.grams).to eq(200)
      expect(entry.protein_g).to eq(54)
      expect(entry.serving_label).to be_blank
    end

    it "multiplies the x1000 unit by a thousand and labels it in kg" do
      food = create(:food, user: user)

      post entries_path, params: { entry: { food_id: food.id, meal: "lunch", quantity: "0,5", unit: "x1000" } }

      entry = Entry.last
      expect(entry.grams).to eq(500)
      expect(entry.serving_label).to eq("0.5 kg")
    end

    it "labels the x1000 unit of a liquid in litres" do
      liquid = create(:food, :milliliters, user: user)

      post entries_path, params: { entry: { food_id: liquid.id, meal: "snack", quantity: "1.5", unit: "x1000" } }

      expect(Entry.last.serving_label).to eq("1.5 l")
    end

    it "falls back to the base unit for a unit value it does not know" do
      food = create(:food, user: user)

      post entries_path, params: {
        entry: { food_id: food.id, meal: "snack", quantity: "2", unit: "serving:whatever" }
      }

      entry = Entry.last
      expect(entry.grams).to eq(2)
      expect(entry.serving_label).to be_blank
    end

    it "carries each food's portion and default unit onto its option" do
      food = create(:food, user: user, portion_amount: 30)
      per_100 = create(:food, user: user, name: "Por 100", portion_amount: 100)

      get new_entry_path

      option = response.body[/<option[^>]*value="#{food.id}"[^>]*>/]
      expect(option).to include("data-multiple-unit=\"kg\"")
      expect(option).to include("data-portion=\"30.0\"")
      expect(option).to include('data-default-unit="portion"')
      expect(response.body[/<option[^>]*value="#{per_100.id}"[^>]*>/])
        .to include('data-default-unit="base"')
      expect(response.body).to include('name="entry[quantity]"')
      expect(response.body).to include('name="entry[unit]"')
    end

    # A food only reaches the server-rendered unit select when the form comes
    # back with one already chosen — an invalid submission. On a fresh form
    # nothing is selected yet, and the browser builds the list from the
    # option's data attributes (see entry_preview_controller.js#rebuildUnits).
    it "offers unidad, the base unit and the x1000 unit once a food is chosen" do
      food = create(:food, user: user, portion_amount: 30)

      post entries_path, params: { entry: { food_id: food.id, meal: "snack" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('data-grams="30.0" selected="selected" value="portion">unidad</option>')
      expect(response.body).to include('data-grams="1" value="base">g</option>')
      expect(response.body).to include('data-grams="1000" value="x1000">kg</option>')
    end

    it "starts on unidad for a food that declares a portion of its own" do
      food = create(:food, user: user, portion_amount: 30)

      post entries_path, params: { entry: { food_id: food.id, meal: "snack" } }

      expect(response.body).to include('selected="selected" value="portion">unidad</option>')
    end

    it "starts on the base unit for a food whose figures are per 100" do
      food = create(:food, user: user, portion_amount: 100)

      post entries_path, params: { entry: { food_id: food.id, meal: "snack" } }

      expect(response.body).to include('selected="selected" value="base">g</option>')
      expect(response.body).to include('data-grams="100.0" value="portion">unidad</option>')
    end

    it "carries the millilitre food's x1000 unit onto its option" do
      liquid = create(:food, :milliliters, user: user)
      post entries_path, params: { entry: { food_id: liquid.id, meal: "snack", grams: 330 } }

      get new_entry_path

      expect(response.body[/<option[^>]*value="#{liquid.id}"[^>]*>/]).to include("data-multiple-unit=\"l\"")
    end
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

  it "logs a food that belongs to someone else, from the shared catalog" do
    other_food = create(:food, kcal_per_100: 165, protein_per_100: 31, carbs_per_100: 0, fat_per_100: 3.6)

    expect {
      post entries_path, params: { entry: { food_id: other_food.id, meal: "lunch", grams: 100 } }
    }.to change(Entry, :count).by(1)

    entry = Entry.last
    expect(entry.food).to eq(other_food)
    expect(entry.protein_g).to eq(31)
    expect(entry.day_log.user).to eq(user)
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

  describe "food select membership" do
    it "offers another user's food in the shared catalog" do
      other_food = create(:food, name: "Alimento de otro")

      get new_entry_path

      expect(response.body).to include(other_food.name)
    end

    it "does not let another user's own logging surface their food in your recents" do
      other_user = create(:user)
      other_food = create(:food, user: other_user, name: "Comida de otro")
      other_goal = create(:goal, user: other_user, is_default: true)
      other_day_log = create(:day_log, user: other_user, goal: other_goal)
      create(:entry, day_log: other_day_log, food: other_food, meal: "lunch")

      expect(Food.recent_for(user)).not_to include(other_food)

      get new_entry_path

      # Still offered — the shared catalog, not the recents list.
      expect(response.body).to include(other_food.name)
    end

    it "offers a food that has never been logged, not just recent ones" do
      food = create(:food, user: user, name: "Pechuga de pollo")

      get new_entry_path

      expect(response.body).to include(food.name)
    end

    it "still offers a newly created food once another food has already been logged" do
      logged = create(:food, user: user, name: "Pollo ya usado")
      post entries_path, params: { entry: { food_id: logged.id, meal: "lunch", grams: 100 } }

      new_food = create(:food, user: user, name: "Alimento nuevo")

      get new_entry_path

      expect(response.body).to include(new_food.name)
    end

    it "orders recently logged foods before the rest of the catalog" do
      recent = create(:food, user: user, name: "Zapallo")
      post entries_path, params: { entry: { food_id: recent.id, meal: "lunch", grams: 100 } }
      other = create(:food, user: user, name: "Arroz")

      get new_entry_path

      body = response.body
      expect(body.index(recent.name)).to be < body.index(other.name)
    end

    it "keeps a food reachable once it drops out of Food.recent_for's 20-item cap" do
      dropped = create(:food, user: user, name: "Cayó del top 20")
      travel_to(1.hour.ago) { post entries_path, params: { entry: { food_id: dropped.id, meal: "lunch", grams: 10 } } }

      20.times do |i|
        food = create(:food, user: user, name: "Reciente #{i}")
        travel_to(i.minutes.ago) { post entries_path, params: { entry: { food_id: food.id, meal: "lunch", grams: 10 } } }
      end

      expect(Food.recent_for(user)).not_to include(dropped)

      get new_entry_path

      expect(response.body).to include(dropped.name)
    end

    it "excludes an archived, never-logged food from the full-catalog group" do
      archived = create(:food, user: user, name: "Archivado sin usar", archived_at: Time.current)

      get new_entry_path

      expect(response.body).not_to include(archived.name)
    end

    it "excludes an archived, previously-logged food from Food.recent_for" do
      archived = create(:food, user: user, name: "Archivado reciente")
      post entries_path, params: { entry: { food_id: archived.id, meal: "lunch", grams: 10 } }
      archived.update!(archived_at: Time.current)

      expect(Food.recent_for(user)).not_to include(archived)
    end
  end

  it "carries the last weight used onto the food option" do
    food = create(:food, user: user, name: "Pechuga de pollo")
    post entries_path, params: { entry: { food_id: food.id, meal: "lunch", grams: 190 } }

    get new_entry_path

    expect(response.body).to include("data-last-grams=\"190.0\"")
  end

  it "omits the last-weight data attribute for a food that has never been logged" do
    food = create(:food, user: user, name: "Nunca registrado")

    get new_entry_path

    tag = response.body[/<option[^>]*value="#{food.id}"[^>]*>/]
    expect(tag).to include("data-kcal=")
    expect(tag).not_to include("last-grams")
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

  describe "units (grams vs millilitres)" do
    it "shows the millilitres unit for a liquid food's option and entry row" do
      liquid = create(:food, :milliliters, user: user, name: "Coca-Cola")

      post entries_path, params: { entry: { food_id: liquid.id, meal: "snack", grams: 330 } }

      get new_entry_path

      expect(response.body).to include('data-unit="ml"')
      expect(response.body).to include("330 ml")
    end

    it "shows the grams unit for a solid food's entry row" do
      food = create(:food, user: user, name: "Pechuga de pollo")

      post entries_path, params: { entry: { food_id: food.id, meal: "snack", grams: 150 } }

      get new_entry_path

      expect(response.body).to include("150 g")
    end

    it "keeps the ad-hoc form's plain amount field, with no unit selector" do
      get new_entry_path, params: { ad_hoc: "1" }

      expect(response.body).not_to include('name="entry[unit]"')
      expect(response.body).not_to include('name="entry[quantity]"')
    end

    it "saves an ad-hoc entry with no unit at all" do
      expect {
        post entries_path, params: {
          entry: { meal: "dinner", food_name_snapshot: "Pizza muzza", protein_g: 10, carbs_g: 10, fat_g: 10, grams: 200 }
        }
      }.to change(Entry, :count).by(1)

      entry = Entry.last
      expect(entry.grams).to eq(200)
      expect(entry.serving_label).to be_blank
    end

    it "shows no unit on an ad-hoc entry's amount field" do
      get new_entry_path, params: { ad_hoc: "1" }

      expect(response.body).to include("Peso — opcional")
      expect(response.body).not_to include("Peso (g)")
    end
  end

  describe "ad-hoc entries" do
    it "renders the ad-hoc form, not the catalog select, for ?ad_hoc=1" do
      get new_entry_path, params: { ad_hoc: "1" }

      expect(response.body).to include('name="entry[food_name_snapshot]"')
      expect(response.body).not_to include('name="entry[food_id]"')
    end

    it "renders the catalog form, not the ad-hoc fields, without ?ad_hoc" do
      get new_entry_path

      expect(response.body).to include('name="entry[food_id]"')
      expect(response.body).not_to include('name="entry[food_name_snapshot]"')
    end

    it "creates an entry with no food_id and calories derived as 4p + 4c + 9f" do
      expect {
        post entries_path, params: {
          entry: { meal: "dinner", food_name_snapshot: "Pizza muzza", protein_g: 100, carbs_g: 100, fat_g: 100 }
        }
      }.to change(Entry, :count).by(1)

      entry = Entry.last
      expect(entry.food_id).to be_nil
      expect(entry.protein_g).to eq(100)
      expect(entry.carbs_g).to eq(100)
      expect(entry.fat_g).to eq(100)
      expect(entry.kcal).to eq(1700)
    end

    it "accepts a comma as the decimal separator" do
      post entries_path, params: {
        entry: { meal: "dinner", food_name_snapshot: "Pizza muzza", protein_g: "12,5", carbs_g: "10", fat_g: "5" }
      }

      expect(Entry.last.protein_g).to eq(12.5)
    end

    it "does not 500 on a hostile ad_hoc query param shape" do
      get new_entry_path, params: { ad_hoc: [ "x" ] }

      expect(response).to have_http_status(:ok)
    end

    it "rejects an entry with no name and re-renders the form" do
      expect {
        post entries_path, params: { entry: { meal: "dinner", protein_g: 100, carbs_g: 100, fat_g: 100 } }
      }.not_to change(Entry, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('name="entry[food_name_snapshot]"')
    end
  end

  describe "decimal(8, 2) overflow" do
    it "rejects an ad-hoc macro that is out of range instead of raising on save" do
      expect {
        post entries_path, params: {
          entry: { meal: "dinner", food_name_snapshot: "Pizza muzza", protein_g: "9999999", carbs_g: 10, fat_g: 10 }
        }
      }.not_to raise_error

      expect(response).to have_http_status(:unprocessable_content)
      expect(Entry.count).to eq(0)
    end

    it "rejects a catalog weight whose derived kcal would overflow, even though grams itself is in range" do
      food = create(:food, user: user, kcal_per_100: 900, protein_per_100: 0, carbs_per_100: 0, fat_per_100: 100)

      expect {
        post entries_path, params: { entry: { food_id: food.id, meal: "lunch", grams: "999999" } }
      }.not_to raise_error

      expect(response).to have_http_status(:unprocessable_content)
      expect(Entry.count).to eq(0)
    end
  end

  it "orders today's entries chronologically, not by the per-meal position that collides across meals" do
    food = create(:food, user: user)

    travel_to(2.hours.ago) { post entries_path, params: { entry: { food_id: food.id, meal: "breakfast", grams: 11 } } }
    travel_to(1.hour.ago) { post entries_path, params: { entry: { food_id: food.id, meal: "breakfast", grams: 22 } } }
    travel_to(30.minutes.ago) { post entries_path, params: { entry: { food_id: food.id, meal: "lunch", grams: 33 } } }

    get new_entry_path

    body = response.body
    positions = [ body.index("11 g"), body.index("22 g"), body.index("33 g") ]

    expect(positions).to all(be_present)
    expect(positions).to eq(positions.sort)
  end

  it "does not 500 on an invalid submission accepted only as text/vnd.turbo-stream.html" do
    post entries_path,
      params: { entry: { meal: "dinner", protein_g: 100, carbs_g: 100, fat_g: 100 } },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "returns the catalog form, not the ad-hoc fields, after an ad-hoc save" do
    post entries_path,
      params: { entry: { meal: "dinner", food_name_snapshot: "Pizza muzza", protein_g: 100, carbs_g: 100, fat_g: 100 } },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response.body).to include('name="entry[food_id]"')
    expect(response.body).not_to include('name="entry[food_name_snapshot]"')
  end

  it "resets the form after a successful Turbo save instead of keeping the logged item" do
    food = create(:food, user: user, name: "Pechuga de pollo")

    post entries_path,
      params: { entry: { food_id: food.id, meal: "lunch", grams: 190 } },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response.body).to include('id="entry_form"')
    expect(response.body).not_to include('value="190"')
  end

  it "does not 500 when the entry param arrives as a bare scalar" do
    post entries_path, params: { entry: "boom" }

    expect(response).to have_http_status(:bad_request)
  end
end
