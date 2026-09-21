extends Node2D
## The way down. It stays sealed and dim until the beacon on this floor is lit.

const REACH_X := 12.0

var open := false
var t := 0.0
var game

@onready var body: Sprite2D = $Body
@onready var glow: PointLight2D = $Glow


func _ready() -> void:
	game = get_tree().get_first_node_in_group("game")
	t = randf() * TAU
	glow.enabled = false
	body.frame = 3
	body.modulate = Color(0.45, 0.45, 0.55)


func unseal() -> void:
	open = true
	glow.enabled = true
	body.modulate = Color(1, 1, 1)
	queue_redraw()


func _process(delta: float) -> void:
	t += delta * 3.0
	if open:
		body.frame = int(t) % 4
		glow.energy = 0.95 + sin(t * 0.8) * 0.2
	queue_redraw()
	var p = game.player
	if not open or not is_instance_valid(p) or not p.alive or p.dark:
		return
	var d: Vector2 = p.global_position - (global_position + Vector2(0, -8))
	if absf(d.x) < REACH_X and absf(d.y) < 12.0:
		game.descend()


func _draw() -> void:
	# a stone arch around the stairwell so it reads as a doorway in the wall
	var stone := Color(0.42, 0.40, 0.52)
	var hi := Color(0.66, 0.64, 0.78)
	var low := Color(0.10, 0.09, 0.15)
	draw_rect(Rect2(-20, -38, 4, 38), stone)
	draw_rect(Rect2(16, -38, 4, 38), stone)
	draw_rect(Rect2(-20, -42, 40, 5), stone)
	draw_rect(Rect2(-20, -42, 40, 1), hi)
	draw_rect(Rect2(-20, -38, 1, 38), hi)
	draw_rect(Rect2(19, -38, 1, 38), low)
	draw_rect(Rect2(-6, -45, 12, 4), stone)
	draw_rect(Rect2(-6, -45, 12, 1), hi)
	if not open:
		# bars across a sealed door
		for i in 4:
			draw_rect(Rect2(-13 + i * 8, -36, 2, 36), Color(0.30, 0.29, 0.38))
			draw_rect(Rect2(-13 + i * 8, -36, 1, 36), Color(0.52, 0.50, 0.62))
		draw_rect(Rect2(-16, -24, 32, 2), Color(0.30, 0.29, 0.38))
