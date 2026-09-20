import { Controller } from "@hotwired/stimulus"

// Shows the macros an amount will produce, before the entry is saved. The
// per-100 values ride along on the selected food's option; the unit option
// carries how much of the food's base unit one of it is worth, so a quantity
// of 0.5 in a 30 g scoop previews the macros for 15 g.
export default class extends Controller {
  static targets = ["food", "quantity", "unit", "kcal", "protein", "carbs", "fat"]

  connect() {
    this.preview()
  }

  // Selecting a food rebuilds the units on offer — servings belong to a
  // food, so the previous food's list would be plain wrong — and then
  // prefills the amount used last time, so a habitual portion is not
  // retyped. An amount already typed is left alone.
  //
  // Order matters: rebuilding resets the selection to the base unit, and the
  // prefilled value is a weight in that base unit (it comes from a stored
  // Entry#grams), so it must land after the reset, never before it.
  foodChanged() {
    const option = this.foodTarget.selectedOptions[0]

    this.rebuildUnits(option)

    const lastGrams = option && option.dataset.lastGrams
    if (lastGrams && this.quantityTarget.value === "") {
      this.quantityTarget.value = parseFloat(lastGrams)
    }

    this.preview()
  }

  // The base unit, that unit ×1000, and one option per serving the food
  // defines — the same list EntriesHelper#entry_unit_options renders on the
  // server, rebuilt from the data the option carries.
  rebuildUnits(option) {
    if (!this.hasUnitTarget) return

    const unit = (option && option.dataset.unit) || "g"
    const multiple = (option && option.dataset.multipleUnit) || "kg"

    this.unitTarget.replaceChildren(
      this.unitOption(unit, "base", 1),
      this.unitOption(multiple, "x1000", 1000),
      ...this.servingsFor(option).map((serving) =>
        this.unitOption(serving.label, `serving:${serving.id}`, serving.grams)
      )
    )
  }

  unitOption(label, value, grams) {
    const option = document.createElement("option")
    option.textContent = label
    option.value = value
    option.dataset.grams = grams
    return option
  }

  servingsFor(option) {
    if (!option || !option.dataset.servings) return []

    try {
      const servings = JSON.parse(option.dataset.servings)
      return Array.isArray(servings) ? servings : []
    } catch {
      return []
    }
  }

  // How much of the food's base unit one of the selected unit is worth. The
  // base unit is 1, so an unreadable or missing value falls back to it
  // rather than zeroing the preview.
  unitGrams() {
    if (!this.hasUnitTarget) return 1

    const option = this.unitTarget.selectedOptions[0]
    const grams = option && parseFloat(option.dataset.grams)
    return Number.isFinite(grams) ? grams : 1
  }

  preview() {
    const option = this.foodTarget.selectedOptions[0]
    const quantity = parseFloat(this.quantityTarget.value)

    if (!option || !option.dataset.kcal || !Number.isFinite(quantity)) {
      this.render(0, 0, 0, 0)
      return
    }

    const factor = (quantity * this.unitGrams()) / 100
    this.render(
      option.dataset.kcal * factor,
      option.dataset.protein * factor,
      option.dataset.carbs * factor,
      option.dataset.fat * factor
    )
  }

  render(kcal, protein, carbs, fat) {
    this.kcalTarget.textContent = Math.round(kcal)
    this.proteinTarget.textContent = protein.toFixed(1)
    this.carbsTarget.textContent = carbs.toFixed(1)
    this.fatTarget.textContent = fat.toFixed(1)
  }
}
