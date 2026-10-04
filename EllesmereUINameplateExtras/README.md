# EllesmereUI Nameplate Extras


This extensible add-on currently provides one feature: **Nameplate Style**. It adds a **Nameplate Extras > Nameplate Style** section using `EllesmereUI.RegisterPlugin`; it does not modify the built-in Nameplates options page.

The **Rules** page starts with **Enable rule styling**, the master switch for the active profile. Turning it off restores EUI appearance while keeping the saved rules, order, selection and individual enabled flags; editing remains available. The **About** page provides a short overview of custom appearances, cast colors, profiles and sharing.

## Character profiles

The **Profiles** tab assigns a named rules profile to each character. **Default** is shared by characters that have not selected another profile. Creating a profile starts with the built-in default rules and appearance settings, then assigns only the current character; selecting the same named profile on other characters shares its rules with them. Renaming or deleting a named profile updates every character assigned to it. EUI's own active profile does not control these assignments; use **Copy Rule** to duplicate an individual rule.

## Included rules

Three starter rules are enabled: current target, elite enemy, and enemy casting. Add up to 12 rules, copy the selected rule, edit their conditions and visual effects, and move them to change priority. A copy is inserted after its source and selected for editing. New rules start enabled for the current target. The first enabled matching rule wins.

Categorical conditions use multi-select checklists: player/NPC/pet/creature, friendly/enemy/neutral, normal/elite/rare/rare elite/boss/minor, current-target state, cast/channel/empowered/interruptibility, and spell school. Multiple choices within a condition match with OR; separate condition groups combine with AND. Leaving a checklist empty means Any. Quest objective remains an optional toggle and uses EUI's cached tooltip-based detector for incomplete objectives in the player's own quest log, following EUI's Show In Instances setting. Combat-log school tracking is enabled only when at least one enabled rule selects a specific school. A spell school is learned when its cast-start event is seen; unknown spells do not match school-specific rules.

Target state separates three cases: **Current target** matches the selected unit; **Not current target** requires a selected target and matches other units; **No target selected** matches only when you have no target. Not current target no longer includes the no-target case, including for existing saved/imported rules. Select both Not current target and No target selected if you want that older combined behavior. Empty/Any still imposes no target restriction.

Empty or missing target selections stay unrestricted across reloads, profile switches, and imports; No-only selections stay No-only. The elite and enemy-casting starter rules also apply to non-targets. Earlier versions could add Yes to saved target selections during profile normalization. Existing Yes values are preserved because they may be intentional; review the Target state checklist if a rule previously changed behavior unexpectedly.

Effects include health-bar color, whole-nameplate scale and opacity, an additional colored health-bar border, and a choice of EUI/flat/Blizzard health texture.

## Health-bar overrides

The Health Bar section uses the same layout as Cast Bar: a master **Override health bar** switch, **Custom health color** beside its color picker, a texture selector, and **Additional health border** beside its color picker with thickness below. Controls are dimmed when their override is off.

The border toggle preserves its saved color and thickness. Existing rules keep their previous appearance; a saved border size of zero remains off until enabled. Turning the health master off restores EUI color/texture and hides only the plugin's additional border. Whole-nameplate size/opacity and cast-bar overrides remain independent.

Tap-denied enemies keep EUI's tapped health-bar color; this plugin suspends only its health-color override while another player has the tap.

## Cast-bar overrides

Appearance is grouped into **Nameplate**, **Health Bar**, and **Cast Bar**. In the Cast Bar section, enable **Override cast bar** for the selected rule. Existing rules leave this off. Inactive controls remain visible but dimmed, with tooltips explaining what to enable.

- **Custom cast color** tints the fill and uninterruptible overlay; the interrupted flash and other EUI cast indicators are preserved.
- **Interruptible cast**, **Interrupt on CD**, and **Uninterruptible cast** target EUI's three cast-color states. Enable Override cast bar and Custom cast color on each rule; different rules can supply different colors. The first rule whose other conditions match wins **per color state**, and EUI's native cooldown and interruptibility evaluators choose the displayed color even when those values are secret. Unmatched states keep EUI's color. No Casting checkbox or separate appearance toggle is required. Explicit Casting targets all three states. Interruptible cast uses the normal/interrupt-available state; Interrupt on CD uses the player's active interrupt cooldown; Uninterruptible has precedence over both. Without a usable interrupt cooldown, EUI uses its normal state.
- These three cast-color checkboxes are available with EUI and Classic WoW UI nameplate styles, and inactive with Blizzard or WoW Forever styles. Hovering explains that EUI or Classic WoW UI style and a UI reload are required. Saved selections are preserved. Casting, Not casting, Channeling and Empowered cast remain available. Availability follows the style actually rendered this session, rather than profile changes awaiting reload.
- The same capability policy is enforced at runtime: saved or imported state-only color selections supply no overrides under unsupported styles. Any, explicit Casting, and matching broad cast-kind selections retain generic tinting. In mixed selections, a matching broad choice tints all states; blocked state choices cannot broaden a nonmatching cast kind.
- Interruptible cast, Interrupt on CD, and Uninterruptible cast implicitly enable active Casting for nameplate size, health styling, texture, opacity and borders without checking Casting in the editor. Those effects use the first matching active-cast rule, even if interruptibility/cooldown is secret or unavailable; they are not restricted to the selected color state. The cast-color renderer still picks overrides independently per state. Other filter groups remain AND requirements. Empowered and Channeling remain specific to their cast kinds. Selecting a subtype clears broad Casting in the editor; existing combined saved selections are preserved, so uncheck Casting once on rules from the earlier auto-selection implementation to scope their colors.
- **Cast-bar texture** offers the same built-in and SharedMedia texture choices as the health bar. Stock Blizzard-style cast artwork retains its atlas; this texture override applies to EUI and Classic styles.
- **Custom cast opacity** fades the cast subtree, including when casts are lifted in front of nameplates.
- **Additional cast border** adds its own outline with color and thickness controls without replacing the EUI border.

Turning an override off, disabling the plugin, or leaving a matching rule restores the engine-authored cast settings. Rules still use first-match priority; a higher rule can take precedence over a cast-specific rule. Friendly plates currently have no EUI cast bar, so these settings do not add one.

Cooldown/interruptibility transitions still reevaluate matching snapshots for extensions that use readable state knowledge. Stable repaints do not trigger repeated ordinary-rule refreshes. A custom predicate requiring restricted information remains fail-closed, but the built-in color-state selections themselves only require an active cast for other appearance effects.

## Install

Copy the `EllesmereUINameplateExtras` folder into `Interface/AddOns`. It requires both `EllesmereUI` and `EllesmereUINameplates` to be enabled. Open the EUI options panel and select **Nameplate Extras > Nameplate Style**. As the addon is in early development, it starts with fresh `EllesmereUINameplateExtrasDB` settings; the former Styles settings/API are not migrated or aliased.

## Extension points

The public runtime API is `EllesmereUINameplateExtras`. Future features can be registered as additional modules in `EllesmereUINameplateExtras_Options.lua`; runtime matchers/effects belong in `EllesmereUINameplateExtras.lua` and its feature modules. Other addon code can call:

```lua
EllesmereUINameplateExtras.Refresh()
EllesmereUINameplateExtras.GetRules()
```

`RegisterCondition(key, predicate)` adds a custom matcher for a corresponding key stored in a rule's `conditions` table. Predicates receive `(unitToken, traits, expectedValue, rule)` and should return `true` for a match. `RegisterSpellSchool(spellID, school)` can seed school metadata (`physical`, `holy`, `fire`, `nature`, `frost`, `shadow`, `arcane`, or `mixed`). After changing a rule programmatically, call `Refresh()`.

Rendering shares readable-condition and predicate results between ordinary and cast-color selection within one unit/rule refresh. Results are not retained between refreshes. Standalone selectors and diagnostics evaluate freshly. `SupportsCastColorStates()` exposes the shared editor/runtime style capability.

## Standalone rule-set sharing

The **Sharing** tab is separate from rule editing. Use **Export Rule Set** to open a copyable code, then paste it on another character with **Import Rule Set**. The code contains only the rule list (names, conditions, and appearance settings); importing replaces the currently selected character profile's rules and selects the first one. It does not import the profile assignment or global enable toggle. New codes use the `!EUI_NPEX_RULES2!` prefix; older `!EUI_NPEX_RULES1!` codes remain importable. These codes do not use EUI's full profile import/export.

## Diagnostics and tests

Run `/npextras cast` while your target is casting to report its cast kind, interruptibility (`interruptible`, `uninterruptible`, or `unknown`), known color state, and the chosen rule for each cast-color state. Secret values are never inspected or printed. An unknown secret value can still drive native color rendering even though Lua cannot identify the active color branch. The winning nameplate rule is reported separately. The command does not require a visible nameplate.

Run `/npextras` with a visible enemy target to report matching rules and reapply the current style. Diagnostics v3 uses the same settings accessor as the options page; `settings shared with options` should be `true`. Settings initialize after SavedVariables load and rebind if the global table is replaced.

Scale is a multiplier on EUI's base scale, including its target/cast animation. The plugin does not modify EUI's animation values.

From the repository root, run `lua EllesmereUINameplateExtras/tests/runtime.lua` (or `npx --yes --package fengari-node-cli fengari EllesmereUINameplateExtras/tests/runtime.lua`). The mocked runtime tests cover delayed SavedVariables loading, table replacement, multi-select matching and legacy imports, option callbacks, new rules, scale updates, frame recycling, and disabling styles. Cast tests cover engine repaints, texture replacement and spark anchors, interrupt flashes, opacity, borders, and restoration. They do not replace in-game testing on Forever and Retail.

Run `lua EllesmereUINameplateExtras/tests/schema.lua` (or `npx --yes --package fengari-node-cli fengari EllesmereUINameplateExtras/tests/schema.lua`) for focused target reload/profile-switch regressions and shared condition validation/normalization checks, including all categorical values, version 1/2 imports, and custom-condition preservation.

Focused follow-up suites are `tests/style-capability.lua`, `tests/cooldown-transitions.lua`, and `tests/predicate-snapshot.lua` inside `EllesmereUINameplateExtras`. Run each from the repository root with Lua or Fengari. They cover saved/imported style restrictions, targeted cooldown refreshes and restoration, and per-refresh predicate consistency; real reload/cooldown events and Retail restricted values still require in-game checks.

Run `lua EllesmereUINameplateExtras/tests/cast-appearances.lua` (or use Fengari) to verify that each color-state selection applies other appearances through implicit Casting without broadening its color mask. It covers known/secret/unavailable flags, channels/empowered casts, AND filters, ordinary first-match priority, and restoration at cast end. The cooldown suite separately exercises explicit extension predicates that require readable state knowledge.

Run `lua EllesmereUINameplateExtras/tests/target-states.lua` (or use Fengari) for target-present/absent matching, retargeting and clearing-target appearance transitions, legacy scalar conditions, OR combinations, other AND filters, and restricted-value handling.
