extends CharacterBody2D
## The lantern keeper. Runs, jumps, and carries the only light on the floor.
## Fuel burns every second and the light shrinks with it. At zero the lantern
## goes out, and the game takes it from there.

signal fuel_empty

const RUN := 120.0
const ACCEL := 950.0
const AIR_ACCEL := 760.0
const FRICTION := 1300.0
const GRAVITY := 980.0
const JUMP_V := -330.0
const JUMP_CUT := -115.0
const MAX_FALL := 420.0
const COYOTE := 0.10
const BUFFER := 0.12
const LIGHT_MIN := 46.0
const LIGHT_MAX := 165.0
const MAX_FUEL := 100.0

var fuel := MAX_FUEL
var alive := true
var dark := false
var frozen := false
var invuln := 0.0
var knock := 0.0
var coyote_t := 0.0
var buffer_t := 0.0
var rising := false
var facing := 1
var light_r := LIGHT_MAX
var safe_pos := Vector2.ZERO
var safe_t := 0.0
var step_t := 0.0
var anim := 0.0
var was_floor := true
var drain_flash := 0.0
var game

@onready var body: Sprite2D = $Body
@onready var lantern: Sprite2D = $Lantern
@onready var lamp: PointLight2D = $Lamp


func _ready() -> void:
	game = get_tree().get_first_node_in_group("game")
	safe_pos = global_position


func _physics_process(delta: float) -> void:
	invuln = maxf(0.0, invuln - delta)
	knock = maxf(0.0, knock - delta)
	drain_flash = maxf(0.0, drain_flash - delta)

	if alive and not dark and not frozen:
		fuel = maxf(0.0, fuel - float(game.burn) * delta)
		if fuel <= 0.0:
			go_dark()
			fuel_empty.emit()

	# you can still run once the lantern dies. It will not help, but you can
	var control := alive and not frozen
	var dir := Input.get_axis("move_left", "move_right") if control else 0.0
	if knock > 0.0:
		dir *= 0.25

	var on_floor := is_on_floor()
	var a := ACCEL if on_floor else AIR_ACCEL
	if absf(dir) < 0.01 and on_floor:
		a = FRICTION
	velocity.x = move_toward(velocity.x, dir * RUN, a * delta)
	velocity.y = minf(MAX_FALL, velocity.y + GRAVITY * delta)

	if on_floor:
		coyote_t = COYOTE
		rising = false
	else:
		coyote_t = maxf(0.0, coyote_t - delta)

	if control and Input.is_action_just_pressed("jump"):
		buffer_t = BUFFER
	else:
		buffer_t = maxf(0.0, buffer_t - delta)

	if control and buffer_t > 0.0 and coyote_t > 0.0:
		velocity.y = JUMP_V
		buffer_t = 0.0
		coyote_t = 0.0
		rising = true
		Sfx.play_var("dash", -17.0, 0.08)

	# let go early for a short hop
	if rising and velocity.y < JUMP_CUT and not Input.is_action_pressed("jump"):
		velocity.y = JUMP_CUT
		rising = false
	if velocity.y >= 0.0:
		rising = false

	if absf(dir) > 0.01:
		facing = 1 if dir > 0.0 else -1

	move_and_slide()

	# cracked stone notices you standing on it
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var other = c.get_collider()
		if other != null and other.has_method("touch") and c.get_normal().y < -0.5:
			other.touch()

	var now_floor := is_on_floor()
	if now_floor and not was_floor and alive:
		Sfx.play_var("step", -15.0, 0.1)
	was_floor = now_floor

	if alive and not dark:
		game.check_hazards(self)
		_track_safe_ground(delta, now_floor)
	if alive and global_position.y > game.lh * game.TILE + 40.0:
		game.fell_out()

	_animate(delta, now_floor)
	_update_lantern()


func _track_safe_ground(delta: float, on_floor: bool) -> void:
	## remember somewhere solid to put you back if you fall into a pit
	if not on_floor or not game.ground_is_safe(global_position):
		safe_t = 0.0
		return
	safe_t += delta
	if safe_t > 0.25:
		safe_pos = global_position


func _animate(delta: float, on_floor: bool) -> void:
	var spd := absf(velocity.x)
	if not on_floor:
		body.frame = 1
	elif spd > 8.0:
		anim += delta * spd * 0.075
		body.frame = int(anim) % 4
		step_t -= delta
		if step_t <= 0.0:
			step_t = 0.27
			Sfx.play_var("step", -22.0, 0.18)
	else:
		anim = 0.0
		body.frame = 0
	body.flip_h = facing < 0
	var a := 1.0
	if invuln > 0.0 and fmod(invuln * 14.0, 1.0) < 0.5:
		a = 0.35
	body.modulate = Color(1, 1, 1, a)
	if drain_flash > 0.0:
		body.modulate = Color(0.55, 1.0, 0.9, a)


func _update_lantern() -> void:
	var t := Time.get_ticks_msec() * 0.001
	var ratio := fuel / MAX_FUEL
	lantern.position = Vector2(7.0 * facing, 1.0 + sin(t * 5.0) * 0.8)
	if dark:
		light_r = 0.0
		lamp.energy = move_toward(lamp.energy, 0.0, 0.08)
		lantern.modulate = Color(0.35, 0.35, 0.45)
		return
	light_r = lerpf(LIGHT_MIN, LIGHT_MAX, ratio)
	var flick := 1.0 + sin(t * 11.0) * 0.03 + sin(t * 23.7) * 0.02 + randf() * 0.02
	if ratio < 0.2:
		# a low lantern stutters
		flick *= 0.82 + 0.18 * absf(sin(t * 17.0 + sin(t * 3.1) * 4.0))
	lamp.texture_scale = (light_r / 128.0) * flick
	lamp.energy = lerpf(0.95, 1.75, ratio) * flick
	lamp.color = Color(1.0, 0.80, 0.50).lerp(Color(0.66, 0.56, 0.80), clampf(1.0 - ratio * 1.4, 0.0, 1.0))
	lantern.modulate = Color(1, 1, 1).lerp(Color(0.55, 0.52, 0.66), clampf(1.0 - ratio * 2.0, 0.0, 0.7))


func add_fuel(x: float) -> void:
	if dark:
		return
	fuel = minf(MAX_FUEL, fuel + x)


func lose_fuel(x: float) -> void:
	if dark or not alive:
		return
	fuel = maxf(0.0, fuel - x)
	if fuel <= 0.0:
		go_dark()
		fuel_empty.emit()


func hurt(cost: float, from: Vector2) -> void:
	if invuln > 0.0 or dark or not alive:
		return
	invuln = 1.0
	knock = 0.28
	var away := signf(global_position.x - from.x)
	if away == 0.0:
		away = -float(facing)
	velocity = Vector2(away * 150.0, -210.0)
	Sfx.play("hurt", -8.0)
	game.shake(6.0)
	game.hud.flash(Color(0.95, 0.25, 0.3, 0.28))
	game.puff(global_position, Color(1.0, 0.6, 0.45), 10, 80.0)
	lose_fuel(cost)


func drain(x: float) -> void:
	if dark or not alive:
		return
	drain_flash = 0.08
	lose_fuel(x)


func go_dark() -> void:
	dark = true
	fuel = 0.0


func consumed() -> void:
	alive = false
	velocity = Vector2.ZERO
	body.visible = false
	lantern.visible = false
