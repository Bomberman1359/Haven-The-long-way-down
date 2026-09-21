extends Node2D
## Lamp oil. Walk into it.

const PICK_R := 12.0
const AMOUNT := 25.0

var t := 0.0
var game

@onready var body: Sprite2D = $Body
@onready var glow: PointLight2D = $Glow


func _ready() -> void:
	game = get_tree().get_first_node_in_group("game")
	t = randf() * TAU


func _process(delta: float) -> void:
	t += delta * 2.3
	body.position.y = -6.0 + sin(t) * 1.6
	body.frame = int(t * 1.3) % 2
	glow.energy = 0.5 + sin(t * 1.6) * 0.1

	var p = game.player
	if is_instance_valid(p) and p.alive and not p.dark \
			and p.global_position.distance_to(global_position + Vector2(0, -6)) < PICK_R:
		p.add_fuel(AMOUNT)
		Sfx.play_var("pickup", -9.0)
		game.puff(global_position + Vector2(0, -6), Color(1.0, 0.76, 0.36), 11, 70.0)
		game.on_flask_taken()
		queue_free()
