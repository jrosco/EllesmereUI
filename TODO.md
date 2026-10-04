# TODO

Ideas for future EllesmereUI Nameplate Extras features.

## Rule conditions

- [ ] Health thresholds: match units below a configurable health percentage.
- [ ] Specific spell casts: match by spell ID or name, with interruptible, channelled, and empowered cast options.
- [ ] Threat state: match when the player or another tank has aggro, or when threat is near a pull.
- [ ] Aura state: match units with a specific buff, debuff, or crowd-control effect.
- [ ] Unit priority: distinguish bosses, rares, enemy players, pets, and quest objectives.

## Styling actions

- [ ] Independently color name text, cast bar, and cast icon.
- [ ] Add glow or pulse effects for urgent casts, low health, or dangerous auras.
- [ ] Apply separate styles to the current target, focus, and mouseover.

## Rule management

- [ ] Support “match all” versus “match any” condition logic.
- [x] Export/import rule sets and copy them between characters.
- [ ] Add starter presets such as Interrupts, Questing, and PvP.

## Implementation notes

- [ ] Gracefully skip conditions when a client restricts or does not expose the required combat information.
- [ ] Start with specific spell casts or health thresholds as the next feature candidates.
