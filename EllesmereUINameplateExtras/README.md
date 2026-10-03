# EllesmereUI Nameplate Extras


This extensible add-on currently provides one feature: **Nameplate Style**. It adds a **Nameplate Extras > Nameplate Style** section using `EllesmereUI.RegisterPlugin`; it does not modify the built-in Nameplates options page.

## Included rules

Three starter rules are enabled: current target, elite enemy, and enemy casting. Add up to 12 rules, copy the selected rule, edit their conditions and visual effects, and move them to change priority. A copy is inserted after its source and selected for editing. New rules start enabled for the current target. The first enabled matching rule wins.

Conditions currently include player/NPC/pet/creature, friendly/enemy/neutral, normal/elite/rare/rare elite/boss/minor, current-target state, an optional active-quest-objective toggle, cast/channel/empowered/interruptibility, and spell school. Quest matching uses EUI's cached tooltip-based detector for incomplete objectives in the player's own quest log, following EUI's Show In Instances setting. Combat-log school tracking is enabled only when at least one enabled rule selects a specific school. A spell school is learned when its cast-start event is seen; unknown spells do not match school-specific rules.

Effects include health-bar color, whole-nameplate scale and opacity, an additional colored health-bar border, and a choice of EUI/flat/Blizzard health texture.

## Health-bar overrides

The Health Bar section uses the same layout as Cast Bar: a master **Override health bar** switch, **Custom health color** beside its color picker, a texture selector, and **Additional health border** beside its color picker with thickness below. Controls are dimmed when their override is off.

The border toggle preserves its saved color and thickness. Existing rules keep their previous appearance; a saved border size of zero remains off until enabled. Turning the health master off restores EUI color/texture and hides only the plugin's additional border. Whole-nameplate size/opacity and cast-bar overrides remain independent.

Tap-denied enemies keep EUI's tapped health-bar color; this plugin suspends only its health-color override while another player has the tap.

## Cast-bar overrides

Appearance is grouped into **Nameplate**, **Health Bar**, and **Cast Bar**. In the Cast Bar section, enable **Override cast bar** for the selected rule. Existing rules leave this off. Inactive controls remain visible but dimmed, with tooltips explaining what to enable.

- **Custom cast color** tints the fill and uninterruptible overlay; the interrupted flash and other EUI cast indicators are preserved.
- **Cast-bar texture** offers EUI, flat, and Blizzard status-bar textures. Stock Blizzard-style cast artwork retains its atlas; this texture override applies to EUI and Classic styles.
- **Custom cast opacity** fades the cast subtree, including when casts are lifted in front of nameplates.
- **Additional cast border** adds its own outline with color and thickness controls without replacing the EUI border.

Turning an override off, disabling the plugin, or leaving a matching rule restores the engine-authored cast settings. Rules still use first-match priority; a higher rule can take precedence over a cast-specific rule. Friendly plates currently have no EUI cast bar, so these settings do not add one.

## Install

Copy the `EllesmereUINameplateExtras` folder into `Interface/AddOns`. It requires both `EllesmereUI` and `EllesmereUINameplates` to be enabled. Open the EUI options panel and select **Nameplate Extras > Nameplate Style**. As the addon is in early development, it starts with fresh `EllesmereUINameplateExtrasDB` settings; the former Styles settings/API are not migrated or aliased.

## Extension points

The public runtime API is `EllesmereUINameplateExtras`. Future features can be registered as additional modules in `EllesmereUINameplateExtras_Options.lua`; runtime matchers/effects belong in `EllesmereUINameplateExtras.lua` and its feature modules. Other addon code can call:

```lua
EllesmereUINameplateExtras.Refresh()
EllesmereUINameplateExtras.GetRules()
```

`RegisterCondition(key, predicate)` adds a custom matcher for a corresponding key stored in a rule's `conditions` table. Predicates receive `(unitToken, traits, expectedValue, rule)` and should return `true` for a match. `RegisterSpellSchool(spellID, school)` can seed school metadata (`physical`, `holy`, `fire`, `nature`, `frost`, `shadow`, `arcane`, or `mixed`). After changing a rule programmatically, call `Refresh()`.

## Diagnostics and tests

Run `/npextras` with a visible enemy target to report matching rules and reapply the current style. Diagnostics v3 uses the same settings accessor as the options page; `settings shared with options` should be `true`. Settings initialize after SavedVariables load and rebind if the global table is replaced.

Scale is a multiplier on EUI's base scale, including its target/cast animation. The plugin does not modify EUI's animation values.

From the repository root, run `lua EllesmereUINameplateExtras/tests/runtime.lua` (or `npx --yes --package fengari-node-cli fengari EllesmereUINameplateExtras/tests/runtime.lua`). The mocked runtime tests cover delayed SavedVariables loading, table replacement, option callbacks, new rules, scale updates, frame recycling, and disabling styles. Cast tests cover engine repaints, texture replacement and spark anchors, interrupt flashes, opacity, borders, and restoration. They do not replace in-game testing on Forever and Retail.
