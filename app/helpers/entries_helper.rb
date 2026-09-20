module EntriesHelper
  # One [text, value, html_attributes] triple per food, in the shape
  # options_for_select (and so form.select, including its grouped/optgroup
  # form) expects. The per-100 g macros and the last weight used ride along
  # as data attributes for the Stimulus preview and grams prefill; a food
  # with no logged weight simply has no data-last-grams attribute at all
  # (Rails omits nil data attributes), which the controller already treats
  # as "nothing to prefill" rather than writing "undefined" into the field.
  def food_select_option(food, last_grams)
    [
      food.display_name, food.id,
      {
        data: {
          kcal: food.kcal_per_100, protein: food.protein_per_100,
          carbs: food.carbs_per_100, fat: food.fat_per_100,
          unit: food.unit_abbreviation,
          multiple_unit: food.multiple_unit_abbreviation,
          # The units on offer depend on the food, so the servings travel
          # with it: entry_preview_controller.js rebuilds the unit select
          # from this when the selection changes.
          servings: food.servings.map { |serving|
            { id: serving.id, label: serving.label, grams: serving.grams.to_f }
          }.to_json,
          last_grams: last_grams[food.id]
        }
      }
    ]
  end

  # Grouped so recency controls ORDER, not membership: every active food
  # belongs in one of the two groups, with habitually-eaten foods surfaced
  # first — see EntriesController#load_food_options.
  def food_select_groups(recent_foods, other_foods, last_grams)
    groups = []
    groups << [ "Recientes", recent_foods.map { |food| food_select_option(food, last_grams) } ] if recent_foods.any?
    groups << [ "Todo el catálogo", other_foods.map { |food| food_select_option(food, last_grams) } ] if other_foods.any?
    groups
  end

  # The units an amount of this food can be typed in: its base unit, the
  # same unit ×1000, and one per serving it defines. Each option carries how
  # much of the base unit it is worth, which is all the preview and the
  # server both need — see EntriesController#amount_resolution.
  #
  # With no food selected there is nothing to read a unit from, so this
  # offers the neutral grams pair; the browser replaces the whole list as
  # soon as a food is picked.
  def entry_unit_options(food)
    base = food&.unit_abbreviation || "g"
    multiple = food&.multiple_unit_abbreviation || "kg"

    options = [
      [ base, Entry::BASE_UNIT, { data: { grams: 1 } } ],
      [ multiple, Entry::MULTIPLE_UNIT, { data: { grams: Food::MULTIPLE_FACTOR } } ]
    ]
    return options if food.nil?

    options + food.servings.map do |serving|
      [ serving.label, "#{Entry::SERVING_UNIT_PREFIX}#{serving.id}", { data: { grams: serving.grams.to_f } } ]
    end
  end
end
