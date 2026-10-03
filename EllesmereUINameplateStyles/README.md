# EllesmereUI Nameplate Styles

An add-on for EUI's nameplates that applies ordered visual rules to enemy and full friendly nameplates. It registers its own **Nameplate Styles** section using `EllesmereUI.RegisterPlugin`; it does not modify the built-in Nameplates options page.

## Included rules

Three starter rules are enabled: current target, elite enemy, and enemy casting. Add up to 12 rules, edit their conditions and visual effects, and move them to change priority. New rules start enabled for the current target. The first enabled matching rule wins.

Conditions currently include player/NPC/pet/creature, friendly/enemy/neutral, normal/elite/rare/rare elite/boss/minor, current-target state, cast/channel/empowered/interruptibility, and spell school. Combat-log school tracking is enabled only when at least one enabled rule selects a specific school. A spell school is learned when its cast-start event is seen; unknown spells do not match school-specific rules.

Effects include health-bar color, whole-nameplate scale and opacity, an additional colored health-bar border, and a choice of EUI/flat/Blizzard health texture.

## Install

Copy the `EllesmereUINameplateStyles` folder into `Interface/AddOns`. It requires both `EllesmereUI` and `EllesmereUINameplates` to be enabled. Open the EUI options panel and select **Nameplate Styles > Rule Styling**.

## Extension points

The runtime is a separate addon with saved settings and a rule matcher. Future matchers/effects can be added in `EllesmereUINameplateStyles.lua` and surfaced in the plugin page. Other addon code can call:

```lua
EllesmereUINameplateStyles.Refresh()
EllesmereUINameplateStyles.GetRules()
```

`RegisterCondition(key, predicate)` adds a custom matcher for a corresponding key stored in a rule's `conditions` table. Predicates receive `(unitToken, traits, expectedValue, rule)` and should return `true` for a match. `RegisterSpellSchool(spellID, school)` can seed school metadata (`physical`, `holy`, `fire`, `nature`, `frost`, `shadow`, `arcane`, or `mixed`). After changing a rule programmatically, call `Refresh()`.

## Diagnostics and tests

Run `/npstyles` with a visible enemy target to report matching rules and reapply the current style. Diagnostics v2 uses the same settings accessor as the options page; `settings shared with options` should be `true`. Settings initialize after SavedVariables load and rebind if the global table is replaced. Existing saved rules are preserved.

Scale is a multiplier on EUI's base scale, including its target/cast animation. The plugin does not modify EUI's animation values.

From the repository root, run `lua EllesmereUINameplateStyles/tests/runtime.lua` (or `npx --yes --package fengari-node-cli fengari EllesmereUINameplateStyles/tests/runtime.lua`). The mocked runtime tests cover delayed SavedVariables loading, table replacement, option callbacks, new rules, scale updates, frame recycling, and disabling styles. They do not replace in-game testing on Forever and Retail.
