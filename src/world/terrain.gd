extends Node2D
## Draws a whole floor in one retained draw list: the back wall, the stone,
## the thin ledges and the spikes. It takes 2D lighting like any CanvasItem,
## so the lantern is what makes it readable.

const FloorTex: Texture2D = preload("res://assets/sprites/floor.png")
const WallTex: Texture2D = preload("res://assets/sprites/wall.png")

const EDGE_TOP := Color(0.64, 0.62, 0.76)
const EDGE_SIDE := Color(0.40, 0.39, 0.52)
const EDGE_LOW := Color(0.06, 0.05, 0.10)
const MOSS := Color(0.34, 0.52, 0.36)
const LEDGE := Color(0.47, 0.44, 0.55)
const LEDGE_HI := Color(0.72, 0.70, 0.82)
const SPIKE := Color(0.78, 0.77, 0.86)
const SPIKE_DARK := Color(0.16, 0.15, 0.22)

var rows: PackedStringArray
var w := 0
var h := 0
var tile := 16


func setup(r: PackedStringArray, ts: int) -> void:
	rows = r
	h = rows.size()
	w = rows[0].length() if h > 0 else 0
	tile = ts
	queue_redraw()


func at(x: int, y: int) -> String:
	if x < 0 or x >= w or y < 0:
		return "#"
	if y >= h:
		return "."
	return rows[y][x]


func is_stone(x: int, y: int) -> bool:
	return at(x, y) == "#"


func _hash(x: int, y: int) -> int:
	return absi((x * 73856093) ^ (y * 19349663))


func _draw() -> void:
	if w == 0:
		return
	var t := float(tile)

	# the back wall: big 32 px slabs, dim and cold, so the stone in front reads first
	for by in range(0, h, 2):
		for bx in range(0, w, 2):
			var v: int = _hash(bx, by) % 4
			draw_texture_rect_region(FloorTex, Rect2(bx * t, by * t, t * 2.0, t * 2.0),
				Rect2(v * 32, 0, 32, 32), Color(0.34, 0.33, 0.46))
	# old pillars holding up the ceiling, every so often
	var px := 6 + _hash(w, h) % 5
	while px < w - 2:
		_pillar(px, t)
		px += 13 + _hash(px, 3) % 9

	for y in h:
		for x in w:
			var c := at(x, y)
			var p := Vector2(x * t, y * t)
			match c:
				"#":
					_stone(x, y, p, t)
				"-":
					_ledge(x, y, p, t)
				"^":
					_spikes(p, t, false)
				"v":
					_spikes(p, t, true)
				"m", "~":
					_rail_h(p, t)
				"n", ":":
					_rail_v(p, t)


func _pillar(px: int, t: float) -> void:
	var x0 := px * t
	var body := Color(0.23, 0.22, 0.31)
	var hi := Color(0.33, 0.32, 0.44)
	var low := Color(0.12, 0.11, 0.17)
	draw_rect(Rect2(x0, 0, t * 1.5, h * t), body)
	draw_rect(Rect2(x0, 0, 2, h * t), hi)
	draw_rect(Rect2(x0 + t * 1.5 - 2, 0, 2, h * t), low)
	for y in range(0, h, 3):
		draw_rect(Rect2(x0, y * t, t * 1.5, 1), low)
	# a capital wherever the pillar meets open air under the ceiling
	for y in range(1, h):
		if not is_stone(px, y) and is_stone(px, y - 1):
			draw_rect(Rect2(x0 - 3, y * t, t * 1.5 + 6, 4), hi)
			draw_rect(Rect2(x0 - 3, y * t + 4, t * 1.5 + 6, 1), low)
		if not is_stone(px, y - 1) and is_stone(px, y):
			draw_rect(Rect2(x0 - 3, y * t - 4, t * 1.5 + 6, 4), hi)


func _stone(x: int, y: int, p: Vector2, t: float) -> void:
	var v: int = _hash(x, y) % 4
	var src := Rect2(v * 32 + (x % 2) * 16, (y % 2) * 16, 16, 16)
	var up := not is_stone(x, y - 1)
	var down := not is_stone(x, y + 1)
	var left := not is_stone(x - 1, y)
	var right := not is_stone(x + 1, y)
	var buried := not (up or down or left or right)
	var tint := Color(0.52, 0.50, 0.60) if buried else Color(0.90, 0.88, 0.98)
	draw_texture_rect_region(FloorTex, Rect2(p, Vector2(t, t)), src, tint)
	if up:
		draw_rect(Rect2(p, Vector2(t, 2)), EDGE_TOP)
		draw_rect(Rect2(p + Vector2(0, 2), Vector2(t, 1)), EDGE_SIDE)
		var hsh := _hash(x, y + 7)
		if hsh % 3 == 0:
			draw_rect(Rect2(p + Vector2(hsh % 11, 0), Vector2(3, 1)), MOSS)
		if hsh % 5 == 0:
			draw_rect(Rect2(p + Vector2(int(hsh / 7.0) % 12, 1), Vector2(2, 2)), MOSS)
	if down:
		draw_rect(Rect2(p + Vector2(0, t - 2), Vector2(t, 2)), EDGE_LOW)
	if left:
		draw_rect(Rect2(p, Vector2(1, t)), EDGE_SIDE)
	if right:
		draw_rect(Rect2(p + Vector2(t - 1, 0), Vector2(1, t)), EDGE_LOW)


func _ledge(x: int, y: int, p: Vector2, t: float) -> void:
	draw_rect(Rect2(p, Vector2(t, 5)), LEDGE)
	draw_rect(Rect2(p, Vector2(t, 1)), LEDGE_HI)
	draw_rect(Rect2(p + Vector2(0, 5), Vector2(t, 1)), EDGE_LOW)
	# a little bracket under every other plank
	if (x + y) % 2 == 0:
		draw_rect(Rect2(p + Vector2(6, 6), Vector2(4, 3)), EDGE_SIDE)


func _rail_h(p: Vector2, t: float) -> void:
	## the track a sliding slab runs along
	for i in 4:
		draw_rect(Rect2(p.x + i * 4.0, p.y + 2.0, 2, 1), Color(0.45, 0.58, 0.85, 0.55))


func _rail_v(p: Vector2, t: float) -> void:
	## the chain a lift rides on, down the middle of its slab
	for i in 4:
		draw_rect(Rect2(p.x + 23.0, p.y + i * 4.0, 2, 2), Color(0.45, 0.58, 0.85, 0.5))


func _spikes(p: Vector2, t: float, down: bool) -> void:
	for i in 3:
		var x0 := p.x + 1.0 + i * 5.0
		var pts: PackedVector2Array
		if down:
			pts = PackedVector2Array([Vector2(x0, p.y), Vector2(x0 + 2.25, p.y + t * 0.62), Vector2(x0 + 4.5, p.y)])
		else:
			pts = PackedVector2Array([Vector2(x0, p.y + t), Vector2(x0 + 2.25, p.y + t * 0.38), Vector2(x0 + 4.5, p.y + t)])
		draw_colored_polygon(pts, SPIKE_DARK)
		var inner := PackedVector2Array([pts[0] + Vector2(1, 0), pts[1] + Vector2(0, 1.5 if not down else -1.5), pts[2] - Vector2(1, 0)])
		draw_colored_polygon(inner, SPIKE)
	# the base plate, so a row of spikes reads as one hazard in the dark
	if down:
		draw_rect(Rect2(p, Vector2(t, 2)), SPIKE_DARK)
	else:
		draw_rect(Rect2(p + Vector2(0, t - 2), Vector2(t, 2)), SPIKE_DARK)
