# Briar Warden integration contract

Native Godot 4.7 PC game, world XZ, up Y, forward -Z. Player begins
(-3,0,3), boss (2,0,-2). Arena playable rectangle X +/-11, Z +/-7.
Souls-like difficulty with committed attacks and meaningful stamina costs.

## Scripts

- `arena.gd`: Node3D, builds environment on ready, static collider layer 1.
- `actor_visual.gd`: Node3D, `setup(is_boss: bool)`, then
  `update_pose(state: String, progress: float, direction: Vector3,
  moving_speed: float, combo: int, delta: float)`.
  States idle/move/attack/skill/dodge/block/parry/hurt/stagger/dead;
  combo 0/1/2; normalized action progress; active swing .30-.60.
  `get_blade_points()` returns [base, tip] as world Vector3 array.
- `combat.gd`: Node3D owns player + boss CharacterBody3D, creates their visuals.
  `setup(camera: Camera3D)`, `restart()`, `snapshot() -> Dictionary`.
  Signals `stats_changed(data: Dictionary)`,
  `combat_event(kind: String, at: Vector3, direction: Vector3, amount: float)`,
  `encounter_ended(victory: bool)`.
  `player` and `boss` properties accessible to camera and verification.
  Public `request_player_action(action: String)`, `force_boss_action(action: String)`
  for deterministic verification. Never grant test invulnerability in regular play.
  Stats dictionary: hp/max_hp/stamina/max_stamina/boss_hp/boss_max_hp/
  skill_cd/heals/locked/boss_state/player_state/parries/combo.
- `main.gd`: root integrates arena, combat, camera, HUD, VFX and sound;
  maps InputMap before combat creates bodies.
- `hud.gd`: CanvasLayer receives snapshots/events; pause/retry/quit signals.
- `effects.gd`: Node3D feedback(kind,at,direction,amount), no gameplay ownership.

## Input actions

move_left A, move_right D, move_up W, move_down S;
attack left mouse; block held right mouse;
parry right mouse held + left mouse pressed (takes precedence over attack);
dodge Shift (tap roll; no separate sprint required for first prototype);
skill Q; heal R; lock_target Tab;
pause Esc; retry F5; fullscreen F11. Optional gamepad mapping later.

## Event names

swing / hit / hurt / block / guard_break / parry / dodge / skill /
boss_swing / boss_telegraph / boss_parry_ready / slam / shockwave /
heal / death / victory / empty.

Root handles impact sound and camera shake. Combat may use short hit stop via
its own timer; avoid Engine.time_scale conflicts with pause. Boss parryable
thrust distinguished by gold cross/glint; normal slam uses red ground warning.
Boss attack names slash, slam, thrust. Health 130 player, 1100 boss; damage
roughly 30/38/55 combo, 100 skill, 27/48/42 boss; 3 heals, 100 stamina.
Keep damage/tempo values centralized in combat script or config.
