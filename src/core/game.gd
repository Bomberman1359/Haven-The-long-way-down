extends Node2D
## The hub: the title screen, the five floors, the lantern's fuel economy, and
## what happens when it runs dry. Floors come from levels.gd, one string per row.
##
## Everything that costs you anything costs fuel. Spikes, drips, husks, leeches
## and pits all drain the lantern, and an empty lantern is the only way to die.

enum { MENU, PLAY, DYING, DEAD, PAUSED, WIN }

const TILE := 16
const SPIKE_COST := 22.0
const FALL_COST := 25.0
const SAVE_PATH := "user://long_way_down.cfg"
const SWARM_EXTRA := 9

const Levels = preload("res://src/core/levels.gd")
const PlayerScene: PackedScene = preload("res://src/player/player.tscn")
const ShadowScene: PackedScene = preload("res://src/shadows/shadow.tscn")
const BeaconScene: PackedScene = preload("res://src/world/beacon.tscn")
const StairScene: PackedScene = preload("res://src/world/stair.tscn")
const FlaskScene: PackedScene = preload("res://src/world/flask.tscn")
const Crumble = preload("res://src/world/crumble.gd")
const Drip = preload("res://src/world/drip.gd")
const Mover = preload("res://src/world/mover.gd")
const Stone = preload("res://src/world/stone.gd")
const SparkTex: Texture2D = preload("res://assets/sprites/spark.png")

const AMBIENT := Color(0.46, 0.44, 0.58)
const AMBIENT_DEEP := Color(0.22, 0.20, 0.32)
const ZOOM := 1.5

@onready var dark: CanvasModulate = $Dark
@onready var terrain = $Terrain
@onready var solids: Node2D = $Solids
@onready var entities: Node2D = $Entities
@onready var fx_root: Node2D = $Fx
@onready var cam: Camera2D = $Cam
@onready var hud = $HUD/Root
@onready var signs = $Signs/Root

var state := MENU
var depth := 1
var level: Dictionary = {}
var rows: PackedStringArray
var lw := 0
var lh := 0
var burn := 1.5

var player = null
var beacon = null
var stair = null
var shadows: Array = []
var light_sources: Array = []
var beacon_lit := false
var died_in_pit := false

var deaths := 0
var flasks_taken := 0
var run_time := 0.0
var best_depth := 1
var best_time := 0.0
var new_best := false
var dying_t := 0.0
var caught_t := -1.0
var shake_amt := 0.0
var warn_t := 0.0
var descending := false
var rng := RandomNumberGenerator.new()


func _enter_tree() -> void:
	add_to_group("game")


func _ready() -> void:
	_setup_input()
	rng.randomize()
	_load_progress()
	load_level(1)
	state = MENU
	entities.process_mode = Node.PROCESS_MODE_DISABLED
	solids.process_mode = Node.PROCESS_MODE_DISABLED
	hud.menu_reset()


func _setup_input() -> void:
	_bind("move_left", [KEY_A, KEY_LEFT])
	_bind("move_right", [KEY_D, KEY_RIGHT])
	_bind("jump", [KEY_SPACE, KEY_W, KEY_UP, KEY_Z, KEY_K])
	_bind("interact", [KEY_E, KEY_X, KEY_J])
	_bind("pause", [KEY_ESCAPE, KEY_P])
	_bind("restart", [KEY_R])
	_bind("home", [KEY_H])
	_bind("begin", [KEY_ENTER, KEY_KP_ENTER])
	_bind("ui_upx", [KEY_UP, KEY_W])
	_bind("ui_downx", [KEY_DOWN, KEY_S])


func _bind(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		InputMap.action_erase_events(action)
	else:
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


# ------------------------------------------------------------ persistence ---
func _load_progress() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return
	best_depth = int(cf.get_value("run", "best_depth", 1))
	best_time = float(cf.get_value("run", "best_time", 0.0))


func _save_progress() -> void:
	var cf := ConfigFile.new()
	cf.set_value("run", "best_depth", best_depth)
	cf.set_value("run", "best_time", best_time)
	cf.save(SAVE_PATH)


func level_count() -> int:
	return Levels.LEVELS.size()


func can_continue() -> bool:
	return best_depth > 1 and best_depth <= level_count()


func continue_depth() -> int:
	return clampi(best_depth, 1, level_count())


# ------------------------------------------------------------- build a floor ---
func _clear_level() -> void:
	for n in entities.get_children():
		n.queue_free()
	for n in solids.get_children():
		n.queue_free()
	for n in fx_root.get_children():
		n.queue_free()
	shadows.clear()
	light_sources.clear()
	player = null
	beacon = null
	stair = null


func load_level(n: int, from_beacon := false) -> void:
	_clear_level()
	depth = clampi(n, 1, level_count())
	level = Levels.LEVELS[depth - 1]
	rows = PackedStringArray(level["rows"])
	lh = rows.size()
	lw = rows[0].length()
	burn = float(level["burn"])
	beacon_lit = false
	died_in_pit = false
	descending = false
	caught_t = -1.0
	dying_t = 0.0

	terrain.setup(rows, TILE)
	_build_solids()
	_spawn_entities()
	signs.setup(level["signs"], TILE)

	cam.zoom = Vector2(ZOOM, ZOOM)
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = lw * TILE
	cam.limit_bottom = lh * TILE
	var deep: float = level["dark"]
	dark.color = AMBIENT.lerp(AMBIENT_DEEP, deep)

	if from_beacon and is_instance_valid(beacon):
		beacon.ignite_quiet()
		beacon_lit = true
		if is_instance_valid(stair):
			stair.unseal()
		player.global_position = beacon.global_position + Vector2(-20, -8)
		player.safe_pos = player.global_position
	cam.global_position = player.global_position
	cam.reset_smoothing()
	hud.fade_target = 0.0


func tile_at(tx: int, ty: int) -> String:
	if tx < 0 or tx >= lw or ty < 0:
		return "#"
	if ty >= lh:
		return "."
	return rows[ty][tx]


func solid_at(p: Vector2) -> bool:
	var tx := int(floor(p.x / TILE))
	var ty := int(floor(p.y / TILE))
	var c := tile_at(tx, ty)
	if c == "#":
		return true
	if c == "-" and fposmod(p.y, TILE) < 5.0:
		return true
	return false


func _build_solids() -> void:
	## Stone becomes as few rectangles as possible: runs along each row, then
	## runs with the same span stacked down the rows. Thin ledges are one-way.
	var runs: Array = []          # [x0, x1, y0, y1]
	var open: Dictionary = {}     # "x0,x1" -> index into runs, for the row above
	for y in lh:
		var row_open: Dictionary = {}
		var x := 0
		while x < lw:
			if rows[y][x] == "#":
				var x0 := x
				while x < lw and rows[y][x] == "#":
					x += 1
				var key := "%d,%d" % [x0, x - 1]
				if open.has(key):
					var i: int = open[key]
					runs[i][3] = y
					row_open[key] = i
				else:
					runs.append([x0, x - 1, y, y])
					row_open[key] = runs.size() - 1
			else:
				x += 1
		open = row_open

	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	solids.add_child(body)
	for r in runs:
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		var wtiles: int = r[1] - r[0] + 1
		var htiles: int = r[3] - r[2] + 1
		shape.size = Vector2(wtiles * TILE, htiles * TILE)
		cs.shape = shape
		cs.position = Vector2(r[0] * TILE + wtiles * TILE * 0.5, r[2] * TILE + htiles * TILE * 0.5)
		body.add_child(cs)

	# one-way ledges
	for y in lh:
		var x := 0
		while x < lw:
			if rows[y][x] == "-":
				var x0 := x
				while x < lw and rows[y][x] == "-":
					x += 1
				var cs := CollisionShape2D.new()
				var shape := RectangleShape2D.new()
				shape.size = Vector2((x - x0) * TILE, 5)
				cs.shape = shape
				cs.one_way_collision = true
				cs.position = Vector2(x0 * TILE + (x - x0) * TILE * 0.5, y * TILE + 2.5)
				body.add_child(cs)
			else:
				x += 1

	_build_movers()

	# cracked stone, one body each so they can fall on their own
	for y in lh:
		for x in lw:
			if rows[y][x] == "=":
				var c := StaticBody2D.new()
				c.set_script(Crumble)
				c.position = Vector2(x * TILE, y * TILE)
				c.cell = Vector2i(x, y)
				solids.add_child(c)


func _build_movers() -> void:
	## Rails in the map become moving slabs. A run of m/~ along a row is a
	## sideways rail and the slab starts at the m. A run of n/: down a column is
	## a lift, three tiles wide, starting at the n.
	for y in lh:
		var x := 0
		while x < lw:
			var ch := rows[y][x]
			if ch == "m" or ch == "~":
				var x0 := x
				var start := -1
				while x < lw and (rows[y][x] == "m" or rows[y][x] == "~"):
					if rows[y][x] == "m":
						start = x
					x += 1
				var x1 := x - 1
				var lo := Vector2(x0 * TILE, y * TILE)
				var hi := Vector2((x1 - 2) * TILE, y * TILE)
				_add_mover(lo, hi, 45.0, start >= 0 and start > (x0 + x1) / 2.0)
			else:
				x += 1
	for x in lw:
		var y := 0
		while y < lh:
			var ch := rows[y][x]
			if ch == "n" or ch == ":":
				var y0 := y
				var start := -1
				while y < lh and (rows[y][x] == "n" or rows[y][x] == ":"):
					if rows[y][x] == "n":
						start = y
					y += 1
				var y1 := y - 1
				_add_mover(Vector2(x * TILE, y0 * TILE), Vector2(x * TILE, y1 * TILE), 55.0,
					start >= 0 and start > (y0 + y1) / 2.0)
			else:
				y += 1


func _add_mover(from: Vector2, to: Vector2, spd: float, start_at_far_end: bool) -> void:
	var m := AnimatableBody2D.new()
	m.set_script(Mover)
	solids.add_child(m)
	if start_at_far_end:
		m.setup(to, from, spd)
	else:
		m.setup(from, to, spd)


func _spawn_entities() -> void:
	for y in lh:
		for x in lw:
			var c := rows[y][x]
			var foot := Vector2(x * TILE + TILE * 0.5, (y + 1) * TILE)
			match c:
				"P":
					player = PlayerScene.instantiate()
					player.position = foot + Vector2(0, -8)
					entities.add_child(player)
					player.fuel_empty.connect(_on_lantern_out)
				"B":
					beacon = BeaconScene.instantiate()
					beacon.position = foot + Vector2(TILE * 0.5, 0)
					entities.add_child(beacon)
				"S":
					stair = StairScene.instantiate()
					stair.position = foot + Vector2(TILE * 0.5, 0)
					entities.add_child(stair)
				"f":
					var f := FlaskScene.instantiate()
					f.position = foot
					entities.add_child(f)
				"w", "l", "h", "k", "b":
					var kind := {"w": 0, "l": 1, "h": 2, "k": 3, "b": 4}[c] as int
					_spawn_shadow(foot + Vector2(0, -8), kind)
				"F":
					var st := Node2D.new()
					st.set_script(Stone)
					st.position = Vector2(x * TILE + TILE * 0.5, y * TILE)
					entities.add_child(st)
				"d":
					var d := Node2D.new()
					d.set_script(Drip)
					d.position = Vector2(x * TILE + TILE * 0.5, y * TILE)
					entities.add_child(d)


func _spawn_shadow(at: Vector2, kind: int):
	var s := ShadowScene.instantiate()
	s.kind = kind
	s.position = at
	s.home = at
	entities.add_child(s)
	shadows.append(s)
	return s


# ------------------------------------------------------------------ the loop ---
func _physics_process(delta: float) -> void:
	_refresh_lights()
	match state:
		PLAY:
			run_time += delta
			_low_fuel_warning(delta)
		DYING:
			_dying_tick(delta)


func _process(delta: float) -> void:
	shake_amt = move_toward(shake_amt, 0.0, delta * 24.0)
	if is_instance_valid(player):
		var look: Vector2 = player.global_position + Vector2(player.velocity.x * 0.25, -10.0)
		var k := 1.0 - pow(0.004, delta)
		cam.global_position = cam.global_position.lerp(look, k)
	cam.offset = Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * shake_amt

	match state:
		MENU, DEAD, WIN, PAUSED:
			_menu_keys()
		PLAY:
			if Input.is_action_just_pressed("pause"):
				_pause(true)
			elif Input.is_action_just_pressed("restart"):
				load_level(depth, beacon_lit)
				state = PLAY
				hud.announce("DEPTH  %d" % depth, level["name"], 1.6)


func _menu_keys() -> void:
	if Input.is_action_just_pressed("ui_upx"):
		hud.menu_move(-1)
	if Input.is_action_just_pressed("ui_downx"):
		hud.menu_move(1)
	if Input.is_action_just_pressed("begin"):
		menu_activate(hud.menu_current())
	if state == DEAD:
		if Input.is_action_just_pressed("restart"):
			menu_activate("retry")
		elif Input.is_action_just_pressed("home"):
			menu_activate("home")
	elif state == PAUSED:
		if Input.is_action_just_pressed("pause"):
			menu_activate("resume")


func menu_activate(id: String) -> void:
	match id:
		"play":
			_start_run(1)
		"continue":
			_start_run(continue_depth())
		"quit":
			# a browser tab cannot be closed from inside the game
			if not OS.has_feature("web"):
				get_tree().quit()
		"resume":
			_pause(false)
		"restart":
			_pause(false)
			load_level(depth, beacon_lit)
			hud.announce("DEPTH  %d" % depth, level["name"], 1.6)
		"retry":
			var keep := beacon_lit
			load_level(depth, keep)
			_enter_play()
			hud.announce("DEPTH  %d" % depth, level["name"], 1.6)
		"home":
			_go_home()


func _start_run(from_depth: int) -> void:
	deaths = 0
	flasks_taken = 0
	run_time = 0.0
	new_best = false
	load_level(from_depth)
	_enter_play()
	Sfx.play("blip", -8.0)
	hud.announce("DEPTH  %d" % depth, level["name"], 2.8)


func _enter_play() -> void:
	state = PLAY
	entities.process_mode = Node.PROCESS_MODE_INHERIT
	solids.process_mode = Node.PROCESS_MODE_INHERIT
	hud.menu_reset()


func _pause(on: bool) -> void:
	if on:
		state = PAUSED
		entities.process_mode = Node.PROCESS_MODE_DISABLED
		solids.process_mode = Node.PROCESS_MODE_DISABLED
		hud.menu_reset()
		Sfx.play("blip", -12.0)
	else:
		_enter_play()


func _go_home() -> void:
	load_level(depth)
	state = MENU
	entities.process_mode = Node.PROCESS_MODE_DISABLED
	solids.process_mode = Node.PROCESS_MODE_DISABLED
	hud.menu_reset()
	Sfx.play("blip", -10.0)


func _unhandled_input(event: InputEvent) -> void:
	if state == MENU and event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_ESCAPE and not OS.has_feature("web"):
		get_tree().quit()


# ------------------------------------------------------------------- light ---
func _refresh_lights() -> void:
	light_sources.clear()
	if is_instance_valid(player) and not player.dark:
		light_sources.append({"pos": player.global_position, "r": player.light_r})
	if is_instance_valid(beacon):
		var r: float = beacon.light_radius()
		if r > 1.0:
			light_sources.append({"pos": beacon.global_position + Vector2(0, -30), "r": r})


func _low_fuel_warning(delta: float) -> void:
	if not is_instance_valid(player) or player.dark:
		return
	var frac: float = player.fuel / player.MAX_FUEL
	if frac < 0.2:
		warn_t -= delta
		if warn_t <= 0.0:
			warn_t = lerpf(0.45, 1.1, frac / 0.2)
			Sfx.play("blip", -20.0, 0.55)


# ------------------------------------------------------------- hazards etc ---
func check_hazards(p) -> void:
	var pos: Vector2 = p.global_position
	var x0 := pos.x - 4.0
	var x1 := pos.x + 4.0
	var y0 := pos.y - 7.0
	var y1 := pos.y + 7.5
	for ty in range(int(floor(y0 / TILE)), int(floor(y1 / TILE)) + 1):
		for tx in range(int(floor(x0 / TILE)), int(floor(x1 / TILE)) + 1):
			var c := tile_at(tx, ty)
			if c == "^" and y1 > ty * TILE + 8 and x1 > tx * TILE + 2 and x0 < tx * TILE + 14:
				p.hurt(SPIKE_COST, Vector2(pos.x, ty * TILE + 16))
				return
			if c == "v" and y0 < ty * TILE + 8 and x1 > tx * TILE + 2 and x0 < tx * TILE + 14:
				p.hurt(SPIKE_COST, Vector2(pos.x, ty * TILE))
				return


func ground_is_safe(pos: Vector2) -> bool:
	## solid stone under both feet and no spikes or cracks within a tile
	var ty := int(floor((pos.y + 9.0) / TILE))
	for dx in [-5.0, 5.0]:
		var tx := int(floor((pos.x + dx) / TILE))
		if tile_at(tx, ty) != "#":
			return false
	var cx := int(floor(pos.x / TILE))
	for x in range(cx - 1, cx + 2):
		for y in range(ty - 2, ty + 1):
			var c := tile_at(x, y)
			if c == "^" or c == "v" or c == "=":
				return false
	return true


func fell_out() -> void:
	if not is_instance_valid(player) or state != PLAY and state != DYING:
		return
	if player.dark:
		_consume()
		return
	Sfx.play("hurt", -6.0)
	shake(8.0)
	hud.flash(Color(0.1, 0.05, 0.15, 0.6))
	if player.fuel <= FALL_COST:
		died_in_pit = true
		player.lose_fuel(player.fuel)
		_consume()
		return
	player.lose_fuel(FALL_COST)
	player.global_position = player.safe_pos
	player.velocity = Vector2.ZERO
	player.invuln = 1.0
	cam.global_position = player.global_position
	cam.reset_smoothing()


func on_flask_taken() -> void:
	flasks_taken += 1


func on_beacon_lit(b) -> void:
	beacon_lit = true
	if is_instance_valid(player):
		player.add_fuel(player.MAX_FUEL)
	shake(9.0)
	hud.flash(Color(1.0, 0.86, 0.55, 0.34))
	puff(b.global_position + Vector2(0, -30), Color(1.0, 0.78, 0.38), 34, 180.0)
	if is_instance_valid(stair):
		stair.unseal()
	hud.announce("THE WAY DOWN OPENS", "the beacon will hold your place", 2.8)
	Sfx.play("discover", -8.0)


func descend() -> void:
	if state != PLAY or descending:
		return
	descending = true
	Sfx.play("descend", -4.0)
	hud.flash(Color(0.6, 0.75, 1.0, 0.45))
	player.frozen = true
	hud.fade_target = 1.0
	var t := get_tree().create_timer(0.55)
	t.timeout.connect(_after_descend)


func _after_descend() -> void:
	if depth >= level_count():
		_win()
		return
	best_depth = maxi(best_depth, depth + 1)
	_save_progress()
	load_level(depth + 1)
	_enter_play()
	hud.announce("DEPTH  %d" % depth, level["name"], 2.8)


func _win() -> void:
	state = WIN
	entities.process_mode = Node.PROCESS_MODE_DISABLED
	solids.process_mode = Node.PROCESS_MODE_DISABLED
	best_depth = level_count() + 1
	new_best = best_time <= 0.0 or run_time < best_time
	if new_best:
		best_time = run_time
	_save_progress()
	hud.fade_target = 0.0
	hud.menu_reset()
	Sfx.play("win", -4.0)


# --------------------------------------------------------- the lantern dies ---
func _on_lantern_out() -> void:
	if state != PLAY:
		return
	state = DYING
	dying_t = 0.0
	caught_t = -1.0
	Sfx.play("lose", -5.0)
	Sfx.play("shadow", -6.0, 0.8)
	hud.flash(Color(0.05, 0.02, 0.08, 0.5))
	shake(5.0)
	puff(player.global_position, Color(0.55, 0.5, 0.7), 12, 50.0)
	# every shadow on the floor turns toward you, and the dark sends more
	for s in shadows:
		if is_instance_valid(s):
			s.hunt()
	for i in SWARM_EXTRA:
		var ang := TAU * float(i) / SWARM_EXTRA + rng.randf() * 0.5
		var s = _spawn_shadow(player.global_position + Vector2(rng.randf_range(210.0, 280.0), 0).rotated(ang), 0)
		s.hunt()


func _dying_tick(delta: float) -> void:
	dying_t += delta
	dark.color = dark.color.lerp(Color(0.04, 0.03, 0.07), 1.0 - pow(0.2, delta))
	if caught_t >= 0.0:
		caught_t += delta
		if caught_t > 1.1:
			_to_dead()
	elif dying_t > 3.0:
		_consume()


func caught(_s) -> void:
	if state != DYING or caught_t >= 0.0:
		return
	_consume()


func _consume() -> void:
	if caught_t >= 0.0:
		return
	if state == PLAY:
		state = DYING
		dying_t = 0.0
	caught_t = 0.0
	if is_instance_valid(player):
		puff(player.global_position, Color(0.85, 0.2, 0.35), 30, 150.0)
		player.consumed()
	shake(12.0)
	hud.flash(Color(0.6, 0.05, 0.15, 0.45))
	Sfx.play("hurt", -3.0, 0.7)


func _to_dead() -> void:
	state = DEAD
	deaths += 1
	entities.process_mode = Node.PROCESS_MODE_DISABLED
	solids.process_mode = Node.PROCESS_MODE_DISABLED
	hud.menu_reset()


# ---------------------------------------------------------------------- fx ---
func shake(a: float) -> void:
	shake_amt = maxf(shake_amt, a)


func puff(pos: Vector2, col: Color, amount: int, speed: float) -> void:
	var p := CPUParticles2D.new()
	p.texture = SparkTex
	p.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	p.position = pos
	p.one_shot = true
	p.explosiveness = 0.92
	p.amount = amount
	p.lifetime = 0.6
	p.spread = 180.0
	p.direction = Vector2(0, -1)
	p.gravity = Vector2(0, 140)
	p.initial_velocity_min = speed * 0.35
	p.initial_velocity_max = speed
	p.scale_amount_min = 0.25
	p.scale_amount_max = 0.7
	p.color = col
	p.z_index = 8
	fx_root.add_child(p)
	p.emitting = true
	var t := Timer.new()
	t.wait_time = 1.2
	t.one_shot = true
	t.autostart = true
	p.add_child(t)
	t.timeout.connect(p.queue_free)
