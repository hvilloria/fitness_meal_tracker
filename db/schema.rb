# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_14_193323) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "day_logs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.uuid "goal_id", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["goal_id"], name: "index_day_logs_on_goal_id"
    t.index ["user_id", "date"], name: "index_day_logs_on_user_id_and_date", unique: true
    t.index ["user_id"], name: "index_day_logs_on_user_id"
  end

  create_table "entries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.decimal "carbs_g", precision: 8, scale: 2, null: false
    t.datetime "created_at", null: false
    t.uuid "day_log_id", null: false
    t.decimal "fat_g", precision: 8, scale: 2, null: false
    t.uuid "food_id"
    t.string "food_name_snapshot", null: false
    t.decimal "grams", precision: 8, scale: 2
    t.decimal "kcal", precision: 8, scale: 2, null: false
    t.datetime "logged_at", null: false
    t.string "meal", null: false
    t.integer "position", default: 0, null: false
    t.decimal "protein_g", precision: 8, scale: 2, null: false
    t.string "serving_label"
    t.datetime "updated_at", null: false
    t.index ["day_log_id", "meal", "position"], name: "index_entries_on_day_log_id_and_meal_and_position"
    t.index ["day_log_id"], name: "index_entries_on_day_log_id"
    t.index ["food_id"], name: "index_entries_on_food_id"
  end

  create_table "foods", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "archived_at"
    t.string "brand"
    t.decimal "carbs_per_100", precision: 8, scale: 2, null: false
    t.datetime "created_at", null: false
    t.decimal "fat_per_100", precision: 8, scale: 2, null: false
    t.decimal "fiber_per_100", precision: 8, scale: 2
    t.decimal "kcal_per_100", precision: 8, scale: 2, null: false
    t.string "name", null: false
    t.decimal "protein_per_100", precision: 8, scale: 2, null: false
    t.decimal "sodium_per_100", precision: 8, scale: 2
    t.string "state", null: false
    t.decimal "sugar_per_100", precision: 8, scale: 2
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["user_id", "name"], name: "index_foods_on_user_id_and_name"
    t.index ["user_id"], name: "index_foods_on_user_id"
  end

  create_table "goals", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "carbs_g", default: 0, null: false
    t.datetime "created_at", null: false
    t.date "effective_from", null: false
    t.integer "fat_g", default: 0, null: false
    t.boolean "is_default", default: false, null: false
    t.integer "kcal", default: 0, null: false
    t.integer "protein_g", default: 0, null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["user_id", "effective_from"], name: "index_goals_on_user_id_and_effective_from"
    t.index ["user_id"], name: "index_goals_on_one_default_per_user", unique: true, where: "is_default"
    t.index ["user_id"], name: "index_goals_on_user_id"
  end

  create_table "servings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "food_id", null: false
    t.decimal "grams", precision: 8, scale: 2, null: false
    t.boolean "is_default", default: false, null: false
    t.string "label", null: false
    t.datetime "updated_at", null: false
    t.index ["food_id"], name: "index_servings_on_food_id"
    t.index ["food_id"], name: "index_servings_on_one_default_per_food", unique: true, where: "is_default"
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "avatar_url"
    t.datetime "created_at", null: false
    t.integer "day_cutoff_hour", default: 4, null: false
    t.string "email", null: false
    t.string "name", null: false
    t.string "provider", null: false
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true
  end

  add_foreign_key "day_logs", "goals"
  add_foreign_key "day_logs", "users"
  add_foreign_key "entries", "day_logs"
  add_foreign_key "entries", "foods", on_delete: :nullify
  add_foreign_key "foods", "users"
  add_foreign_key "goals", "users"
  add_foreign_key "servings", "foods"
end
