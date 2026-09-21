# Macro tracker — design

A personal macro and calorie tracker in the spirit of MyFitnessPal, scoped to
the 90% case: log what you habitually eat, quickly, and see where the day
stands against a goal.

Derived from `spec_app_macros.md`, which remains the authority on the data
model's intent. This document records the decisions that spec left open and
the concrete shape of the first iteration.

## Decisions

**Multi-user from day one.** `user_id` on `foods`, `goals` and `day_logs`, with
scoping on every query. The source spec argues for single-user simplicity, but
adding accounts later means touching every table and every query. The cost is
paid now instead.

**Google-only authentication, no Devise.** `omniauth-google-oauth2` plus
`omniauth-rails_csrf_protection`. With no passwords, there is nothing for Devise
to manage — no reset flow, no confirmation, no lockable. A `User` model, a
`SessionsController` and a signed session cookie cover it.

**Access is restricted by an email allowlist.** A Google login on a public URL
is open to anyone with a Google account. `ALLOWED_EMAILS` (comma-separated) is
checked in the OAuth callback; anything else is rejected before a `User` is
created.

**Application-wide time zone.** `config.time_zone = "America/Argentina/Buenos_Aires"`.
Not a per-user column — every user of this deployment is in the same place.

**The day ends at a configurable hour, defaulting to 04:00.** Food logged at
01:00 belongs to the previous day. `users.day_cutoff_hour` holds it. No query
resolves a date through `Date.current`; they all go through `DayLog.for`.

**Ad-hoc entries do not enter the catalog.** Typing "pizza muzza, 100 protein,
100 carbs, 100 fat" records what was eaten in total, not per 100 g. Both
`entries.food_id` and `entries.grams` are nullable to allow it.

**Four meals**, not the source spec's five: `breakfast`, `lunch`, `snack`,
`dinner`. No `extra`.

**UUID primary keys**, per the source spec.

## Schema

All decimal columns are `decimal(8, 2)` unless noted. Macros are grams, sodium
is milligrams.

### `users`

| Column | Type | Notes |
|---|---|---|
| `id` | uuid | |
| `email` | string | unique |
| `name` | string | |
| `avatar_url` | string, nullable | from the Google profile |
| `provider` | string | `google_oauth2` |
| `uid` | string | unique with `provider` |
| `day_cutoff_hour` | integer | default 4 |

### `foods`

Values are stored normalized per 100 g. What the user types is per portion
(see below); the form converts. Normalization is what lets an amount in any
unit resolve to macros by simple proportion.

| Column | Type | Notes |
|---|---|---|
| `id` | uuid | |
| `user_id` | uuid | |
| `name` | string | |
| `brand` | string, nullable | null for generics |
| `state` | enum | `raw` \| `cooked` \| `dry` \| `as_sold`, required |
| `kcal_per_100` | decimal | from the label; not derived from macros |
| `protein_per_100` | decimal | |
| `carbs_per_100` | decimal | |
| `fat_per_100` | decimal | |
| `fiber_per_100` | decimal, nullable | stored, not surfaced in this iteration |
| `sodium_per_100` | decimal, nullable | stored, not surfaced in this iteration |
| `sugar_per_100` | decimal, nullable | stored, not surfaced in this iteration |
| `archived_at` | timestamp, nullable | soft delete |

`state` is required and always displayed next to the name. Raw and cooked
chicken differ by roughly 30%, and a food consumed in two states is two
catalog records.

`kcal_per_100` is taken from the label rather than computed, because labels
account for fiber, sugar alcohols and rounding that the 4/4/9 calculation does
not. When there is no label, it is computed once at creation and stored.

Index on `[user_id, name]`.

### Portion size, not named servings

An earlier draft gave each food a list of named `Serving` rows ("1 feta" = 30 g)
so an entry could be logged as "2 fetas". It was built, and then removed after
the human used it: the name carried no weight, and a list of named rows on the
food form actively misled them.

What replaced it is one number on `foods`:

| Column | Type | Notes |
|---|---|---|
| `portion_amount` | decimal | how much of the food's own `unit` one portion is; defaults to 100 |

**The figures a user types on the food form describe one portion, not 100 g.**
A food whose label reads per 100 g simply leaves the portion at 100 and nothing
changes. A protein tub labelled per 30 g scoop gets a portion of 30 and its
label values typed verbatim.

Storage stays normalized per 100 — the form converts on the way in and back out,
so the edit form returns what was typed. That round trip is exact for every
portion that divides 100 cleanly, and drifts at most 0.02 for awkward portions
above 125.

At logging time the amount carries a unit: **unidades** (multiply by
`portion_amount`), the base unit (`g`/`ml`), or its ×1000 multiple (`kg`/`l`).
`entries.serving_label` freezes the expression the user chose — "2 unidades",
"0.5 kg" — and must never disagree with the amount stored beside it.

### `goals`

| Column | Type | Notes |
|---|---|---|
| `id` | uuid | |
| `user_id` | uuid | |
| `label` | string | "Día normal" |
| `kcal` | integer | always derived from the macros |
| `protein_g` | integer | |
| `carbs_g` | integer | |
| `fat_g` | integer | |
| `is_default` | boolean | |
| `effective_from` | date | |

Goals are versioned rather than updated destructively, so past days stay
comparable against the goal that was actually in force. This iteration only
creates and edits the active goal; the history exists because `day_logs`
captures `goal_id`.

### `day_logs`

| Column | Type | Notes |
|---|---|---|
| `id` | uuid | |
| `user_id` | uuid | |
| `date` | date | unique with `user_id` |
| `goal_id` | uuid | copied on creation, never resolved at read time |

Weight, body fat and notes are deliberately out of this iteration.

`goal_id` is required, so a user must have a goal before logging anything. On
first sign-in, with no default goal, the app redirects to the goal calculator
rather than creating a day.

### `entries`

| Column | Type | Notes |
|---|---|---|
| `id` | uuid | |
| `day_log_id` | uuid | |
| `food_id` | uuid, nullable | null for ad-hoc entries; may also be orphaned |
| `meal` | enum | `breakfast` \| `lunch` \| `snack` \| `dinner` |
| `grams` | decimal, nullable | null when an ad-hoc entry has no known weight |
| `serving_label` | string, nullable | "2 unidades", "0.5 kg" — what the user chose |
| `food_name_snapshot` | string | |
| `kcal` | decimal | calculated and frozen |
| `protein_g` | decimal | calculated and frozen |
| `carbs_g` | decimal | calculated and frozen |
| `fat_g` | decimal | calculated and frozen |
| `position` | integer | order within the meal |
| `logged_at` | timestamp | |

**Macros are computed when the entry is written and never recalculated on
read.** An entry is a historical fact, not a view onto the catalog. Correcting
a food's values three months from now — because the brand reformulated, or the
original numbers were wrong — must not silently rewrite a month of history.
The cost is duplicated data and an explicit `recalculate!` when an entry is
edited; the benefit is a history that can be trusted.

Validation splits on the entry's origin: when `food_id` is present, `grams` is
required and the macros are computed; when it is absent, the macros are
required and `grams` is optional.

Index on `[day_log_id, meal, position]`.

## Calculation

### Entry macros

From a catalog food:

```
factor    = grams / 100
kcal      = food.kcal_per_100    * factor
protein_g = food.protein_per_100 * factor
carbs_g   = food.carbs_per_100   * factor
fat_g     = food.fat_per_100     * factor
```

For an ad-hoc entry the macros come from the form as typed, and kcal is derived
as `4 * protein_g + 4 * carbs_g + 9 * fat_g`.

Values are stored to two decimals and rounded only for display. Rounding on
write accumulates: twenty entries rounded to integers can drift a day by
15-20 kcal.

### Day totals and progress

```
totals         = SUM(entries of the day_log)
remaining_kcal = goal.kcal - totals.kcal
progress_pct   = totals.kcal / goal.kcal * 100
```

A direct `SUM` is sufficient at 10-15 entries per day; the totals are not
materialized.

Remaining values may be negative and are displayed as negative. A day over the
goal is information, not an error to be hidden at zero.

### Goal distribution

`Goal#kcal` is always derived from the macros and stored:

```
kcal = 4 * protein_g + 4 * carbs_g + 9 * fat_g
```

All three macros are freely editable and the calorie total follows. Raising
protein raises the total; bringing it back down is the user's own adjustment to
carbs or fat, made against a figure that updates as they type.

An earlier draft pinned the calorie total and redistributed the other macros
automatically. It was dropped: it buys a couple of keystrokes on a screen
touched about once a month, and costs a mode toggle, a rule for which macro
absorbs the difference, and clamping logic for when that pushes a macro out of
range.

The "target kcal" field is the inverse operation, used once: it distributes a
calorie figure across the three macros. A new goal has no split to preserve, so
it seeds at **25% protein / 50% carbs / 25% fat** — comfortably inside the
AMDR ranges (protein 10-35%, carbohydrate 45-65%, fat 20-35%) established by
the Institute of Medicine, and landing protein near 1.6 g/kg for a typical
adult weight, which is where Morton et al. (2018) found gains in fat-free mass
plateau.

Body weight is deliberately not stored. It would serve only to anchor that
first protein suggestion, which the user overwrites with their own figure
immediately afterwards.

This does not contradict the rule that kcal must not be derived for `Food`.
That rule protects label values; a goal has no label.

## Where the logic lives

Fat models. Plain objects only where the calculation belongs to no single
record.

- **`Entry`** computes and freezes its macros in `before_validation`, and
  exposes `recalculate!` for explicit edits.
- **`MacroSplit`** converts between grams, calories and percentages, and seeds
  a new goal from a calorie figure.
- **`DayLog.for(user, time)`** finds or creates the day, applying
  `day_cutoff_hour`. Every date-scoped query goes through it.
- **`Food.recent_for(user)`** returns the last 20 logged foods, ordered by
  recent frequency, for the entry form.

## Views

Mobile-first: a single column, generous tap targets, no hover as the sole
affordance. Server-rendered ERB with Turbo; Stimulus only where live feedback
is needed. Sass via `dartsass-rails`, compiled by a dedicated `css` service in
`compose.yaml` running `bin/rails dartsass:watch`.

**`days#show` — the day.** Four SVG progress rings (kcal, protein, carbs, fat)
showing current against goal, the remaining figure in large type, and below it
the entries grouped by the four meals. Previous/next day navigation.

**`goals#edit` — the goal calculator.** All three macros are editable. Editing
any of them updates the calorie total and the three percentages instantly via a
Stimulus controller, so the user can steer toward a figure they have in mind.
The server recomputes through `MacroSplit` on save, so the stored total never
depends on the browser.

**`foods#index` / `#new` / `#edit` — the catalog.** Per-100 g values as they
appear on the label for the declared portion. `state` is optional and limited
to raw or cooked — "dry" and "as sold" were dropped as indistinguishable for
anything that comes packaged.

**`entries#new` — logging.** Pick the meal, then a recent food or a search,
then an amount and its unit, with macros updating live as the amount is typed.
Saving keeps the form open and appends the entry below over Turbo Stream, so
that a multi-item meal — 190 g pasta, 200 g beef, oil, cheese — is logged
without renavigating. A separate link opens the ad-hoc entry form.

## Authentication flow

1. `GET /auth/google_oauth2` → Google.
2. Callback: reject unless the email is in `ALLOWED_EMAILS`.
3. Find or create the `User` by `[provider, uid]`; refresh name and avatar.
4. Store `user_id` in a signed session cookie.
5. `ApplicationController` requires a session for everything except the sign-in
   page and the callback.

`GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` come from the environment. The
development redirect URI is `http://localhost:3000/auth/google_oauth2/callback`.
Creating the Google Cloud credentials is a manual step for the operator.

## Out of scope

In the source spec's order of value: repeat day, repeat meal, recipes, multiple
goals per day type, weight and body composition logging, weekly trend charts,
micronutrient display, barcode scanning, external food database import.

Favorites are also deferred; recents cover the same need at a fraction of the
work, and whether favorites add anything on top is better judged after the app
has been used.

## Known risks

**Google is a single point of failure for access.** No Google, no login. A
personal app can live with this, but it is a real dependency.

**`dartsass-rails` must build inside the production image.** It hooks into
`assets:precompile` and ships a platform-specific binary; this needs verifying
against the slim base image during implementation, not at deploy time.

**Deployment remains unresolved.** Supabase provides one database while
`config/database.yml` declares separate `cache`, `queue` and `cable` databases
for the solid_* gems. That has to be settled before the first deploy.
