# Original articulated character models — revision 2

These assets were created locally in Blender 5.2 for Briar Warden. They contain no external character assets. The `.blend` files are editable sources; Godot loads the identically named `.glb` files.

Revision 2 replaces the broad prototype surfaces with a shaped cuirass and bascinet, layered curved pauldrons, vambrace/cuisse/greave details, articulated knuckles, overlapping sabatons, rolled shield edging and convex enamel, raised tree heraldry, curved quillons and spiral grip wrapping, and thick folded cloth. The lord's crown and shoulder thorns follow curved, tapered branches.

The original 18 gameplay joint names, hierarchy, physical scale, and `BladeHilt` / `BladeTip` markers remain unchanged. The sword's marker distance remains 1.16 m for the knight and 1.8375 m for the lord. Parent actor rotation still controls facing; the imported assets face Godot -Z.

Opaque decoration is combined under each rigid pivot and uses a vertex palette. The blade and eyes retain separate materials for gameplay emission. The runtime visual script handles the Compatibility palette, outline, hit flash, and golden parry cue. Most meshes now have one surface rather than one surface per rivet, plate, or trim strip.

| Asset | V1 triangles | V2 triangles | V1 color surfaces | V2 color surfaces |
| --- | ---: | ---: | ---: | ---: |
| Wayfarer | 3,803 | 33,348 | 91 | 23 |
| Thorn lord | 4,092 | 34,096 | 101 | 22 |

The two-character review scene reports **769 → 181 draw calls**, including its unchanged ground, outline and shadow passes. This is a 76.5% reduction. Triangle counts describe the full exported source; Godot may choose generated LODs at gameplay distance.

Regenerate with `tools/build_characters.py` using Blender's background Python runner. The generator deliberately imports the stable original hierarchy from `source_v1/build_characters.py`, then replaces its surfaces and saves the complete V2 assets. `source_v1/` preserves the original `.blend`, `.glb`, generator and visual script; its `.gdignore` keeps these backups out of Godot imports.

Validation and close views:

- `tests/character_animation_check.gd`: 1,586 sampled frames, 11 actions, three attack directions, both actors; constant blade length, finite transforms and heal attachment checks.
- `tests/character_detail_review.gd`: matched V1/V2 front views, V2 back cloth view and action view, plus measured draw calls.
- `tests/character_v2_front.png`, `character_v2_back.png`, `character_v2_actions.png`, and `character_heal.png`.
- `model_metrics.json` and `tests/character_drawcalls.json` contain the measured counts.
