# Converts between macro grams, calories and percentages. The arithmetic
# belongs to no single record: a Goal uses it to derive its calorie target, an
# ad-hoc Entry uses it to derive calories from typed macros, and the goal form
# uses it to seed a brand new split.
class MacroSplit
  PROTEIN_KCAL_PER_G = 4
  CARBS_KCAL_PER_G = 4
  FAT_KCAL_PER_G = 9

  # Inside the Institute of Medicine's Acceptable Macronutrient Distribution
  # Ranges (protein 10-35%, carbohydrate 45-65%, fat 20-35%), and landing
  # protein near 1.6 g/kg for a typical adult weight, where Morton et al.
  # (2018) found gains in fat-free mass plateau.
  DEFAULT_PERCENTAGES = { protein: 0.25, carbs: 0.50, fat: 0.25 }.freeze

  class << self
    def kcal_from(protein_g:, carbs_g:, fat_g:)
      (protein_g.to_f * PROTEIN_KCAL_PER_G +
        carbs_g.to_f * CARBS_KCAL_PER_G +
        fat_g.to_f * FAT_KCAL_PER_G).round
    end

    def percentages(protein_g:, carbs_g:, fat_g:)
      total = kcal_from(protein_g: protein_g, carbs_g: carbs_g, fat_g: fat_g)
      return { protein: 0.0, carbs: 0.0, fat: 0.0 } if total.zero?

      {
        protein: share(protein_g.to_f * PROTEIN_KCAL_PER_G, total),
        carbs: share(carbs_g.to_f * CARBS_KCAL_PER_G, total),
        fat: share(fat_g.to_f * FAT_KCAL_PER_G, total)
      }
    end

    def from_kcal(kcal)
      return { protein_g: 0, carbs_g: 0, fat_g: 0 } unless kcal.to_i.positive?

      {
        protein_g: (kcal * DEFAULT_PERCENTAGES[:protein] / PROTEIN_KCAL_PER_G).round,
        carbs_g: (kcal * DEFAULT_PERCENTAGES[:carbs] / CARBS_KCAL_PER_G).round,
        fat_g: (kcal * DEFAULT_PERCENTAGES[:fat] / FAT_KCAL_PER_G).round
      }
    end

    private
      def share(macro_kcal, total_kcal)
        (macro_kcal / total_kcal * 100).round(1)
      end
  end
end
