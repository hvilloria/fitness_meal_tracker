class EntriesController < ApplicationController
  include NormalizesDecimalParams

  rescue_from DayLog::MissingGoal, with: :redirect_to_goal

  def new
    @day_log = DayLog.for(current_user)
    # #present? is safe against the Array/Hash shapes a hostile query string
    # can send for a param that is normally a flag.
    @ad_hoc = params[:ad_hoc].present?
    @entry = Entry.new(meal: params[:meal].to_s.presence || "breakfast")
    load_food_options unless @ad_hoc
  end

  def create
    @day_log = DayLog.for(current_user)
    @entry = @day_log.entries.build(entry_attributes)
    # Which form was submitted is read from the entry itself, not a query
    # param: the ad-hoc form has no food_id field at all.
    @ad_hoc = entry_params[:food_id].blank?

    if @entry.save
      respond_to do |format|
        # The form stays open for the next item in the same meal, so it must
        # reset rather than keep showing the food/grams that were just
        # logged — otherwise a stale preview invites a double log.
        format.turbo_stream do
          @fresh_entry = Entry.new(meal: @entry.meal)
          load_food_options unless @ad_hoc
        end
        format.html { redirect_to new_entry_path(meal: @entry.meal), notice: "Registrado." }
      end
    else
      load_food_options unless @ad_hoc
      # #build pushed the invalid, unsaved @entry onto the day_log.entries
      # association target; reload so the "registrado hoy" list below the
      # form doesn't try to render it (it has no id yet, so entry_path
      # would fail to generate a route for it).
      @day_log.entries.reload
      # Turbo can request this response with only the turbo-stream media
      # type accepted; there is no entries/new.turbo_stream.erb (and should
      # not be one — a full form re-render belongs in HTML), so force the
      # format explicitly rather than letting content negotiation 500.
      render :new, formats: :html, status: :unprocessable_content
    end
  end

  def destroy
    entry = Entry.joins(:day_log).where(day_logs: { user_id: current_user.id }).find(params[:id])
    entry.destroy
    redirect_back fallback_location: root_path, notice: "Entrada eliminada."
  end

  private
    def load_food_options
      # Food.recent_for is an INNER JOIN on entries: a food that has never
      # been logged is invisible to it — not just a brand new user's first
      # food, but every food a user creates after that, since recents lists
      # only foods that already have at least one entry. Recents control
      # ORDER, not membership: the select must always offer the full active
      # catalog, with the habitually-eaten foods surfaced first.
      @recent_foods = Food.recent_for(current_user).to_a
      @other_foods = current_user.foods.active.where.not(id: @recent_foods.map(&:id)).order(:name)
      @last_grams = Food.last_grams_for(current_user)
    end

    def entry_attributes
      attributes = entry_params.except(:serving_id, :quantity)
      food = find_food(entry_params[:food_id])
      return attributes.merge(food: nil) if food.nil?

      # The catalog is the source of truth for a catalog entry: typed macros
      # and a typed name are dropped by construction, not merely overwritten
      # because grams happens to be required too.
      attributes.except(:protein_g, :carbs_g, :fat_g, :food_name_snapshot)
        .merge(food: food, **serving_resolution(food))
    end

    # A serving is a multiplier, never a source of macros: it resolves to
    # grams and the macros follow from the food's per-100 g values.
    def serving_resolution(food)
      serving = food.servings.find_by(id: entry_params[:serving_id])
      return {} if serving.nil?

      quantity = entry_params[:quantity].to_d
      quantity = 1 if quantity.zero?

      # The label is frozen history: it must never disagree with the grams
      # stored beside it, so it renders the exact quantity chosen (2, 0.5),
      # not an integer truncation of it.
      formatted_quantity = helpers.number_with_precision(quantity, precision: 2, strip_insignificant_zeros: true)
      { grams: serving.grams * quantity, serving_label: "#{formatted_quantity} × #{serving.label}" }
    end

    def find_food(food_id)
      return nil if food_id.blank?

      current_user.foods.find(food_id)
    end

    def entry_params
      @entry_params ||= begin
        permitted = require_params_hash(:entry).permit(
          :food_id, :meal, :grams, :serving_id, :quantity,
          :food_name_snapshot, :protein_g, :carbs_g, :fat_g
        )
        normalize_decimals(permitted, :grams, :protein_g, :carbs_g, :fat_g, :quantity)
        permitted
      end
    end

    def redirect_to_goal
      redirect_to edit_goal_path, notice: "Primero definí tu meta."
    end
end
