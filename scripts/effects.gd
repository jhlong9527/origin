extends Node3D

const MAX_SPARKS = 240
const SKILL_VFX_SCALE := 2.0
var particles: Array[Dictionary] = []
var sparks: MultiMeshInstance3D
var rings: Array[Dictionary] = []
var trail_mesh = ImmediateMesh.new()
var trail_material: StandardMaterial3D
var trail_history: Dictionary = {0: [], 1: []}
var audio_pool: Array[AudioStreamPlayer] = []
var sounds: Dictionary = {}
var audio_index = 0
var active_audio = true
var parry_anchor: Node3D
var rng = RandomNumberGenerator.new()
var combat_source: Node3D
var danger_mesh := ImmediateMesh.new()
var danger_instance: MeshInstance3D
var _last_sim_time := 0.0
var _generation := -1
var rendered_warning := ""
var rendered_projectiles := 0
var rendered_waves := 0
var eye_history := PackedVector3Array()
var eye_sample_time := -1.0
const ARROW_POOL_SIZE := 48
var arrow_pool: Array[Node3D] = []
var arrow_meshes: Array[Array] = []
var rendered_arrows := 0

func _ready() -> void:
	rng.seed = 84324
	var spark_mesh = SphereMesh.new()
	spark_mesh.radius = .028
	spark_mesh.height = .07
	spark_mesh.radial_segments = 4
	spark_mesh.rings = 1
	sparks = MultiMeshInstance3D.new()
	sparks.multimesh = MultiMesh.new()
	sparks.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	sparks.multimesh.use_colors = true
	sparks.multimesh.mesh = spark_mesh
	sparks.multimesh.instance_count = MAX_SPARKS
	sparks.material_override = _material(Color.WHITE, true)
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sparks)
	for i in MAX_SPARKS:
		particles.append({"life": 0.0, "pos": Vector3.ZERO, "vel": Vector3.ZERO, "color": Color.WHITE})
		sparks.multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3.ZERO))
	var trail = MeshInstance3D.new()
	trail.mesh = trail_mesh
	trail_material = _material(Color(0.66, 0.91, 0.91, .5), true)
	trail_material.vertex_color_use_as_albedo = true
	trail_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail.material_override = trail_material
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(trail)
	danger_instance = MeshInstance3D.new()
	danger_instance.name = "SimulationLinkedEffects"
	danger_instance.mesh = danger_mesh
	danger_instance.material_override = _material(Color.WHITE, true)
	danger_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(danger_instance)
	_build_arrow_pool()
	for i in 16:
		var mesh = ImmediateMesh.new()
		var instance = MeshInstance3D.new()
		instance.mesh = mesh
		instance.material_override = _material(Color(1, .6, .2, .6), true)
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
		instance.hide()
		rings.append({"node": instance, "mesh": mesh, "life": 0.0, "duration": 1.0, "radius": 1.0, "kind": ""})
	for i in 10:
		var player = AudioStreamPlayer.new()
		add_child(player)
		audio_pool.append(player)
	for kind in ["swing", "hit", "hurt", "block", "guard_break", "parry", "dodge", "skill", "projectile", "projectile_impact", "boss_swing", "boss_telegraph", "boss_parry_ready", "slam", "shockwave", "heal", "death", "victory", "empty", "weapon_switch", "bow_draw", "bow_release", "arrow_hit", "bow_land"]:
		sounds[kind] = _synthesize(kind)

func _material(color: Color, vertex: bool = false) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.vertex_color_use_as_albedo = vertex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat

func sound(kind: String) -> void:
	if not active_audio or not sounds.has(kind): return
	var player = audio_pool[audio_index % audio_pool.size()]
	audio_index += 1
	player.stream = sounds[kind]
	player.volume_db = -11.0 if kind != "parry" else -7.0
	player.pitch_scale = rng.randf_range(.96, 1.04)
	player.play()

func feedback(kind: String, at: Vector3, direction: Vector3, amount: float = 0.0) -> void:
	sound(kind)
	var color = Color("f7cb75")
	var count = 0
	match kind:
		"hit": count = 18
		"hurt":
			count = 14
			color = Color("e87668")
		"block": count = 22
		"parry":
			count = 50
			_ring(at, "parry", 1.8, .42, Color("ffe7a2"))
			for ring in rings:
				if ring.kind == "warning" or ring.kind == "parry_glint":
					ring.life = 0.0
					ring.node.hide()
		"guard_break": count = 30
		"dodge":
			count = 8
			color = Color("acb6a0")
		"skill":
			count = 24
			color = Color("a9eff0")
		"bow_release":
			count = 5 if amount > 0 else 2
			color = Color("d3f5e2") if amount > 0 else Color("dad3b2")
		"arrow_hit":
			count = 9 if amount > 0 else 4
			color = Color("e4c09a")
		"bow_land":
			count = 12
			color = Color("b2b5a0")
			_ring(at, "impact", .72, .23, Color(.60,.72,.62,.3))
		"boss_telegraph":
			pass # Geometry comes from combat.visual_state(), never an autonomous warning timer.
		"boss_parry_ready":
			count = 8
			pass # The glint is attached to the actual thrust's active state below.
		"slam":
			count = 42
		"shockwave":
			pass
		"projectile":
			count = 14
			color = Color("bdfff1")
		"projectile_impact":
			count = 32
			color = Color("7be8dc")
			_ring(at, "impact", .9, .24, Color("c1ffeb"))
		"heal":
			count = 24
			color = Color("a5dfb2")
			_ring(at, "heal", 1.1, .8, Color("b9deb3"))
		"victory", "death":
			count = 50
			_ring(at, "shockwave", 3.0, 1.3, Color("efc573"))
	var origin = at
	if kind in ["dodge", "slam", "shockwave"]: origin.y = .1
	_emit(origin, direction, count, color)

func _emit(at: Vector3, direction: Vector3, count: int, color: Color) -> void:
	for i in MAX_SPARKS:
		if count <= 0: break
		if particles[i].life > 0: continue
		particles[i] = {"life": rng.randf_range(.2, .65), "pos": at, "vel": Vector3(rng.randf_range(-2.9, 2.9), rng.randf_range(1.2, 4.2), rng.randf_range(-2.9, 2.9)) + direction * 1.8, "color": color}
		count -= 1

func _ring(at: Vector3, kind: String, radius: float, duration: float, color: Color) -> void:
	for ring in rings:
		if ring.life > 0: continue
		ring.life = duration
		ring.duration = duration
		ring.radius = radius
		ring.kind = kind
		ring.node.basis = Basis.IDENTITY
		ring.node.position = at + Vector3.UP * .045
		ring.node.material_override.albedo_color = color
		ring.node.material_override.no_depth_test = kind == "parry_glint"
		ring.node.show()
		break

func add_blade_sample(index: int, points: PackedVector3Array, active: bool, empowered: bool = false) -> void:
	if points.size() < 2: return
	if is_instance_valid(combat_source) and (combat_source._hit_stop > 0.0 or combat_source.ended): return
	if active:
		trail_history[index].push_front({"a": points[0].lerp(points[1], .24), "b": points[1], "life": .14, "empowered": empowered})
		if trail_history[index].size() > 12: trail_history[index].pop_back()

func _process(delta: float) -> void:
	if is_instance_valid(combat_source):
		var state: Dictionary = combat_source.visual_state()
		if _generation != state.generation:
			clear()
			_generation = state.generation
			_last_sim_time = state.time
		var simulation_delta: float = maxf(0.0, state.time - _last_sim_time)
		_last_sim_time = state.time
		if not state.ended: delta = simulation_delta
		_render_simulation(state)
	for i in MAX_SPARKS:
		var p = particles[i]
		if p.life <= 0: continue
		p.life -= delta
		p.vel.y -= 11.0 * delta
		p.pos += p.vel * delta
		if p.pos.y < .04:
			p.pos.y = .04
			p.vel *= .42
			p.vel.y = absf(p.vel.y)
		var size_scale = clampf(p.life * 6.0, 0.0, 1.0)
		sparks.multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size_scale), p.pos))
		sparks.multimesh.set_instance_color(i, p.color)
	for ring in rings:
		if ring.life <= 0: continue
		ring.life -= delta
		if ring.life <= 0:
			ring.node.hide()
			continue
		var fraction = 1.0 - ring.life / ring.duration
		var radius = ring.radius * (.4 + fraction * .6)
		if ring.kind == "warning": radius = ring.radius
		if ring.kind == "shockwave": radius = ring.radius * fraction
		var width = .045 if ring.kind == "warning" else .14 * (1.0 - fraction)
		var mesh: ImmediateMesh = ring.mesh
		mesh.clear_surfaces()
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		if ring.kind == "parry_glint":
			if is_instance_valid(parry_anchor): ring.node.global_position = parry_anchor.global_position + Vector3.UP * 3.6
			var view_camera = get_viewport().get_camera_3d()
			if view_camera: ring.node.basis = view_camera.global_basis
			for i in 8:
				var a = TAU * i / 8.0
				var b = TAU * (i + 1) / 8.0
				var ra = radius if i % 2 == 0 else radius * .18
				var rb = radius if i % 2 != 0 else radius * .18
				mesh.surface_add_vertex(Vector3.ZERO)
				mesh.surface_add_vertex(Vector3(cos(a), sin(a), 0) * ra)
				mesh.surface_add_vertex(Vector3(cos(b), sin(b), 0) * rb)
			mesh.surface_end()
			continue
		for i in 72:
			var a = TAU * i / 72.0
			var b = TAU * (i + 1) / 72.0
			var p1 = Vector3(cos(a), 0, sin(a)) * radius
			var p2 = Vector3(cos(b), 0, sin(b)) * radius
			var p3 = Vector3(cos(a), 0, sin(a)) * (radius - width)
			var p4 = Vector3(cos(b), 0, sin(b)) * (radius - width)
			for p in [p1, p2, p3, p2, p4, p3]: mesh.surface_add_vertex(p)
		mesh.surface_end()
		var mat: StandardMaterial3D = ring.node.material_override
		mat.albedo_color.a = minf(ring.life * 4, .8)
	trail_mesh.clear_surfaces()
	for index in trail_history:
		var history: Array = trail_history[index]
		for p in history: p.life -= delta
		while not history.is_empty() and history.back().life <= 0: history.pop_back()
		if history.size() < 2: continue
		trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in range(history.size() - 1):
			var p = history[i]
			var prev = history[i + 1]
			var trail_center: Vector3 = (p.a + p.b) * .5
			var pa: Vector3 = trail_center + (p.a - trail_center) * (SKILL_VFX_SCALE if p.empowered else 1.0)
			var pb: Vector3 = trail_center + (p.b - trail_center) * (SKILL_VFX_SCALE if p.empowered else 1.0)
			var prev_center: Vector3 = (prev.a + prev.b) * .5
			var prev_a: Vector3 = prev_center + (prev.a - prev_center) * (SKILL_VFX_SCALE if p.empowered else 1.0)
			var prev_b: Vector3 = prev_center + (prev.b - prev_center) * (SKILL_VFX_SCALE if p.empowered else 1.0)
			var col = Color("b5f3f1") if p.empowered else (Color("edc27e") if index == 1 else Color("dae3df"))
			col.a = clampf(p.life / .14, 0.0, 1.0) * .75
			trail_mesh.surface_set_color(col)
			for pos in [pa, pb, prev_b, pa, prev_b, prev_a]: trail_mesh.surface_add_vertex(pos)
		trail_mesh.surface_end()

func clear() -> void:
	for arrow in arrow_pool: arrow.hide()
	rendered_arrows = 0
	for p in particles: p.life = 0.0
	for i in MAX_SPARKS: sparks.multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3.ZERO))
	for ring in rings:
		ring.life = 0.0
		ring.node.hide()
	for history in trail_history.values(): history.clear()
	eye_history.clear()
	eye_sample_time = -1.0
	trail_mesh.clear_surfaces()
	danger_mesh.clear_surfaces()
	rendered_warning = ""
	rendered_projectiles = 0
	rendered_waves = 0
	for player in audio_pool: player.stop()


func sync_combat(source: Node3D) -> void:
	combat_source = source
	parry_anchor = source.boss
	_generation = source.encounter_generation
	_last_sim_time = source.simulation_time
	_render_simulation(source.visual_state())


func _triangle(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	danger_mesh.surface_set_color(color)
	danger_mesh.surface_add_vertex(a)
	danger_mesh.surface_add_vertex(b)
	danger_mesh.surface_add_vertex(c)


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	_triangle(a,b,c,color)
	_triangle(a,c,d,color)


func _band(center: Vector3, inner: float, outer: float, color: Color, height := 0.0, segments := 80) -> void:
	for step in segments:
		var a := TAU * step / segments
		var b := TAU * (step + 1) / segments
		var da := Vector3(cos(a), 0.0, sin(a))
		var db := Vector3(cos(b), 0.0, sin(b))
		_quad(center + da * maxf(inner,0.0), center + db * maxf(inner,0.0),
			center + db * outer + Vector3.UP * height, center + da * outer + Vector3.UP * height, color)


func _render_simulation(state: Dictionary) -> void:
	danger_mesh.clear_surfaces()
	rendered_warning = ""
	rendered_projectiles = 0
	rendered_waves = 0
	_render_arrows(state.get("arrows", []))
	if state.ended: return
	var warning: Dictionary = state.warning
	var flying: Array = state.projectiles
	var waves: Array = state.shockwaves
	var boss_active: Dictionary = state.get("boss_active", {})
	var arrows: Array = state.get("arrows", [])
	var has_arrow_trails := false
	for arrow in arrows:
		if not arrow.stuck and arrow.trail.size() > 1:
			has_arrow_trails = true
			break
	if not boss_active.get("glint", false):
		eye_history.clear()
		eye_sample_time = -1.0
	# A thrust warning is intentionally hidden (the red eye cue is emitted
	# through boss_active instead).  Do not begin an ImmediateMesh surface when
	# that warning is the only active effect, otherwise Godot reports an empty
	# surface on surface_end().
	var has_warning_geometry: bool = not warning.is_empty() and warning.kind != "thrust"
	var has_boss_geometry: bool = bool(boss_active.get("glint", false)) or bool(boss_active.get("charge", false))
	if not has_warning_geometry and not has_boss_geometry and not has_arrow_trails and flying.is_empty() and waves.is_empty(): return
	danger_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	if not warning.is_empty():
		rendered_warning = warning.kind
		if warning.kind == "slam": _draw_slam_warning(warning)
		elif warning.kind == "thrust": pass # Directional thrust warning intentionally hidden; red eye cue remains.
	if not boss_active.is_empty():
		# These cues are driven by the same combat clock as collision and damage.
		# They make the thrust's parry window and slam's charged blade readable.
		if boss_active.get("kind", "") == "boss_thrust" and boss_active.get("glint", false):
			_draw_boss_eye_streak(boss_active)
		if boss_active.get("kind", "") == "boss_slam" and boss_active.get("charge", false):
			_draw_slam_blade_charge(boss_active)
	for wave in waves:
		_draw_shockwave(wave)
		rendered_waves += 1
	for projectile in flying:
		_draw_projectile(projectile)
		rendered_projectiles += 1
	for arrow in arrows:
		if not arrow.stuck: _draw_arrow_trail(arrow)
	danger_mesh.surface_end()


func _build_arrow_pool() -> void:
	var packed := load("res://assets/weapons/arrow.glb") as PackedScene
	if packed == null: return
	for i in ARROW_POOL_SIZE:
		var arrow := packed.instantiate() as Node3D
		arrow.name = "FlightArrow%d" % i
		add_child(arrow)
		arrow.hide()
		arrow_pool.append(arrow)
		var meshes: Array = arrow.find_children("*", "MeshInstance3D", true, false)
		if arrow is MeshInstance3D: meshes.append(arrow)
		for instance in meshes:
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		arrow_meshes.append(meshes)


func _render_arrows(arrows: Array) -> void:
	rendered_arrows = mini(arrows.size(), arrow_pool.size())
	for i in arrow_pool.size():
		var node := arrow_pool[i]
		if i >= rendered_arrows:
			node.hide()
			continue
		var arrow: Dictionary = arrows[i]
		node.show()
		var direction: Vector3 = arrow.direction
		var up := Vector3.RIGHT if absf(direction.dot(Vector3.UP)) > .98 else Vector3.UP
		node.global_transform = Transform3D(Basis.looking_at(direction, up), arrow.at)
		for instance in arrow_meshes[i]:
			instance.transparency = 1.0 - float(arrow.fade)


func _draw_arrow_trail(arrow: Dictionary) -> void:
	var points: PackedVector3Array = arrow.trail
	var camera := get_viewport().get_camera_3d()
	var view := camera.global_basis.z if camera else Vector3.UP
	for i in range(points.size() - 1):
		var tangent := points[i] - points[i + 1]
		if tangent.length_squared() < .000001: continue
		var fade := 1.0 - float(i) / points.size()
		var side := tangent.normalized().cross(view).normalized()
		var width := (.032 if arrow.skill else .014) * fade
		var tint := Color(.52,.96,.86,.55 * fade) if arrow.skill else Color(.91,.91,.74,.38 * fade)
		_quad(points[i]-side*width, points[i]+side*width, points[i+1]+side*width*.85, points[i+1]-side*width*.85, tint)


func _draw_boss_eye_streak(active: Dictionary) -> void:
	var camera := get_viewport().get_camera_3d()
	var basis := camera.global_basis if camera else Basis.IDENTITY
	var center: Vector3 = active.position + Vector3.UP * 3.28
	if is_instance_valid(combat_source):
		var head: Node3D = combat_source.boss_visual.joints.get("Head")
		if head: center = head.to_global(Vector3(0,.12,-.235))
	var direction: Vector3 = active.direction
	var side := basis.x
	var up := basis.y
	if float(active.time) > eye_sample_time + .012:
		eye_history.insert(0, center)
		if eye_history.size() > 12: eye_history.resize(12)
		eye_sample_time = float(active.time)
	var pulse := .72 + .28 * sin(float(active.time) * 52.0)
	# A narrow red eye flare with two divergent, fading tails.
	var core := .075 * pulse
	_quad(center - side * .42 - up * core, center + side * .42 - up * core, center + side * .42 + up * core, center - side * .42 + up * core, Color(1.0,.10,.08,.85))
	_triangle(center - side * .34, center + side * .34, center + up * core * .38, Color(1.0,.88,.73,1.0))
	for branch in [-1.0, 1.0]:
		var start: Vector3 = center + side * branch * .18
		var end: Vector3 = center + side * branch * (.75 + .18 * pulse) + direction * .20 + up * (.10 * branch)
		var width := .035 * pulse
		_quad(start - up * width, start + up * width, end + up * width * .18, end - up * width * .18, Color(1.0,.16,.08,.72 * pulse))
		var end2: Vector3 = center + side * branch * 1.12 + direction * .33 + up * (.18 * branch)
		_quad(end - up * width * .7, end + up * width * .7, end2 + up * width * .06, end2 - up * width * .06, Color(1.0,.035,.025,.28 * pulse))
	for i in range(eye_history.size()-1):
		var fade := 1.0 - float(i)/12.0
		var a := eye_history[i]
		var b := eye_history[i+1]
		_quad(a-up*.055*fade,a+up*.055*fade,b+up*.055*fade,b-up*.055*fade,Color(1,.035,.02,.55*fade))


func _draw_slam_blade_charge(active: Dictionary) -> void:
	if not is_instance_valid(combat_source): return
	var blade: PackedVector3Array = combat_source.boss_visual.get_blade_points()
	var start := blade[0]
	var end := blade[1]
	var camera := get_viewport().get_camera_3d()
	var side := camera.global_basis.x if camera else Vector3.RIGHT
	var pulse := .55 + .45 * sin(float(active.time) * 18.0)
	var w := .20 + .045 * pulse
	_quad(start-side*w,start+side*w,end+side*w*.30,end-side*w*.30,Color(.70,.19,1.0,.26+.18*pulse))
	_quad(start-side*w*.18,start+side*w*.18,end+side*w*.08,end-side*w*.08,Color(1.0,.83,1.0,.90))
	for i in 9:
		var t := fmod(float(i)/9.0+float(active.time)*.65,1.0)
		var point := start.lerp(end,t)+side*sin(t*TAU+float(i))*.23
		_triangle(point-side*.025,point+side*.025,point+Vector3.UP*.08,Color(.94,.54,1.0,.8))


func _draw_slam_warning(warning: Dictionary) -> void:
	var center: Vector3 = warning.at
	center.y = 0.082
	var radius: float = warning.radius
	var p: float = warning.progress
	var pulse := 0.45 + 0.55 * p
	_band(center, radius - 0.08, radius, Color(1.0,.27,.07,.70))
	_band(center, 0.0, radius - .08, Color(.78,.13,.025,.05 + .075 * p))
	_band(center + Vector3.UP * .007, radius * p - .025, radius * p + .025, Color(1.0,.51,.18,.5 * pulse))
	for step in 16:
		var direction := Vector3(cos(TAU * step / 16.0),0,sin(TAU * step / 16.0))
		var tangent := direction.cross(Vector3.UP)
		var tip := center + direction * (radius - .14)
		_triangle(tip, tip - direction * .26 + tangent * .11, tip - direction * .26 - tangent * .11, Color(1.0,.48,.16,.68))


func _draw_thrust(warning: Dictionary) -> void:
	var polygon: PackedVector3Array = warning.polygon
	var active: bool = warning.active
	var p: float = warning.progress
	if polygon.size() >= 3:
		var center := Vector3.ZERO
		for point in polygon: center += point
		center /= polygon.size()
		for step in range(polygon.size() - 1):
			var a := polygon[step]
			var b := polygon[step + 1]
			_triangle(center,a,b,Color(1.0,.53,.08,.19 if active else .10))
			_quad(a,b,b.lerp(center,.028),a.lerp(center,.028),Color(1.0,.73,.20,.86))
	var direction: Vector3 = warning.direction
	var right := direction.cross(Vector3.UP)
	var origin: Vector3 = warning.at
	origin.y = .105
	for step in range(1, 6):
		var along: float = step * warning.reach / 6.0
		var tip := origin + direction * along
		_triangle(tip, tip - direction * .33 + right * .20, tip - direction * .33 - right * .20, Color(1.0,.77,.27,.30 + .35 * p))
	if active:
		var center: Vector3 = warning.boss_at + Vector3.UP * 1.15
		var tip := center + direction * 3.0
		_quad(center + right * .14,tip + right * .05,tip - right * .05,center - right * .14,Color(1.0,.86,.38,.80))
		for sign_value in [-1.0,1.0]:
			var offset: Vector3 = right * sign_value * .36
			_quad(center + offset,tip + offset * .65,tip + offset * .65 + Vector3.UP * .035,center + offset + Vector3.UP * .07,Color(1.0,.42,.10,.65))


func _draw_shockwave(wave: Dictionary) -> void:
	var radius: float = wave.radius
	var age: float = wave.time
	var center: Vector3 = wave.at
	center.y = .11
	var fade := 1.0 - smoothstep(.68,.9,age)
	# The leading edge uses the exact physics radius. Hot core, ember lip, lifted dust follow it.
	_band(center, radius-.48,radius,Color(1.0,.25,.045,.30*fade))
	_band(center + Vector3.UP*.014,radius-.12,radius,Color(1.0,.82,.34,.95*fade))
	_band(center + Vector3.UP*.019,radius-.055,radius,Color(1.0,.97,.70,fade))
	_band(center,radius-.75,radius-.19,Color(.56,.30,.12,.25*fade),.22)
	for step in 72:
		var angle := TAU * step / 72.0
		var direction := Vector3(cos(angle),0,sin(angle))
		var tangent := direction.cross(Vector3.UP)
		var height := (.10 + .40 * (sin(step * 3.41 + age * 23.0)*.5+.5)) * fade
		var at := center + direction * maxf(radius - .17,0.0)
		_triangle(at - tangent*.09,at + tangent*.09,at - direction*.18 + Vector3.UP*height,Color(1.0,.49,.12,.70*fade))
		if step % 3 == 0:
			var fleck := at - direction * .35 + Vector3.UP * (height + .12)
			_triangle(fleck-tangent*.035,fleck+tangent*.035,fleck+Vector3.UP*.09,Color(1.0,.89,.45,fade))
	_band(center,.0,maxf(.03,1.4*(1.0-age)),Color(1.0,.59,.13,.15*fade))


func _draw_projectile(projectile: Dictionary) -> void:
	var center: Vector3 = projectile.at
	var direction: Vector3 = projectile.direction
	var right := direction.cross(Vector3.UP)
	# Q's projectile is intentionally oversized for readability; this is a
	# presentation-only scale and does not alter the collision sphere.
	var radius: float = projectile.radius * SKILL_VFX_SCALE
	var age: float = projectile.age
	var trail: PackedVector3Array = projectile.trail
	for step in 28:
		var a := lerpf(-1.40,1.40,step/28.0)
		var b := lerpf(-1.40,1.40,(step+1)/28.0)
		var pa := right * sin(a) * radius + direction * cos(a) * radius * .42
		var pb := right * sin(b) * radius + direction * cos(b) * radius * .42
		var taper := pow(maxf(0.0,cos((a+b)*.5)),.5)
		_quad(center+pa,center+pb,center+pb-direction*.26*taper,center+pa-direction*.26*taper,Color(.12,.74,.71,.55))
		_quad(center+pa,center+pb,center+pb-direction*.072*taper,center+pa-direction*.072*taper,Color(.83,1.0,.86,.98))
		_quad(center+pa+Vector3.UP*.025,center+pb+Vector3.UP*.025,center+pb-direction*.022,center+pa-direction*.022,Color(1.0,1.0,.84,1.0))
		_quad(center+pa-direction*.15,center+pb-direction*.15,center+pb-direction*.70*taper,center+pa-direction*.70*taper,Color(.10,.61,.68,.15))
	for index in range(trail.size()-1):
		var fade := 1.0-float(index)/maxf(trail.size(),1)
		for sign_value in [-1.0,1.0]:
			var edge: Vector3 = right * radius * .86 * sign_value
			_quad(trail[index]+edge,trail[index+1]+edge*.90,trail[index+1]+edge*.90-direction*.20,trail[index]+edge-direction*.20,Color(.34,.94,.80,.52*fade))
	for step in 10:
		var seed_value := step*1.83 + age*10.0
		var at := center - direction*(.20+fmod(seed_value,1.0)*1.2) + right*sin(seed_value*3.0)*radius*.75
		at.y += sin(seed_value*2.0)*.17
		_triangle(at-right*.025,at+right*.025,at+direction*.12,Color(.80,1.0,.78,.70))

func _synthesize(kind: String) -> AudioStreamWAV:
	var rate = 22050
	var duration = .23
	if kind in ["parry", "heal", "victory"]: duration = .85
	if kind in ["slam", "death", "shockwave"]: duration = .65
	var samples = int(rate * duration)
	var bytes = PackedByteArray()
	bytes.resize(samples * 2)
	var filtered = 0.0
	for i in samples:
		var t = float(i) / rate
		var env = pow(maxf(0, 1.0 - t / duration), 2.0) * minf(t * 300.0, 1.0)
		var noise = rng.randf_range(-1, 1)
		filtered = lerpf(filtered, noise, .17)
		var wave = 0.0
		match kind:
			"bow_release": wave = filtered * exp(-t * 19) * 1.4 + sin(TAU * (380 * t - 210 * t * t)) * exp(-t * 32) * .5
			"bow_draw": wave = filtered * .25 * sin(t * 290) + sin(TAU * (110 * t + 85 * t * t)) * .09
			"arrow_hit": wave = noise * exp(-t * 75) * .85 + sin(TAU * 185 * t) * exp(-t * 32) * .35
			"weapon_switch": wave = filtered * .3 * sin(t * 80)
			"bow_land": wave = filtered * .5 + sin(TAU * 68 * t) * exp(-t * 24) * .65
			"swing", "boss_swing", "dodge", "skill": wave = filtered * sin(PI * t / duration) * 1.9
			"block", "parry", "boss_parry_ready":
				var freq = 950.0 if kind == "parry" else 670.0
				wave = sin(TAU * freq * t) * .3 + sin(TAU * freq * 1.47 * t) * .22 + noise * exp(-t * 50) * .35
			"heal", "victory": wave = (sin(TAU * 440 * t) + sin(TAU * 554.37 * t) + sin(TAU * 659.25 * t)) * .18
			"boss_telegraph", "empty": wave = sin(TAU * 180 * t) * .3
			_: wave = filtered * 1.2 + sin(TAU * (95 * t - 40 * t * t)) * .65
		var value = int(clampf(wave * env * .68, -.98, .98) * 32767.0)
		bytes.encode_s16(i * 2, value)
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = bytes
	return stream


