# V2 refinement

Keep existing project at D:/godot/briar_warden and existing input mappings.
Character and environment art should be visibly more detailed, in late sunset light.

Combat timing target: player and boss actions ~18% shorter, not instant.
Preserve readable windups and useful absolute parry window. Match travel distances
by increasing action movement speeds appropriately. Tests must follow new timings.

Root owns scripts/main.gd, scripts/hud.gd, final integration and capture/build.
Character agent owns tools/build_characters.py, assets/characters, scripts/actor_visual.gd.
Arena agent owns scripts/arena.gd, shaders/terrain.gdshader, new scripts/atmosphere.gd
and shaders for sunset lighting. Root calls atmosphere.setup() if provided.
Combat agent owns scripts/combat.gd, scripts/effects.gd and combat tests.

Combat/VFX contract: keep existing combat_event signal and main feedback hooks;
root will additionally call effects.sync_combat(combat) after combat.setup() to
attach combat reference and synchronize projectile/warning/shockwave presentation
from actual simulation objects. Effects must not simulate an independent damage
area. Ordinary slash has NO ground warning. Thrust uses a directional strip/wedge
following its actual forward attack path, with gold parry cue. Slam uses real
impact-centered radius and clearly animated fiery/dust shock front.

Q skill retains physical lunge and slash and launches one forward crescent shockwave:
projectile travels ~9m at ~13m/s, world static obstruction via swept collision,
hits boss at most once, visible core / trails / particles, no damage behind walls.
Projectile hit base damage 45; existing skill melee 100 may stack once when close.
Pause, restart, parry interruption and death must clear/pause appropriate warnings.

Do not overwrite unrelated projects or user-added project.godot settings. Keep
Compatibility renderer unless root explicitly switches it after measured tests.
