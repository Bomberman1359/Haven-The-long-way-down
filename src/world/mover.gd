extends AnimatableBody2D
## A slab of stone that rides back and forth along a rail. Stand on it and it
## carries you. Like a ledge, you can jump up through it from below.

const PAUSE := 0.6
const WIDTH := 48.0

var a := Vector2.ZERO     # one end of the rail (top-left of the slab)
var b := Vector2.ZERO     # the other end
var speed := 36.0
var t := 0.0
var dir := 1.0
var hold := 0.0


func setup(from: Vector2, to: Vector2, spd: float) -> void:
	a = from
	b = to
	speed = spd
	position = a


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	z_index = 2
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(WIDTH, 6)
	cs.shape = shape
	cs.position = Vector2(WIDTH * 0.5, 3)
	cs.one_way_collision = true
	add_child(cs)


func _physics_process(delta: float) -> void:
	if hold > 0.0:
		hold -= delta
		return
	var span := maxf(1.0, a.distance_to(b))
	t += dir * speed * delta / span
	if t >= 1.0:
		t = 1.0
		dir = -1.0
		hold = PAUSE
	elif t <= 0.0:
		t = 0.0
		dir = 1.0
		hold = PAUSE
	position = a.lerp(b, t)


func _draw() -> void:
	var stone := Color(0.50, 0.47, 0.60)
	draw_rect(Rect2(0, 0, WIDTH, 6), stone)
	draw_rect(Rect2(0, 0, WIDTH, 1), Color(0.78, 0.76, 0.88))
	draw_rect(Rect2(0, 5, WIDTH, 1), Color(0.10, 0.09, 0.14))
	for i in 3:
		draw_rect(Rect2(i * 16 + 7, 1, 2, 4), Color(0.36, 0.34, 0.46))
	# little glowing runes so a moving slab reads as different from stone
	draw_rect(Rect2(3, 2, 2, 2), Color(0.55, 0.75, 1.0, 0.9))
	draw_rect(Rect2(WIDTH - 5, 2, 2, 2), Color(0.55, 0.75, 1.0, 0.9))
