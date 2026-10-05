# EllesmereUI Extend Nameplates


This extensible add-on currently provides one feature: **Nameplate Style**. It adds an **Extend Nameplates > Nameplate Style** section using `EllesmereUI.RegisterPlugin`; it does not modify the built-in Nameplates options page. The addon folder/ID is `EllesmereUIExtendNameplates`, supporting Retail and Forever.

The **Rules** page starts with **Enable rule styling**, the master switch for the active profile. Turning it off restores EUI appearance and locks the rule editor while keeping saved rules, order, selection and individual enabled flags. Only the master toggle remains usable on Rules until styling is reenabled. Disabling the selected rule locks its name, conditions, appearance, Copy/Delete and reorder controls; rule selection, Add Rule and Rule enabled remain available while global styling is on. Lock tooltips explain what to enable, and existing override/style requirements still apply after unlocking. The **About** page provides a short overview of custom appearances, cast colors, profiles and sharing.

Under **Rule Order**, Edit rule and Rule name share one row. Add, Copy, Delete, Move Up and Move Down share a single action row that stays together during page search.

## Rules preview header

The **Rules** page has a fixed hero header using EUI's native `SetContentHeader` system, like its built-in Nameplates page. The combined sample contains a health bar, an always-visible cast bar with a repeating three-second cast/timer, and target arrows. It stays above the settings while you scroll and replaces the old inline previews. Profiles, Sharing and About have no preview header.

The sample follows the **selected rule's saved appearance**, without evaluating its match conditions or requiring a real unit/cast. Fill textures, colors, media borders, glows, opacity and arrow styles update immediately. Nameplate size and the Health bar, Cast bar, Text and Other scaling selections are reflected independently. Border/arrow settings that are not overridden fall back to the current EUI profile. Master bar overrides off leave the sample visible so nameplate opacity can still be inspected; global/individual rule locks dim the sample. The header reserves space for scaling/effects and fits narrow panels. Closing it or leaving Rules stops cast/glow animations; cached Rules headers resume and refresh their current size when restored.

## Per-rule text overrides

Under **Appearance – Text**, enable **Override text** to choose content in EUI's existing **Top, Left, Center, Right, Bottom-left and Bottom-right** nameplate slots and its **Cast name, Cast target and Cast timer** positions. **Use EUI setting** preserves native content; **None** hides a slot. The text override is independent of fill/border masters and follows the first matching ordinary rule. It is off by default.

Health/nameplate choices are **Name**, **Level**, **Health percentage**, **Current health**, **Maximum health**, **Current / maximum health**, and **Target of target**. Cast choices are **Spell name**, **Cast target**, **Remaining time**, **Elapsed time**, **Total time**, and **Elapsed / total time**. Positions, font sizes, offsets and width/wrap settings follow the corresponding EUI slot settings; cast labels reserve room for the timer. Health text belongs to Text scaling; cast text follows Cast bar scaling, opacity and lifted casts.

In **Text Colors**, each element has an independent override toggle and color picker. Color-only overrides can tint EUI's existing labels without replacing their content. EUI-combined name/level labels retain native embedded color formatting; choose separate name and level slots for fully independent colors. Native stock level artwork/level boxes are not new text-slot positions. Turning text/color overrides off, leaving a match, disabling styling or recycling reveals EUI's latest text visibility and colors. The native Interrupted label takes precedence during interrupted flashes. Saved content/colors are preserved when the master is disabled and are included in validated rule sharing.

The pinned Rules header displays the selected content/colors, including custom sample cast-time formats. Retail health percentages use the native ScaleTo100 curve, while health/name/duration values go directly to native text-format sinks without branching or arithmetic on secrets. Forever uses EUI's available number formatter and guarded readable health/timestamp fallbacks. Cast-target-name APIs are Retail-only: unavailable or restricted display decisions produce blank text rather than guessing a cast target from the unit's temporary target. Unknown health/time data is also left blank when no safe rendering path is available. Actual layouts and restricted-content behavior still need testing on both clients.

## Character profiles

The **Profiles** tab assigns a named rules profile to each character. **Default** is shared by characters that have not selected another profile. Creating a profile starts with the built-in default rules and appearance settings, then assigns only the current character; selecting the same named profile on other characters shares its rules with them. Renaming or deleting a named profile updates every character assigned to it. EUI's own active profile does not control these assignments; use **Copy Rule** to duplicate an individual rule.

**Reset Nameplate Style** resets the active Extras profile to fresh built-in settings, including rule order, selection, enabled state and all appearance/condition overrides. It preserves the profile name, character assignments and other profiles. Reset normalizes the starter conditions and rebuilds the editor/header immediately. The Non Target starter selects both Not current target and No target selected. After installing an updated addon build, `/reload` before resetting so the running addon uses that build's defaults.

## Included rules

Three starter rules are enabled: current target, elite enemy, and enemy casting. Add up to 12 rules, copy the selected rule, edit their conditions and visual effects, and move them to change priority. A copy is inserted after its source and selected for editing. New rules start enabled for the current target. The first enabled matching rule wins.

Categorical conditions use multi-select checklists: player/NPC/pet/creature, friendly/enemy/neutral, normal/elite/rare/rare elite/boss/minor, current-target state, player combat state, instance type, cast/channel/empowered/interruptibility, and spell school. Multiple choices within a condition match with OR; separate condition groups combine with AND. Leaving a checklist empty means Any. Quest objective remains an optional toggle and uses EUI's cached tooltip-based detector for incomplete objectives in the player's own quest log, following EUI's Show In Instances setting. Combat-log school tracking is enabled only when at least one enabled rule selects a specific school. A spell school is learned when its cast-start event is seen; unknown spells do not match school-specific rules.

**Player combat state** refers to **your character**, not the nameplate unit: select In combat, Out of combat, or both. Leaving it empty enables both states without restricting the rule. Combat-start/end events reapply matching appearance and restore native styling when a rule stops matching.

**Instance Type** describes where your character is: Open world, Dungeon, Raid, Battleground, Arena, Scenario or Delve. It is not group type—you can be in a raid group in the open world. An empty selection means Any; multiple choices use OR. Retail delves are distinguished from scenarios using their instance difficulty metadata (scenario/208), including after completion. Arena, Scenario and Delve choices are gated on Forever; saved/imported Retail choices remain preserved but do not match on that client. Supported choices in mixed selections still work. Unknown/restricted context fails closed for selected filters, while empty/Any stays unrestricted.

Both filters apply to ordinary appearances and per-state cast-color candidates, combining with the other condition groups using AND. Existing rules with no context selections retain their appearance. Context APIs are only queried when an enabled rule needs the corresponding filter. Zone/instance transitions and difficulty/info updates reevaluate rules alongside player combat transitions. Selections are included in the existing validated rules-only sharing format.

Target state separates three cases: **Current target** matches the selected unit; **Not current target** requires a selected target and matches other units; **No target selected** matches only when you have no target. Not current target no longer includes the no-target case, including for existing saved/imported rules. Select both Not current target and No target selected if you want that older combined behavior. Empty/Any still imposes no target restriction.

Threat filters describe the **aggro holder**, not your character's role: **Tank threat** matches an enemy held by a tank; **Non-tank threat** matches one held by a Damage/Healer; **Threat on me** matches when you hold aggro, independently of your role. Choices combine with OR and other filter groups remain AND requirements. Detailed threat confirms the holder; an enemy's temporary spell target is not assumed to hold aggro. Current-target API pairings are used when available. Secret/unavailable threat data and unassigned/hidden roles cannot match the corresponding filter. Threat on me can still match with an unknown role. Empty/Any remains unrestricted and does not trigger threat scans.

Empty or missing target selections stay unrestricted across reloads, profile switches, and imports; No-only selections stay No-only. The elite and enemy-casting starter rules also apply to non-targets. Earlier versions could add Yes to saved target selections during profile normalization. Existing Yes values are preserved because they may be intentional; review the Target state checklist if a rule previously changed behavior unexpectedly.

Effects include health-bar color, selective nameplate scale and opacity, native border overrides, and a choice of EUI/flat/Blizzard health texture.

## Nameplate scaling

The cog beside **Nameplate size (%)** selects which elements receive that rule's size multiplier: **Health bar**, **Cast bar**, **Class resources**, **Text**, and **Other elements**. Text includes nameplate name, health, level, target-of-target, threat, classification and friendly subtitle text. Cast-bar text follows Cast bar; aura counters follow Other elements. Other elements includes buffs, debuffs, crowd control, cast-lockout indicators, markers and selection indicators. **Scale all** enables every category; switching it off clears every category so you can select only the elements you want. Existing and new rules default to scaling all elements.

Unchecked categories keep EUI's own size, including its target/cast animations and independent element settings. Health/cast child decorations follow their bar; class-resource textures and decorations, pooled aura rows, and lifted casts retain their category selection. Text is controlled separately from bars and Other elements, including text parented to the health bar. Markers remain under Other even when parented to a text host. Rule changes, disabling styling, and frame recycling restore the latest engine-authored scales. The cog follows the same global and individual-rule locks as the size slider, including an already-open popup.

Native parent-scale flags, parent references and scale getters can become secret under Retail restrictions. Extras checks them before branching or arithmetic. When a component's inheritance is unreadable, it releases its local compensation where possible and leaves the inherited sizing in place until a later readable refresh; it does not guess the hidden flag.

Selections are saved per rule as `style.scaleElements`, a boolean map of category keys. Missing keys mean enabled, preserving older rules. Rule sharing includes these selections and rejects malformed or unknown category entries. The retired buffs/debuffs/CC selections are removed when loading settings or importing older codes; those elements follow the existing Other elements choice, which defaults to enabled.

Older rules with Other elements disabled also start with Text disabled to preserve their appearance. Once edited, Text and Other are independent, and their selections survive sharing and profile changes.

The integration is contained entirely in `EllesmereUIExtendNameplates`; no edits to EllesmereUI or EllesmereUINameplates are required. It observes existing Nameplates refresh functions and AuraKit's deferred group construction, tracks aura-holder transfers, and adapts the existing warrior-charge rendering helper's geometry input.

## Health-bar overrides

The Health Bar section uses the same layout as Cast Bar: a master **Override health bar** switch, **Custom health color** beside its color picker, a fill-texture selector, and **Override health border** beside its color picker. **Health border texture** and size share the next row. Controls are dimmed when their override is off.

The combined Rules header previews the selected rule's health/cast fill textures, colors, opacity and media borders. **Use EUI texture** shows the corresponding fill texture from the current EUI profile. Health uses a fixed sample value and cast progress repeats, rather than reading live units/casts. Turning an override off restores its baseline sample without dimming the preview, so nameplate opacity remains visible. Global styling and individual-rule editor locks still dim the samples.

The border toggle preserves its saved color, texture and thickness. Older rules without a border-texture selection use **Solid**; a saved health border size of zero remains off until enabled. Turning the health master off restores EUI color, fill texture and native border. Whole-nameplate size/opacity and cast-bar overrides remain independent.

## Media border overrides

**Override health border** and **Override cast border** replace the corresponding native outlines rather than adding a second border. Texture choices come directly from `EllesmereUI.GetBorderTextureDropdown()` (Solid, Blizzard, Glow, other built-in media and installed SharedMedia borders). Both live bars and previews use `EllesmereUI.ApplyBorderStyle()` with the native `nameplates` defaults. Solid borders use physical-pixel thickness and native scaleGuard; textured borders use EUI's four size steps and registered media offsets.

While a border override is active, the native outline is suppressed but EUI continues updating its own texture, size, color and visibility underneath. Turning the border or bar override off, leaving a matching rule, disabling styling or recycling a plate releases the replacement and reveals EUI's latest border state. Health/cast overrides are independent. Replacement casts follow the cast subtree, including lifted casts. Native wrapping is suppressed where it conflicts with the independent replacement outlines and resumes when the cast override ends. Stock border artwork is replaced while keeping a plain profile-colored bar background; native icons, text, fill and selection effects retain their ownership.

All implementation stays inside Extras. It requires EUI's shared border-rendering API; older builds without that API leave native borders untouched. Retail restricted geometry is handled by EUI's renderer and secret alpha values are only forwarded to setters, not inspected. Native textured rendering and wrap/stock-style positioning need in-game verification on Retail and Forever.

## Animated border glows

**Health border glow** and **Cast border glow** add independent animated effects alongside the media borders. Only bar-suited effects are offered: **None**, **Pixel Glow**, and **Auto-Cast Shine**, with a separate color for each bar. Both bars in the combined Rules header show their glow. The Pixel Glow cog exposes lines, thickness, speed and an optional background/color. For Auto-Cast Shine, the cog exposes **Sparkle size (%)**, independently for health and cast bars: 50–200%, with 100% matching EUI's normal sparkles. This changes the individual sparkle sizes, not the bar, orbit speed or sparkle count. The Extras adapter calls EUI's public lower-level Shine renderer and reuses animations until color, dimensions or sparkle size changes; no EUI files are modified.

Glows default to None and use the **first matching ordinary rule**, with the existing conditions and priority. They require the corresponding health/cast master override, but do not require a custom border override: they can surround EUI's original border too. Health glows follow the Health bar scaling category; cast glows follow Cast bar and stay with lifted casts. They inherit the bar/nameplate opacity. Leaving a match, disabling the corresponding master or styling, and recycling tear down the effect. Hidden previews stop animating and restart when the page is shown again.

While the plugin's cast glow is running, EUI's **Important Cast Glow** is temporarily suppressed to avoid overlapping effects. EUI retains ownership of its important-cast state and keeps updating underneath; choosing None or stopping the plugin glow restores its latest visibility/alpha, including secret native decisions. Health glows do not suppress Important Cast Glow. The plugin does not call Retail-only `C_Spell.IsSpellImportant`; match-driven glows also work on Forever and neither supported effect requires Retail action-button atlases. Restricted Retail visibility uses EUI's native-animation engine host: Auto-Cast Shine temporarily renders Pixel Glow there rather than a frozen Lua driver, retaining the selected Shine style/size for when it becomes readable again. Layout dimensions come from clean authored settings/setters, never restricted bar measurements.

Glow settings are included in validated rule sharing. Unsupported styles and malformed colors/parameters are rejected. All changes remain in Extras; native animation and positioning still require in-game verification on Retail and Forever.

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
- **Override cast border** replaces EUI's outline with the selected media border texture, color and size; switching it off restores the native cast border.

Turning an override off, disabling the plugin, or leaving a matching rule restores the engine-authored cast settings. Rules still use first-match priority; a higher rule can take precedence over a cast-specific rule. Friendly plates currently have no EUI cast bar, so these settings do not add one.

Cooldown/interruptibility transitions still reevaluate matching snapshots for extensions that use readable state knowledge. Stable repaints do not trigger repeated ordinary-rule refreshes. A custom predicate requiring restricted information remains fail-closed, but the built-in color-state selections themselves only require an active cast for other appearance effects.

## Target-arrow overrides

Under **Appearance – Target Arrows**, enable **Override target arrows** and choose **Target-arrow style**. The combined Rules header and dropdown thumbnails show EUI's available artwork: Simple, Double, Winged, Feathered, Split, Celestial, Rune, Demon, Halo, Curved, Barbed, Holy Spear, Bracket, Diamond, Crystal and Classic. **Use EUI arrow style** follows the current EUI profile's style while letting the matching rule show arrows.

The first enabled matching ordinary rule controls these arrows, using the existing target, classification, reaction, cast, threat and other conditions. For example, place an elite-target rule with Winged above a casting-target rule with Double, followed by a general current-target rule with Simple. Overrides are off by default; a higher-priority matching rule without an arrow override preserves EUI's normal arrows rather than using a lower rule's override.

Arrows remain **current-target indicators**. A matching non-target/no-target rule does not add arrows to other units. An enabled override can show arrows even when EUI's general target-arrow setting is off. Color and size follow EUI's current settings; friendly bars retain EUI's friendly arrow-size convention. In selective scaling, arrows belong to **Other elements**.

Turning the override off, leaving its match, disabling rules/styling, retargeting or recycling restores EUI's arrow behavior. Native target/marker/layout repaints retain the winning override. Retail creation uses the available aura-anchor aspect template, with safe fallback when layout/target data is restricted; Forever/older clients can use the plain-parent, fully anchored layout. Friendly name-only overlays without a health bar remain outside the ordinary-rule renderer. Arrow settings share with rules and unknown styles/malformed flags are rejected. All integration remains in Extras.

## Install

Copy the `EllesmereUIExtendNameplates` folder into `Interface/AddOns`. It requires both `EllesmereUI` and `EllesmereUINameplates` to be enabled. Open the EUI options panel and select **Extend Nameplates > Nameplate Style**. Do not run the previous Nameplate Extras addon alongside it, since both would style the same plates.

The addon starts with fresh `EllesmereUIExtendNameplatesDB` settings. There is no settings migration, old API alias or old slash-command alias. Rule-set prefixes and the serialized wire-format identifier remain stable, so sharing codes continue to use the existing codec.

## Extension points

The public runtime API is `EllesmereUIExtendNameplates`. Future features can be registered as additional modules in `Options.lua`; runtime matchers/effects belong in `Nameplates.lua` and its feature modules. The TOC retains the addon-folder name (`EllesmereUIExtendNameplates.toc`) as required for WoW addon discovery. Other addon code can call:

```lua
EllesmereUIExtendNameplates.Refresh()
EllesmereUIExtendNameplates.GetRules()
```

`RegisterCondition(key, predicate)` adds a custom matcher for a corresponding key stored in a rule's `conditions` table. Predicates receive `(unitToken, traits, expectedValue, rule)` and should return `true` for a match. `RegisterSpellSchool(spellID, school)` can seed school metadata (`physical`, `holy`, `fire`, `nature`, `frost`, `shadow`, `arcane`, or `mixed`). After changing a rule programmatically, call `Refresh()`.

Rendering shares readable-condition and predicate results between ordinary and cast-color selection within one unit/rule refresh. Results are not retained between refreshes. Standalone selectors and diagnostics evaluate freshly. `SupportsCastColorStates()` exposes the shared editor/runtime style capability.

## Standalone rule-set sharing

The **Sharing** tab is separate from rule editing. Use **Export Rule Set** to open a copyable code, then paste it on another character with **Import Rule Set**. The code contains only the rule list (names, conditions, and appearance settings); importing replaces the currently selected character profile's rules and selects the first one. It does not import the profile assignment or global enable toggle. New codes use the `!EUI_NPEX_RULES2!` prefix; older `!EUI_NPEX_RULES1!` codes remain importable. These codes do not use EUI's full profile import/export.

## Diagnostics and tests

Run `/enp cast` while your target is casting to report its cast kind, interruptibility (`interruptible`, `uninterruptible`, or `unknown`), known color state, and the chosen rule for each cast-color state. Secret values are never inspected or printed. An unknown secret value can still drive native color rendering even though Lua cannot identify the active color branch. The winning nameplate rule is reported separately. The command does not require a visible nameplate.

Run `/enp` (or `/extendnameplates`) with a visible enemy target to report matching rules and reapply the current style. Diagnostics v3 uses the same settings accessor as the options page; `settings shared with options` should be `true`. Settings initialize after SavedVariables load and rebind if the global table is replaced.

Scale is a multiplier on EUI's base scale, including its target/cast animation. The plugin does not modify EUI's animation values.

From the repository root, run `lua EllesmereUIExtendNameplates/tests/runtime.lua` (or `npx.cmd --yes --package fengari-node-cli fengari EllesmereUIExtendNameplates/tests/runtime.lua`). Other suites live in the same `tests/` folder and can be run with that command by replacing `runtime.lua` with the suite filename. The mocked tests do not replace in-game testing on Retail and Forever.

Run `tests/schema.lua` within the renamed addon for target reload/profile-switch regressions, shared condition validation/normalization, categorical values, v1/v2 imports, and custom-condition preservation.

Focused follow-up suites are `tests/style-capability.lua`, `tests/cooldown-transitions.lua`, and `tests/predicate-snapshot.lua` inside `EllesmereUIExtendNameplates`. They cover saved/imported style restrictions, targeted cooldown refreshes/restoration, and per-refresh predicate consistency; real reload/cooldown events and Retail restricted values still need in-game checks.

`tests/cast-appearances.lua` verifies implicit Casting appearances without broadening color masks, including readable/secret/unavailable flags, channels/empowered casts, AND filters, priority and restoration.

`tests/target-states.lua` covers target-present/absent matching, retargeting/clearing-target transitions, legacy conditions, OR/AND logic and restricted values.

`tests/threat.lua` covers aggro-holder roles, Threat on me, roster lookup, temporary spell targets, restrictions, API gating and threat/role-change refreshes.

`tests/ui-locks.lua` verifies editor locks, hover explanations, stale callbacks, preserved data, reenable behavior and override prerequisites.

`tests/scaling.lua` and `tests/scaling-options.lua` cover category combinations, effective scales, engine animations/writes, lifted casts, lazy decorations, pool transfers, restoration, cog defaults/locks and sharing. Native positioning still needs an in-game check.

`tests/appearance-previews.lua` covers hero-preview appearance updates, media fallbacks, opacity, selected rules and locks; `tests/options-search.lua` covers frameless prebuild safety and searchable layouts.

`tests/target-arrows.lua` and `tests/target-arrow-options.lua` cover matching/priority, retargeting, native repaints/restoration, restrictions, Retail templates, Forever fallback, friendly targets, scaling, previews, sharing and locks.

`tests/border-overrides.lua` covers native outline suppression/restoration, independent bars, stock art, scaleGuard, recycling and secret-safe alpha forwarding.

`tests/rule-glows.lua` and `tests/glow-options.lua` cover bar glows, borders, authored geometry, Important Cast restoration, restrictions, Forever, scaling, previews, Pixel/Shine settings, stale callbacks and sharing.

`tests/header-preview.lua` covers the pinned Rules-only header, repeating casts, scrolling, combined bars/arrows, scaling, caches, sizing and teardown.

`tests/text-overrides.lua` and `tests/text-options.lua` cover text content/colors, native restoration, secret sinks, Forever fallbacks, previews, locks and sharing.

`tests/combat-instance.lua` and `tests/context-options.lua` cover combat/instance matching, Any, OR/AND, palettes, API gating, events, restrictions, Forever, editing and sharing.

`tests/reset-defaults.lua` covers active-profile reset, pristine templates, normalized conditions, Non Target selections and editor/header refresh. `tests/rename.lua` verifies the renamed identity and fresh settings without legacy aliases or migration.
