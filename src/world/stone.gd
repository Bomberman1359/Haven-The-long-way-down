extends Node2D
## A loose stone in the ceiling. Walk under it and it shakes, then drops.
## It grows back a few seconds later, so the same spot can get you twice.

enum { HANG, SHAKE, FALL, GONE }

const COST := 20.0
const SHAKE_TIME := 0.35
const REGROW := 4.5
const GRAV := 900.0

var state := HANG
var t := 0.0
var vy := 0.0
var home := Vector2.ZERO
var game


func _ready() -> void:
	game = get_tree().get_first_node_in_group("game")
	home = position
	z_index = 4


func _physics_process(delta: float) -> void:
	var p = game.player
	match state:
		HANG:
			if is_instance_valid(p) and p.alive and not p.dark:
				var pp: Vector2 = p.global_position
				if absf(pp.x - global_position.x) < 14.0 and pp.y > global_position.y \
						and pp.y - global_position.y < 230.0 and _clear_below(pp.y):
					state = SHAKE
					t = 0.0
					Sfx.play_var("step", -10.0, 0.3)
		SHAKE:
			t += delta
			if t >= SHAKE_TIME:
				state = FALL
				vy = 0.0
		FALL:
			vy = minf(520.0, vy + GRAV * delta)
			position.y += vy * delta
			if is_instance_valid(p) and p.alive and not p.dark:
				var pp2: Vector2 = p.global_position
				if absf(pp2.x - global_position.x) < 10.0 and absf(pp2.y - global_position.y) < 13.0:
					p.hurt(COST, global_position + Vector2(0, -10))
					_shatter()
					return
			if game.solid_at(global_position + Vector2(0, 6)) or position.y > home.y + 1200.0:
				_shatter()
		GONE:
			t += delta
			if t >= REGROW:
				state = HANG
				position = home
	queue_redraw()


func _clear_below(to_y: float) -> bool:
	## only drops when nothing solid sits between it and you
	var y := global_position.y + 10.0
	while y < to_y - 8.0:
		if game.solid_at(Vector2(global_position.x, y)):
			return false
		y += 8.0
	return true


func _shatter() -> void:
	state = GONE
	t = 0.0
	game.puff(global_position, Color(0.62, 0.58, 0.70), 9, 70.0)
	Sfx.play_var("step", -6.0, 0.25)


func _draw() -> void:
	if state == GONE:
		if t > REGROW - 0.8:
			var a := clampf((t - (REGROW - 0.8)) / 0.8, 0.0, 1.0) * 0.6
			_rock(Vector2.ZERO, a)
		return
	var off := Vector2.ZERO
	if state == SHAKE:
		off = Vector2(randf_range(-1.2, 1.2), randf_range(-0.5, 0.5))
	_rock(off, 1.0)


func _rock(off: Vector2, a: float) -> void:
	var pts := PackedVector2Array([
		off + Vector2(-6, 0), off + Vector2(6, 0), off + Vector2(7, 5),
		off + Vector2(3, 10), off + Vector2(-2, 11), off + Vector2(-7, 6)])
	draw_colored_polygon(pts, Color(0.36, 0.34, 0.45, a))
	draw_polyline(PackedVector2Array([off + Vector2(-6, 0), off + Vector2(6, 0)]), Color(0.70, 0.68, 0.80, a), 1.0)
	draw_line(off + Vector2(-2, 3), off + Vector2(1, 7), Color(0.14, 0.12, 0.20, a), 1.0)
	if state == HANG:
		# a little dust hints that it is loose
		var k := fmod(Time.get_ticks_msec() * 0.001 + home.x * 0.01, 2.2)
		if k < 0.5:
			draw_rect(Rect2(off + Vector2(randf_range(-4, 4), 12 + k * 20.0), Vector2(1, 1)), Color(0.7, 0.68, 0.8, 0.6 * a))
