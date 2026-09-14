import { Controller } from "@hotwired/stimulus"

// Mirrors MacroSplit so the calorie total and the three percentages respond as
// the user types. The server recomputes on save, so this is display only.
const PROTEIN_KCAL_PER_G = 4
const CARBS_KCAL_PER_G = 4
const FAT_KCAL_PER_G = 9

export default class extends Controller {
  static targets = ["protein", "carbs", "fat", "kcal", "proteinPct", "carbsPct", "fatPct"]

  connect() {
    this.recalculate()
  }

  recalculate() {
    const protein = this.gramsFrom(this.proteinTarget)
    const carbs = this.gramsFrom(this.carbsTarget)
    const fat = this.gramsFrom(this.fatTarget)

    const proteinKcal = protein * PROTEIN_KCAL_PER_G
    const carbsKcal = carbs * CARBS_KCAL_PER_G
    const fatKcal = fat * FAT_KCAL_PER_G
    const total = proteinKcal + carbsKcal + fatKcal

    this.kcalTarget.textContent = Math.round(total)
    this.proteinPctTarget.textContent = this.percentage(proteinKcal, total)
    this.carbsPctTarget.textContent = this.percentage(carbsKcal, total)
    this.fatPctTarget.textContent = this.percentage(fatKcal, total)
  }

  gramsFrom(element) {
    const value = parseFloat(element.value)
    return Number.isFinite(value) ? value : 0
  }

  percentage(macroKcal, totalKcal) {
    if (totalKcal === 0) return "0"
    return (macroKcal / totalKcal * 100).toFixed(0)
  }
}
