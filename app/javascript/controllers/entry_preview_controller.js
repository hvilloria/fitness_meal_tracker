import { Controller } from "@hotwired/stimulus"

// Shows the macros a weight will produce, before the entry is saved. The
// per-100 g values ride along on the selected option.
export default class extends Controller {
  static targets = ["food", "grams", "kcal", "protein", "carbs", "fat", "unitLabel"]

  connect() {
    this.updateUnitLabel()
    this.preview()
  }

  // Selecting a food prefills the weight used last time, so a habitual
  // portion is not retyped. A weight already typed is left alone.
  foodChanged() {
    const option = this.foodTarget.selectedOptions[0]
    const lastGrams = option && option.dataset.lastGrams

    if (lastGrams && this.gramsTarget.value === "") {
      this.gramsTarget.value = parseFloat(lastGrams)
    }

    this.updateUnitLabel()
    this.preview()
  }

  // The weight field's unit label follows the selected food (g or ml, see
  // Food#unit) — it falls back to "g" for the blank "Elegí un alimento"
  // option, which carries no data-unit, and on connect (e.g. a form
  // re-rendered with a food already selected after a validation error).
  updateUnitLabel() {
    if (!this.hasUnitLabelTarget) return

    const option = this.foodTarget.selectedOptions[0]
    this.unitLabelTarget.textContent = (option && option.dataset.unit) || "g"
  }

  preview() {
    const option = this.foodTarget.selectedOptions[0]
    const grams = parseFloat(this.gramsTarget.value)

    if (!option || !option.dataset.kcal || !Number.isFinite(grams)) {
      this.render(0, 0, 0, 0)
      return
    }

    const factor = grams / 100
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
