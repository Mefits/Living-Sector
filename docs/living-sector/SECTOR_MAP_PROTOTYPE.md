# Sector map prototype — scope and review

Branch: feature/sector-political-map (not yet merged into living-sector-dev).

## Included

- Read-only egui window from the new Sector button next to the existing minimap toggle.
- Systems at their authoritative WorldRegistry universe coordinates.
- Colors from AgentStore.system_control (computed by the existing faction tick).
- Contested-body rings and faction legend.
- Only verified inter-system gate connections from AgentStore.gate_pairs, resolved through LocationInfo.celestial_body_id and BodyIdentity.db_id.
- Pan by drag, zoom slider, select a system, center the existing 3D camera.
- Close via the top-right window control or existing Escape panel-stack behavior.

## Out of scope

- No true faction border polygons: translucent halos mark control only.
- No new political or economic behavior, no guessed lines between systems.
- No permanent map annotations or historic time slider.
- No persistence changes; the upstream client save issue remains open.
- No assertion of a working binary until tests are run.

## Validation before merging

1. cargo check -p client_bevy
2. cargo test -p sim_core
3. Boot a new world on Windows; click Sector, pan/zoom, click a system and use Focus in 3D.
4. Confirm systems show the correct faction after the faction control tick; unknown at boot is acceptable.
5. Confirm line count matches actual cross-system gate pairs and no fabricated routes appear.
6. Check Escape closes the map and the main menu remains unaffected.
7. Check controls remain visible at 1280x720 and 1920x1080.
8. Review changes when pulling new upstream commits.

This is a focused architecture experiment. Once verified, expand to a dedicated full-window strategy map and territory geometry without touching the simulator rules.
