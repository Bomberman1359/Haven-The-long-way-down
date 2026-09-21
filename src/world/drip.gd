extends Node2D
## A leak in the ceiling. Every so often a drop gathers and falls. Water and
## flames do not get along, so a drop on your lantern costs you fuel.

const DRIP_COST := 12.0
const GRAV := 620.0

var t := 0.0
var every := 1.9
var drops: Array = []     # each: {pos, vy}
var splash_t := 0.0
var game


func _ready() -> void:
	game = get_tree().get_first_node_in_group("game")
	t = randf() * every
	every = randf_range(1.6, 2.3)
	z_index = 4


func _physics_process(delta: float) -> void:
	t += delta
	if t >= every:
		t = 0.0
		drops.append({"pos": Vector2(0, 3), "vy": 0.0})
	var p = game.player
	var keep: Array = []
	for d in drops:
		var vy: float = d["vy"] + GRAV * delta
		var pos: Vector2 = d["pos"] + Vector2(0, vy * delta)
		d["vy"] = vy
		d["pos"] = pos
		var world := global_position + pos
		var hit_player := false
		if is_instance_valid(p) and p.alive and not p.dark:
			var pp: Vector2 = p.global_position
			if absf(world.x - pp.x) < 7.0 and absf(world.y - pp.y) < 10.0:
				hit_player = true
		if hit_player:
			p.hurt(DRIP_COST, world + Vector2(0, -8))
			game.puff(world, Color(0.75, 0.80, 0.90), 10, 45.0)
			Sfx.play("flare", -18.0, 1.7)
			continue
		if game.solid_at(world) or pos.y > 900.0:
			game.puff(world - Vector2(0, 2), Color(0.45, 0.62, 0.95), 5, 35.0)
			continue
		keep.append(d)
	drops = keep
	queue_redraw()


func _draw() -> void:
	# the drop gathering on the ceiling
	var grow := clampf(t / every, 0.0, 1.0)
	var water := Color(0.50, 0.66, 1.0, 0.9)
	draw_rect(Rect2(-3, 0, 6, 1), Color(0.30, 0.40, 0.62, 0.8))
	if grow > 0.2:
		draw_circle(Vector2(0, 1.0 + grow * 2.0), 0.6 + grow * 1.2, water)
	for d in drops:
		var pos: Vector2 = d["pos"]
		draw_circle(pos, 1.6, water)
		draw_line(pos - Vector2(0, 3), pos, Color(0.50, 0.66, 1.0, 0.5), 1.0)
