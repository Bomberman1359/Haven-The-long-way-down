extends Node2D
## Words scratched into the back wall. They sit on their own canvas layer so
## the dark does not swallow them, and they fade in as your lantern gets close.

var signs: Array = []
var tile := 16
var game
var font: Font


func _ready() -> void:
	game = get_tree().get_first_node_in_group("game")
	font = ThemeDB.fallback_font


func setup(list: Array, ts: int) -> void:
	signs = list
	tile = ts
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var p = game.player if game != null else null
	if not is_instance_valid(p) or game.state == game.MENU:
		return
	var pp: Vector2 = p.global_position
	for s in signs:
		var at := Vector2(float(s[0]) * tile, float(s[1]) * tile)
		var text: String = s[2]
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		var centre := at + Vector2(width * 0.5, -4.0)
		var d := centre.distance_to(pp)
		var a := clampf(1.0 - (d - 120.0) / 150.0, 0.0, 1.0)
		if a <= 0.01:
			continue
		draw_string(font, at + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0, 0, 0, 0.6 * a))
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.80, 0.78, 0.92, 0.85 * a))
