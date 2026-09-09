extends CanvasLayer

signal pause_toggled(paused: bool)
signal retry_requested
signal quit_requested
signal sound_toggled(enabled: bool)
signal shake_toggled(enabled: bool)
signal focus_toggled(enabled: bool)

const GOLD = Color("d9c389")
const WHITE = Color("f0eedb")
const INK = Color("17272b")
var root: Control
var hp: ProgressBar
var stamina: ProgressBar
var boss_hp: ProgressBar
var boss_trail: ProgressBar
var hp_text: Label
var status: Label
var skill_text: Label
var flask_text: Label
var lock_text: Label
var menu: Control
var result: Control
var result_title: Label
var result_detail: Label
var paused = false
var finished = false
var notice_time = 0.0
var notice: Label
var resume_button: Button

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Segoe UI"])
	var theme = Theme.new()
	theme.default_font = font
	theme.default_font_size = 20
	root.theme = theme
	var vignette = ColorRect.new()
	root.add_child(vignette)
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader = Shader.new()
	shader.code = "shader_type canvas_item; void fragment(){ float edge=pow(length((UV-vec2(.5))*vec2(1.0,.85)),2.8); COLOR=vec4(.025,.055,.06,edge*1.3); }"
	var material = ShaderMaterial.new()
	material.shader = shader
	vignette.material = material
	_build_hud()
	_build_menu()
	_build_result()

func _label(text: String, size: int, color: Color = WHITE) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.025, 0.055, 0.06, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _box(color: Color, border: Color = Color.TRANSPARENT, width: int = 0) -> StyleBoxFlat:
	var box = StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(2)
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 12
	box.content_margin_bottom = 12
	return box

func _bar(color: Color, height: float) -> ProgressBar:
	var bar = ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size.y = height
	var background = _box(Color(0.04, 0.07, 0.07, 0.88), Color("a89d78"), 1)
	var fill = _box(color)
	for style in [background, fill]:
		style.content_margin_left = 0
		style.content_margin_right = 0
		style.content_margin_top = 0
		style.content_margin_bottom = 0
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bar

func _build_hud() -> void:
	var vitals = VBoxContainer.new()
	root.add_child(vitals)
	vitals.position = Vector2(48, 35)
	vitals.custom_minimum_size.x = 340
	vitals.add_theme_constant_override("separation", 7)
	var title_row = HBoxContainer.new()
	vitals.add_child(title_row)
	title_row.add_child(_label("荆棘誓约", 23, GOLD))
	hp_text = _label("130 / 130", 15)
	hp_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	title_row.add_child(hp_text)
	hp = _bar(Color("b85254"), 15)
	vitals.add_child(hp)
	stamina = _bar(Color("94b98d"), 9)
	vitals.add_child(stamina)
	status = _label("", 14, GOLD)
	vitals.add_child(status)
	var region = VBoxContainer.new()
	root.add_child(region)
	region.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	region.offset_left = -380
	region.offset_right = -48
	region.offset_top = 35
	region.offset_bottom = 145
	var name_label = _label("BRIAR WARDEN", 23, GOLD)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	region.add_child(name_label)
	var subtitle = _label("暮林  /  失落圣庭", 15)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	region.add_child(subtitle)
	lock_text = _label("", 14, GOLD)
	lock_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	region.add_child(lock_text)
	var boss_panel = VBoxContainer.new()
	root.add_child(boss_panel)
	boss_panel.anchor_left = 0.25
	boss_panel.anchor_right = 0.75
	boss_panel.anchor_top = 1.0
	boss_panel.anchor_bottom = 1.0
	boss_panel.offset_top = -102
	boss_panel.offset_bottom = -38
	boss_panel.add_theme_constant_override("separation", 9)
	var boss_name = _label("维尔格，荆冠守誓者", 23)
	boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_panel.add_child(boss_name)
	var stack = Control.new()
	stack.custom_minimum_size.y = 16
	boss_panel.add_child(stack)
	boss_trail = _bar(Color("d5aa73"), 16)
	stack.add_child(boss_trail)
	boss_trail.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	boss_hp = _bar(Color("a74851"), 16)
	stack.add_child(boss_hp)
	boss_hp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	boss_hp.add_theme_stylebox_override("background", StyleBoxEmpty.new())
	var abilities = VBoxContainer.new()
	root.add_child(abilities)
	abilities.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	abilities.offset_left = 48
	abilities.offset_right = 260
	abilities.offset_top = -124
	abilities.offset_bottom = -42
	abilities.add_theme_constant_override("separation", 10)
	skill_text = _label("霜誓斩  ·  就绪", 18, Color("b6e0d8"))
	abilities.add_child(skill_text)
	flask_text = _label("圣露  3", 18, GOLD)
	abilities.add_child(flask_text)
	notice = _label("", 28, GOLD)
	root.add_child(notice)
	notice.anchor_left = 0.2
	notice.anchor_right = 0.8
	notice.anchor_top = 0.21
	notice.anchor_bottom = 0.28
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _overlay() -> Control:
	var overlay = Control.new()
	root.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var tint = ColorRect.new()
	overlay.add_child(tint)
	tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tint.color = Color(0.025, 0.055, 0.055, 0.82)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.hide()
	return overlay

func _center_column(parent: Control, width: float, height: float) -> VBoxContainer:
	var col = VBoxContainer.new()
	parent.add_child(col)
	col.anchor_left = 0.5
	col.anchor_right = 0.5
	col.anchor_top = 0.5
	col.anchor_bottom = 0.5
	col.offset_left = -width / 2.0
	col.offset_right = width / 2.0
	col.offset_top = -height / 2.0
	col.offset_bottom = height / 2.0
	col.add_theme_constant_override("separation", 18)
	return col

func _button(parent: Control, text: String, callback: Callable) -> Button:
	var button = Button.new()
	button.text = text
	button.custom_minimum_size.y = 48
	button.add_theme_stylebox_override("normal", _box(Color(0.1, 0.16, 0.17, 0.9), Color("6d796a"), 1))
	button.add_theme_stylebox_override("hover", _box(Color("304944"), GOLD, 1))
	button.add_theme_stylebox_override("focus", _box(Color(0.2, 0.26, 0.22, 0.3), GOLD, 2))
	button.add_theme_stylebox_override("pressed", _box(Color("1c302c"), GOLD, 2))
	parent.add_child(button)
	button.pressed.connect(callback)
	return button

func _build_menu() -> void:
	menu = _overlay()
	var col = _center_column(menu, 360, 480)
	var title = _label("片刻安宁", 36, GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	resume_button = _button(col, "继续战斗", func(): toggle_pause())
	_button(col, "重新挑战", _retry)
	var sound = CheckButton.new()
	sound.text = "声音"
	sound.button_pressed = true
	col.add_child(sound)
	sound.toggled.connect(func(on: bool): sound_toggled.emit(on))
	var shake = CheckButton.new()
	shake.text = "镜头震动"
	shake.button_pressed = true
	col.add_child(shake)
	shake.toggled.connect(func(on: bool): shake_toggled.emit(on))
	var focus = CheckButton.new()
	focus.text = "远景柔化"
	focus.button_pressed = true
	col.add_child(focus)
	focus.toggled.connect(func(on: bool): focus_toggled.emit(on))
	_button(col, "离开圣庭", func(): quit_requested.emit())

func _build_result() -> void:
	result = _overlay()
	var col = _center_column(result, 460, 265)
	result_title = _label("", 46, GOLD)
	result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(result_title)
	result_detail = _label("", 20)
	result_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(result_detail)
	_button(col, "再次挑战", _retry)

func apply_stats(data: Dictionary) -> void:
	if not is_instance_valid(hp): return
	hp.max_value = float(data.get("max_hp", 130))
	hp.value = float(data.get("hp", 130))
	hp_text.text = "%d / %d" % [hp.value, hp.max_value]
	stamina.max_value = float(data.get("max_stamina", 100))
	stamina.value = float(data.get("stamina", 100))
	boss_hp.max_value = float(data.get("boss_max_hp", 1100))
	boss_trail.max_value = boss_hp.max_value
	var new_hp = float(data.get("boss_hp", 1100))
	if new_hp > boss_hp.value: boss_trail.value = new_hp
	boss_hp.value = new_hp
	var cd = float(data.get("skill_cd", 0))
	skill_text.text = "霜誓斩  ·  %.1f" % cd if cd > 0 else "霜誓斩  ·  就绪"
	flask_text.text = "圣露  %d" % int(data.get("heals", 3))
	lock_text.text = "锁定目标" if bool(data.get("locked", false)) else ""
	var state = str(data.get("player_state", "idle"))
	var names = {"block": "防御", "parry": "盾反", "stagger": "失衡", "heal": "饮露", "skill": "霜誓斩"}
	status.text = names.get(state, "")

func announce(text: String) -> void:
	notice.text = text
	notice.modulate.a = 1.0
	notice_time = 1.4

func toggle_pause() -> void:
	if finished: return
	paused = not paused
	menu.visible = paused
	pause_toggled.emit(paused)
	if paused: resume_button.grab_focus()

func show_result(victory: bool) -> void:
	finished = true
	menu.hide()
	result_title.text = "誓约已偿" if victory else "誓火已熄"
	result_title.add_theme_color_override("font_color", GOLD if victory else Color("ca7272"))
	result_detail.text = "荆冠守誓者已被击败" if victory else "圣庭仍在等待"
	await get_tree().create_timer(1.7, true, false, true).timeout
	if not finished: return
	result.show()
	var buttons = result.find_children("*", "Button", true, false)
	if not buttons.is_empty(): buttons[0].grab_focus()

func _retry() -> void:
	finished = false
	paused = false
	menu.hide()
	result.hide()
	pause_toggled.emit(false)
	retry_requested.emit()

func _process(delta: float) -> void:
	if boss_trail:
		boss_trail.value = move_toward(boss_trail.value, boss_hp.value, delta * 100.0)
	if notice_time > 0:
		notice_time -= delta
		notice.modulate.a = minf(notice_time * 3.0, 1.0)
