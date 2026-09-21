extends Node2D
## Something that lives in the dark. While your lantern burns, wisps and
## leeches keep to the edge of the light. When it goes out, everything here
## comes for you at once.

enum { WISP, LEECH, HUSK }

const TEX := {
	WISP: preload("res://assets/sprites/wisp.png"),
	LEECH: preload("res://assets/sprites/leech.png"),
	HUSK: preload("res://assets/sprites/husk.png"),
}
const STATS := {
	WISP: {"speed": 62.0, "glow": Color(1.0, 0.24, 0.36), "gs": 0.20, "flee": true},
	LEECH: {"speed": 46.0, "glow": Color(0.30, 0.95, 0.80), "gs": 0.20, "flee": true},
	HUSK: {"speed": 26.0, "glow": Color(1.0, 0.45, 0.20), "gs": 0.24, "flee": false},
}
const HUNT_SPEED := 235.0
const LEECH_DRAIN := 3.5
const HUSK_COST := 15.0

var kind := WISP
var home := Vector2.ZERO
var vel := Vector2.ZERO
var t := 0.0
var seed_off := 0.0
var hunting := false
var draining := false
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
	glow.energy = 1.1
	queue_redraw()


func _physics_process(delta: float) -> void:
	t += delta
	body.frame = int(t * 7.0 + seed_off) % 4
	var p = game.player
	if not is_instance_valid(p):
		return
	var ppos: Vector2 = p.global_position

	if hunting:
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
	draining = false

	match kind:
		WISP:
			# drift around home; when the lantern comes near, circle just outside it
			target = home + Vector2(sin(t * 0.7 + seed_off) * 46.0, cos(t * 0.9 + seed_off) * 22.0)
			if pd < 230.0:
				var around := (global_position - ppos).normalized().rotated(0.7 * delta)
				target = ppos + around * (light_r + 16.0)
		LEECH:
			# lean into the light and drink from it
			if pd < 260.0:
				var side := (global_position - ppos).normalized()
				target = ppos + side * maxf(18.0, light_r * 0.78)
				if pd < light_r * 0.92:
					draining = true
					p.drain(LEECH_DRAIN * delta)
			else:
				target = home + Vector2(sin(t * 0.5 + seed_off) * 30.0, cos(t * 0.8) * 16.0)
		HUSK:
			# a slow patrol that does not care about your light at all
			target = home + Vector2(sin(t * 0.45 + seed_off) * 56.0, sin(t * 1.3) * 5.0)
			if p.alive and not p.dark and pd < 13.0:
				p.hurt(HUSK_COST, global_position)

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
	glow.energy = 0.6 + (0.25 if draining else 0.0)
	queue_redraw()


func _draw() -> void:
	# a leech's straw into your lantern
	if draining and is_instance_valid(game.player):
		var to: Vector2 = game.player.global_position - global_position
		var a := 0.35 + 0.25 * sin(t * 18.0)
		draw_line(Vector2.ZERO, to, Color(0.35, 1.0, 0.85, a), 1.0)
