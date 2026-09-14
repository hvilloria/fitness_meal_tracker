import { Controller } from "@hotwired/stimulus"

// Mirrors MacroSplit so the calorie total and the three percentages respond as
// the user types. The server recomputes on save, so this is display only.
const PROTEIN_KCAL_PER_G = 4
const CARBS_KCAL_PER_G = 4
const FAT_KCAL_PER_G = 9

export default class extends Controller {
  static targets = ["protein", "carbs", "fat", "kcal", "proteinPct", "carbsPct", "fatPct"]
  static values = { defaultPercentages: Object }

  connect() {
    this.recalculate()
  }

  // Macro -> total direction: any macro edit re-derives the calorie total
  // and the three percentages. Must never itself write to the macro fields,
  // or it would loop with distribute().
  recalculate() {
    const protein = this.gramsFrom(this.proteinTarget)
    const carbs = this.gramsFrom(this.carbsTarget)
    const fat = this.gramsFrom(this.fatTarget)

    const proteinKcal = protein * PROTEIN_KCAL_PER_G
    const carbsKcal = carbs * CARBS_KCAL_PER_G
    const fatKcal = fat * FAT_KCAL_PER_G
    const total = proteinKcal + carbsKcal + fatKcal

    this.setKcalDisplay(total)

    // The percentage breakdown is optional: the ad-hoc entry form only
    // shows the calorie total, not a per-macro percentage split.
    if (this.hasProteinPctTarget) this.proteinPctTarget.textContent = this.percentage(proteinKcal, total)
    if (this.hasCarbsPctTarget) this.carbsPctTarget.textContent = this.percentage(carbsKcal, total)
    if (this.hasFatPctTarget) this.fatPctTarget.textContent = this.percentage(fatKcal, total)
  }

  // Total -> macro direction: bound ONLY to direct user input on the
  // calorie field itself (see the view), never fired programmatically, so
  // it cannot re-trigger itself through recalculate()'s writes. Preserves
  // the macros' current percentage split when they are non-zero; falls
  // back to MacroSplit::DEFAULT_PERCENTAGES (read from a data attribute,
  // not retyped here) for a brand-new, all-zero goal.
  distribute() {
    const target = this.gramsFrom(this.kcalTarget)

    const protein = this.gramsFrom(this.proteinTarget)
    const carbs = this.gramsFrom(this.carbsTarget)
    const fat = this.gramsFrom(this.fatTarget)
    const currentTotal = protein * PROTEIN_KCAL_PER_G + carbs * CARBS_KCAL_PER_G + fat * FAT_KCAL_PER_G

    const percentages = currentTotal > 0
      ? {
          protein: (protein * PROTEIN_KCAL_PER_G) / currentTotal,
          carbs: (carbs * CARBS_KCAL_PER_G) / currentTotal,
          fat: (fat * FAT_KCAL_PER_G) / currentTotal
        }
      : this.defaultPercentagesValue

    this.proteinTarget.value = Math.round((target * percentages.protein) / PROTEIN_KCAL_PER_G)
    this.carbsTarget.value = Math.round((target * percentages.carbs) / CARBS_KCAL_PER_G)
    this.fatTarget.value = Math.round((target * percentages.fat) / FAT_KCAL_PER_G)

    // Re-derive the real total from the rounded grams rather than leaving
    // the typed figure on screen: distribution can drift a few kcal from
    // rounding, and the displayed total must reflect what will be saved.
    this.recalculate()
  }

  setKcalDisplay(total) {
    const rounded = Math.round(total)
    if (this.kcalTarget.tagName === "INPUT") {
      this.kcalTarget.value = rounded
    } else {
      this.kcalTarget.textContent = rounded
    }
  }

  gramsFrom(element) {
    const value = parseFloat(element.value)
    // The server rejects negative macros (greater_than_or_equal_to: 0), so a
    // negative reading here must not drive the live total — showing the user
    // a number the save will refuse is worse than clamping it in the UI.
    return Number.isFinite(value) ? Math.max(0, value) : 0
  }

  percentage(macroKcal, totalKcal) {
    if (totalKcal === 0) return "0"
    return (macroKcal / totalKcal * 100).toFixed(0)
  }
}
