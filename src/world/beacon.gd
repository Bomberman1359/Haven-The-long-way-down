extends Node2D
## The beacon at the heart of each floor. Stand beside it and hold E to light
## it. A lit beacon fills your lantern, keeps a patch of the floor warm, marks
## where you come back if the lantern goes out, and opens the stairway down.

const HOLD_TIME := 1.1
const LIGHT_R := 170.0
const REACH_X := 26.0
const REGEN_R := 64.0
const REGEN_RATE := 14.0

var lit := false
var charge := 0.0
var flicker := 0.0
var near := false
var game

@onready var body: Sprite2D = $Body
@onready var lamp: PointLight2D = $Light
var embers: CPUParticles2D


func _ready() -> void:
	game = get_tree().get_first_node_in_group("game")
	flicker = randf() * TAU
	lamp.enabled = false
	body.frame = 0

	embers = CPUParticles2D.new()
	embers.texture = preload("res://assets/sprites/spark.png")
	embers.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	embers.position = Vector2(0, -38)
	embers.amount = 24
	embers.lifetime = 1.8
	embers.spread = 24.0
	embers.direction = Vector2(0, -1)
	embers.gravity = Vector2(0, -14)
	embers.initial_velocity_min = 12.0
	embers.initial_velocity_max = 30.0
	embers.scale_amount_min = 0.2
	embers.scale_amount_max = 0.55
	embers.color = Color(1.0, 0.74, 0.36, 0.9)
	embers.emitting = false
	add_child(embers)


func light_radius() -> float:
	if lit:
		return LIGHT_R
	return LIGHT_R * 0.5 * charge_frac()


func charge_frac() -> float:
	return clampf(charge / HOLD_TIME, 0.0, 1.0)


func _process(delta: float) -> void:
	var p = game.player
	near = is_instance_valid(p) and p.alive and not p.dark \
		and absf(p.global_position.x - global_position.x) < REACH_X \
		and absf(p.global_position.y - (global_position.y - 8.0)) < 28.0

	if lit:
		flicker += delta
		body.frame = 1 + int(flicker * 10.0) % 4
		lamp.energy = 1.35 + sin(flicker * 7.4) * 0.12 + sin(flicker * 13.3) * 0.05
		if is_instance_valid(p) and p.alive and p.global_position.distance_to(global_position + Vector2(0, -12)) < REGEN_R:
			p.add_fuel(REGEN_RATE * delta)
		queue_redraw()
		return

	if near and Input.is_action_pressed("interact") and game.state == game.PLAY:
		if charge <= 0.01:
			Sfx.play("vigil", -12.0, 1.3)
		charge += delta
		if int(charge * 6.0) != int((charge - delta) * 6.0):
			Sfx.play_var("blip", -22.0, 0.2)
		if charge >= HOLD_TIME:
			ignite()
	else:
		charge = maxf(0.0, charge - delta * 2.0)

	if charge > 0.01:
		flicker += delta
		body.frame = 1 + int(flicker * 6.0) % 4
		lamp.enabled = true
		lamp.energy = lerpf(0.2, 0.9, charge_frac())
		lamp.texture_scale = maxf(0.4, light_radius() / 128.0)
		embers.emitting = charge_frac() > 0.4
	else:
		lamp.enabled = false
		body.frame = 0
		embers.emitting = false
	queue_redraw()


func ignite() -> void:
	lit = true
	charge = HOLD_TIME
	lamp.enabled = true
	lamp.texture_scale = LIGHT_R / 128.0
	body.frame = 1
	embers.emitting = true
	embers.amount = 32
	queue_redraw()
	Sfx.play("ignite", -4.0)
	game.on_beacon_lit(self)


func ignite_quiet() -> void:
	## already burning: used when you come back to it after losing the lantern
	lit = true
	charge = HOLD_TIME
	lamp.enabled = true
	lamp.texture_scale = LIGHT_R / 128.0
	body.frame = 1
	embers.emitting = true
	embers.amount = 32


func _draw() -> void:
	if lit:
		return
	var t := Time.get_ticks_msec() * 0.001
	if near:
		# a small prompt above the brazier, and the hold meter as a ring
		var a := 0.75 + 0.25 * sin(t * 5.0)
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(-20, -58), "HOLD  E", HORIZONTAL_ALIGNMENT_CENTER, 40, 8, Color(1.0, 0.88, 0.62, a))
	if charge > 0.01:
		var c := Vector2(0, -34)
		draw_arc(c, 13.0, -PI / 2.0, -PI / 2.0 + TAU * charge_frac(), 28, Color(1.0, 0.82, 0.5, 0.9), 2.0)
