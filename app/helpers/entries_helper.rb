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
end
