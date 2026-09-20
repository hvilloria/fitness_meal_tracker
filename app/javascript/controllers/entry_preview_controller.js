import { Controller } from "@hotwired/stimulus"

// Shows the macros an amount will produce, before the entry is saved. The
// per-100 values ride along on the selected food's option; the unit option
// carries how much of the food's base unit one of it is worth, so a quantity
// of 0.5 of a 30 g portion previews the macros for 15 g.
export default class extends Controller {
  static targets = ["food", "quantity", "unit", "kcal", "protein", "carbs", "fat"]

  connect() {
    this.preview()
  }

  // Selecting a food rebuilds the units on offer — a portion belongs to a
  // food, so the previous food's list would be plain wrong — and then
  // prefills the amount used last time, so a habitual portion is not
  // retyped. An amount already typed is left alone.
  //
  // Order matters: rebuilding also resets which unit is selected, and the
  // prefilled value is a weight in the food's base unit (it comes from a
  // stored Entry#grams), so it is converted into whatever unit the rebuild
  // settled on — and must therefore land after it, never before.
  foodChanged() {
    const option = this.foodTarget.selectedOptions[0]

    this.rebuildUnits(option)

    const lastGrams = option && parseFloat(option.dataset.lastGrams)
    if (Number.isFinite(lastGrams) && this.quantityTarget.value === "") {
      this.quantityTarget.value = this.roundedQuantity(lastGrams / this.unitGrams())
    }

    this.preview()
  }

  // One portion of the food, its base unit, and that unit ×1000 — the same
  // list EntriesHelper#entry_unit_options renders on the server, rebuilt
  // from the data the option carries. The selection it lands on is the
  // server's too (data-default-unit), so the rule lives in one place.
  rebuildUnits(option) {
    if (!this.hasUnitTarget) return

    const unit = (option && option.dataset.unit) || "g"
    const multiple = (option && option.dataset.multipleUnit) || "kg"
    const portion = option && parseFloat(option.dataset.portion)

    const options = []
    if (Number.isFinite(portion) && portion > 0) {
      options.push(this.unitOption("unidad", "portion", portion))
    }
    options.push(this.unitOption(unit, "base", 1), this.unitOption(multiple, "x1000", 1000))
    this.unitTarget.replaceChildren(...options)

    // Assigning a value no option carries leaves the select on nothing at
    // all (selectedIndex -1), which would post an empty unit, so fall back
    // to the base unit rather than trusting the attribute blindly.
    this.unitTarget.value = (option && option.dataset.defaultUnit) || "base"
    if (this.unitTarget.selectedIndex < 0) this.unitTarget.value = "base"
  }

  // Two decimals is enough for any amount typed by hand, and parseFloat
  // drops the trailing zeros toFixed leaves behind ("2.00" -> 2).
  roundedQuantity(quantity) {
    return parseFloat(quantity.toFixed(2))
  }

  unitOption(label, value, grams) {
    const option = document.createElement("option")
    option.textContent = label
    option.value = value
    option.dataset.grams = grams
    return option
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
