extends StaticBody2D
## Cracked stone. It holds for a moment after you land on it, then drops out
## of the floor and grows back a few seconds later.

enum { IDLE, SHAKING, GONE }

const HOLD := 0.45
const REGROW := 3.2
const FloorTex: Texture2D = preload("res://assets/sprites/floor.png")

var state := IDLE
var t := 0.0
var cell := Vector2i.ZERO
var drop := 0.0
var shape: CollisionShape2D
var game


func _ready() -> void:
	game = get_tree().get_first_node_in_group("game")
	collision_layer = 1
	collision_mask = 0
	shape = CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(16, 16)
	shape.shape = r
	shape.position = Vector2(8, 8)
	add_child(shape)
	z_index = 1


func touch() -> void:
	if state == IDLE:
		state = SHAKING
		t = 0.0
		Sfx.play_var("step", -12.0, 0.3)


func _physics_process(delta: float) -> void:
	match state:
		SHAKING:
			t += delta
			# deeper floors are built from worse stone
			var hold_for := HOLD if game.depth <= 3 else HOLD * 0.78
			if t >= hold_for:
				state = GONE
				t = 0.0
				drop = 0.0
				shape.set_deferred("disabled", true)
				game.puff(global_position + Vector2(8, 10), Color(0.55, 0.52, 0.62), 6, 40.0)
		GONE:
			t += delta
			drop += delta
			if t >= REGROW and not _player_inside():
				state = IDLE
				t = 0.0
				shape.set_deferred("disabled", false)
	queue_redraw()


func _player_inside() -> bool:
	var p = game.player
	if not is_instance_valid(p):
		return false
	var r := Rect2(global_position - Vector2(6, 9), Vector2(28, 34))
	return r.has_point(p.global_position)


func _draw() -> void:
	var off := Vector2.ZERO
	var a := 1.0
	match state:
		SHAKING:
			off = Vector2(randf_range(-1.0, 1.0), randf_range(-0.6, 0.6))
		GONE:
			off = Vector2(0, drop * drop * 260.0)
			a = clampf(1.0 - drop * 2.2, 0.0, 1.0)
			if t > REGROW - 0.5:
				# growing back: a faint outline first
				off = Vector2.ZERO
				a = clampf((t - (REGROW - 0.5)) * 1.2, 0.0, 0.6)
	if a <= 0.0:
		return
	var src := Rect2(((cell.x + cell.y) % 4) * 32 + 8, 8, 16, 16)
	draw_texture_rect_region(FloorTex, Rect2(off, Vector2(16, 16)), src, Color(0.98, 0.84, 0.72, a))
	draw_rect(Rect2(off, Vector2(16, 2)), Color(0.80, 0.70, 0.62, a))
	draw_rect(Rect2(off + Vector2(0, 14), Vector2(16, 2)), Color(0.08, 0.06, 0.10, a))
	# the cracks
	var crack := Color(0.10, 0.07, 0.10, a)
	draw_line(off + Vector2(3, 2), off + Vector2(7, 8), crack, 1.0)
	draw_line(off + Vector2(7, 8), off + Vector2(5, 14), crack, 1.0)
	draw_line(off + Vector2(7, 8), off + Vector2(13, 11), crack, 1.0)
	draw_line(off + Vector2(12, 2), off + Vector2(10, 5), crack, 1.0)
