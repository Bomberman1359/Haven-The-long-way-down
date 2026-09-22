extends Node2D
## Something that lives in the dark. While your lantern burns, most of these
## keep their distance or keep to their own business. When it goes out,
## everything on the floor comes for you at once.
##
##   wisp     circles just outside your light
##   leech    leans into the light and drinks your fuel
##   husk     a slow patrol that ignores the light; bumping it costs fuel
##   stalker  only moves while you are not facing it
##   brute    hangs still until you share its floor, then charges

enum { WISP, LEECH, HUSK, STALKER, BRUTE }

const TEX := {
	WISP: preload("res://assets/sprites/wisp.png"),
	LEECH: preload("res://assets/sprites/leech.png"),
	HUSK: preload("res://assets/sprites/husk.png"),
	STALKER: preload("res://assets/sprites/stalker.png"),
	BRUTE: preload("res://assets/sprites/brute.png"),
}
const STATS := {
	WISP: {"speed": 62.0, "glow": Color(1.0, 0.24, 0.36), "gs": 0.20, "flee": true},
	LEECH: {"speed": 48.0, "glow": Color(0.30, 0.95, 0.80), "gs": 0.20, "flee": true},
	HUSK: {"speed": 26.0, "glow": Color(1.0, 0.45, 0.20), "gs": 0.24, "flee": false},
	STALKER: {"speed": 74.0, "glow": Color(0.62, 0.72, 1.0), "gs": 0.20, "flee": false},
	BRUTE: {"speed": 44.0, "glow": Color(1.0, 0.36, 0.16), "gs": 0.30, "flee": false},
}
const HUNT_SPEED := 235.0
const HUSK_COST := 18.0
const STALKER_COST := 20.0
const BRUTE_COST := 25.0

# brute states
enum { HOVER, WIND, CHARGE, BACK }
const WIND_TIME := 0.55
const CHARGE_SPEED := 265.0
const CHARGE_REACH := 210.0

var kind := WISP
var home := Vector2.ZERO
var vel := Vector2.ZERO
var t := 0.0
var seed_off := 0.0
var hunting := false
var draining := false
var frozen := false
var stun := 0.0
var bstate := HOVER
var bt := 0.0
var charge_dir := 1.0
var charge_from := Vector2.ZERO
var game

@onready var body: Sprite2D = $Body
@onready var glow: PointLight2D = $Glow


func _ready() -> void:
	game = get_tree().get_first_node_in_group("game")
	seed_off = randf() * TAU
	t = randf() * 10.0
	body.texture = TEX[kind]
	body.hframes = 4
	glow.color = STATS[kind]["glow"]
	glow.texture_scale = STATS[kind]["gs"]
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.5)


func hunt() -> void:
	hunting = true
	draining = false
	frozen = false
	glow.energy = 1.1
	body.modulate = Color(1, 1, 1)
	queue_redraw()


func leech_drain() -> float:
	## leeches get thirstier the deeper you go
	return 3.5 + 0.4 * float(game.depth - 1)


func _physics_process(delta: float) -> void:
	t += delta
	stun = maxf(0.0, stun - delta)
	var p = game.player
	if not is_instance_valid(p):
		return
	var ppos: Vector2 = p.global_position

	if hunting:
		body.frame = int(t * 9.0 + seed_off) % 4
		var to := ppos - global_position
		vel = vel.lerp(to.normalized() * HUNT_SPEED, 1.0 - pow(0.015, delta))
		global_position += vel * delta
		body.flip_h = vel.x < 0.0
		if p.alive and to.length() < 10.0:
			game.caught(self)
		return

	var speed: float = STATS[kind]["speed"]
	var pd := global_position.distance_to(ppos)
	var light_r: float = p.light_r
	var target := home
	var free_move := true
	draining = false
	frozen = false

	match kind:
		WISP:
			# drift around home; when the lantern comes near, circle just outside it
			target = home + Vector2(sin(t * 0.7 + seed_off) * 46.0, cos(t * 0.9 + seed_off) * 22.0)
			if pd < 230.0:
				var around := (global_position - ppos).normalized().rotated(0.7 * delta)
				target = ppos + around * (light_r + 16.0)
		LEECH:
			# lean into the light and drink from it
			if pd < 270.0:
				var side := (global_position - ppos).normalized()
				target = ppos + side * maxf(18.0, light_r * 0.74)
				if pd < light_r * 0.92:
					draining = true
					p.drain(leech_drain() * delta)
			else:
				target = home + Vector2(sin(t * 0.5 + seed_off) * 30.0, cos(t * 0.8) * 16.0)
		HUSK:
			# a slow patrol that does not care about your light at all
			target = home + Vector2(sin(t * 0.45 + seed_off) * 56.0, sin(t * 1.3) * 5.0)
			if p.alive and not p.dark and pd < 13.0:
				p.hurt(HUSK_COST, global_position)
		STALKER:
			_stalker(delta, p, ppos, pd, light_r)
			free_move = false
		BRUTE:
			_brute(delta, p, ppos, pd)
			free_move = false

	if free_move:
		var desired := (target - global_position)
		desired = desired.limit_length(speed) if desired.length() > 4.0 else desired * 4.0
		if STATS[kind]["flee"]:
			for s in game.light_sources:
				var sp: Vector2 = s["pos"]
				var sr: float = s["r"]
				var d := global_position.distance_to(sp)
				if d < sr and d > 0.5:
					var push := 1.0 - d / sr
					desired += (global_position - sp) / d * speed * 2.2 * push
		vel = vel.lerp(desired, 1.0 - pow(0.04, delta))
		global_position += vel * delta
		body.flip_h = vel.x < 0.0
		body.frame = int(t * 7.0 + seed_off) % 4

	glow.energy = 0.6 + (0.25 if draining else 0.0)
	queue_redraw()


func _stalker(delta: float, p, ppos: Vector2, pd: float, light_r: float) -> void:
	## It moves only while your back is turned. Face it and it locks in place.
	var ahead := signf(global_position.x - ppos.x) == float(p.facing) or absf(global_position.x - ppos.x) < 4.0
	var seen: bool = p.alive and not p.dark and ahead and pd < light_r * 1.6 + 30.0
	if seen or stun > 0.0:
		frozen = seen
		vel = vel.lerp(Vector2.ZERO, 1.0 - pow(0.0001, delta))
		body.modulate = Color(1.7, 1.8, 2.0) if seen else Color(1, 1, 1, 0.6)
		glow.energy = 1.1
	else:
		body.modulate = Color(1, 1, 1)
		var chase := (ppos - global_position).normalized()
		var spd: float = STATS[STALKER]["speed"] if pd < 330.0 else 20.0
		vel = vel.lerp(chase * spd, 1.0 - pow(0.02, delta))
		body.frame = int(t * 8.0 + seed_off) % 4
	global_position += vel * delta
	body.flip_h = ppos.x < global_position.x
	if p.alive and not p.dark and pd < 12.0 and stun <= 0.0:
		p.hurt(STALKER_COST, global_position)
		stun = 1.3
		global_position += (global_position - ppos).normalized() * 60.0


func _brute(delta: float, p, ppos: Vector2, pd: float) -> void:
	## Hangs in the air until you come level with it, winds up, then charges
	## straight along the floor. Jump it.
	bt += delta
	match bstate:
		HOVER:
			var bob := Vector2(0, sin(t * 1.6 + seed_off) * 3.0)
			global_position = global_position.lerp(home + bob, 1.0 - pow(0.05, delta))
			body.frame = int(t * 5.0) % 4
			if bt > 1.0 and p.alive and not p.dark and absf(ppos.x - global_position.x) < 150.0 \
					and absf(ppos.y - global_position.y) < 26.0:
				bstate = WIND
				bt = 0.0
				charge_dir = signf(ppos.x - global_position.x)
				if charge_dir == 0.0:
					charge_dir = 1.0
				Sfx.play_var("shadow", -9.0, 0.1)
		WIND:
			body.frame = int(t * 14.0) % 4
			body.position = Vector2(randf_range(-1.5, 1.5), randf_range(-1.0, 1.0))
			glow.energy = lerpf(0.6, 1.6, bt / WIND_TIME)
			if bt >= WIND_TIME:
				bstate = CHARGE
				bt = 0.0
				charge_from = global_position
				body.position = Vector2.ZERO
				Sfx.play_var("dash", -8.0, 0.1)
		CHARGE:
			body.frame = int(t * 16.0) % 4
			global_position.x += charge_dir * CHARGE_SPEED * delta
			if absf(global_position.x - charge_from.x) > CHARGE_REACH or bt > 1.2:
				bstate = BACK
				bt = 0.0
		BACK:
			body.frame = int(t * 5.0) % 4
			global_position = global_position.move_toward(home, STATS[BRUTE]["speed"] * delta)
			if global_position.distance_to(home) < 2.0:
				bstate = HOVER
				bt = 0.0
	body.flip_h = charge_dir < 0.0 if bstate != HOVER else ppos.x < global_position.x
	if bstate != WIND:
		glow.energy = 0.7
	if p.alive and not p.dark and pd < 16.0:
		p.hurt(BRUTE_COST, global_position)


func _draw() -> void:
	# a leech's straw into your lantern
	if draining and is_instance_valid(game.player):
		var to: Vector2 = game.player.global_position - global_position
		var a := 0.35 + 0.25 * sin(t * 18.0)
		draw_line(Vector2.ZERO, to, Color(0.35, 1.0, 0.85, a), 1.0)
	# a brute winding up shows which way it is about to go
	if kind == BRUTE and bstate == WIND:
		var a2 := clampf(bt / WIND_TIME, 0.0, 1.0)
		for i in 3:
			var x := charge_dir * (18.0 + i * 7.0 + a2 * 6.0)
			draw_line(Vector2(x, -4), Vector2(x + charge_dir * 4.0, 0), Color(1.0, 0.5, 0.25, a2), 1.0)
			draw_line(Vector2(x + charge_dir * 4.0, 0), Vector2(x, 4), Color(1.0, 0.5, 0.25, a2), 1.0)
