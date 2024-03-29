extends CharacterBody3D

# One godot unit is 64 hammer units

# This (https://developer.valvesoftware.com/wiki/TF2/Team_Fortress_2_Mapper%27s_Reference)
# page was really useful.

# I'm just going to assume that the collision hull will always be a box, but it
# wouldn't be that hard to change it (e.g. for cylinder replace extents.y with
# height/2)


# I think this causes a bug where you cant jump sometimes while walking into
# walls.
@export var axis_align_hull: bool = true
#export var view_height: float = 68/32 setget set_view_height
@export var crouch_height: float = 0.98438 # 63hu
@export var stand_height: float = 1.29688 # 83hu
@export var crouch_time: float = 0.1

@export var max_speed: float = 4.6875 # 300hu
@export var accel: float = max_speed * 10
@export var max_air_speed: float = 1
@export var air_accel: float = 15
@export var friction: float = max_speed * 2
@export var snap_distance: float = 0.125
# I couldn't find exactly what this should be, but the player needs to be able
# to jump up 70hu (1.09u) with crouching, 50hu (0.78u) without.
@export var jump_power: float = 4.55
# export var coyote_time: float = 0.05 # set in the timer
@export var crouch_speed_modifier: float = 0.33
@export var backward_speed_modifier: float = 0.9
@export var auto_bhop: bool = true
@export var no_friction_on_bhop: bool = true

@export var sensitivity: float = 0.001
# irl you can look a bit past straight up and down ¯\_(ツ)_/¯
@export var camera_max_angle: float = (PI/2)*1.05
@export var camera_min_angle: float = (-PI/2)*1.05

var _crouching: bool = false
# This isn't full coyote time, it's just supposed to help when walking down
# slopes, etc. Can be used as a replacement for is_on_floor
var _coyote_mode: bool = false
var _on_floor_last_frame: bool = false

@onready var head: Node3D = $Head
@onready var hull: CollisionShape3D = $CollisionHull
@onready var coyote_timer: Timer = $CoyoteTimer

@onready var speed_label_int: Label = %SpeedLabelInt
@onready var speed_label_fract: Label = %SpeedLabelFract
@onready var speed_lost: ProgressBar = %SpeedLost
@onready var speed_gained: ProgressBar = %SpeedGained


func _on_coyote_timer_timeout() -> void:
	_coyote_mode = false


# From the character's feet
func set_view_height(value: float) -> void:
	var feet = hull.position.y

	if hull.shape is BoxShape3D:
		feet -= hull.shape.size.y/2
		head.position.y = feet + value


# I set the gravity to 800 hu/s = 12.5 u/s
func get_gravity() -> Vector3:
	return (ProjectSettings.get_setting("physics/3d/default_gravity")
		* ProjectSettings.get_setting("physics/3d/default_gravity_vector"))


# -z is forwards just in case you were wondering. (That's the way that the
# camera node points by default.)
func get_input() -> Vector3:
	return Vector3(
		Input.get_action_strength("move_right")
			-Input.get_action_strength("move_left"),
		0,
		Input.get_action_strength("move_back")
			-Input.get_action_strength("move_forward"))


func _ready() -> void:
	assert(hull.shape is BoxShape3D, "expected a BoxShape3D in the collision hull")
	set_view_height(68.0/64.0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	coyote_timer.connect("timeout", Callable(self, "_on_coyote_timer_timeout"))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			self.rotation.y += -event.relative.x * sensitivity
			head.rotation.x += -event.relative.y * sensitivity
			head.rotation.x = clamp(head.rotation.x,
				camera_min_angle, camera_max_angle)


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("capture_mouse"):
		Input.mouse_mode = (Input.MOUSE_MODE_CAPTURED if Input.mouse_mode ==
			Input.MOUSE_MODE_VISIBLE else Input.MOUSE_MODE_VISIBLE)


func _physics_process(delta: float) -> void:
	var input: Vector3 = get_input()
	# pretty obvious, used for horizontal speed and stuff
	var vel_flat: Vector3 = Vector3(self.velocity.x, 0, self.velocity.z)
	self.floor_snap_length = snap_distance


	# if the floor is too steep use air movement (slide off / surfing)
	if self.is_on_floor() and self.get_floor_angle() <= self.floor_max_angle:
		_coyote_mode = true
	if not self.is_on_floor() and _coyote_mode and coyote_timer.is_stopped():
		coyote_timer.start()


	if axis_align_hull:
		# setting it to a blank basis resets the rotation but also the scale
		# you shouldn't scale physics nodes anyway though so it's ok
		hull.global_transform.basis = Basis()


	# the **dir**ection that the player **wish**es to go in
	var wish_dir = (input.x * self.transform.basis.x
		+ input.z * self.transform.basis.z).normalized()

	# i thought it was a good idea to keep wish_dir normalized
	var norm_input = input.normalized()
	var scaled_wish_dir = (
		norm_input.x * self.transform.basis.x
		+ norm_input.z * self.transform.basis.z * (
			backward_speed_modifier if input.z > 0 else 1.0)
		) * (crouch_speed_modifier if _crouching else 1.0)


	# Ground Movement
	if _coyote_mode:
		# how far the player might move this frame
		var frame_move = scaled_wish_dir * accel * delta

		# ignore if player is going too fast, and they are trying to go faster (
		# the `dot <= 0` bit )
		if vel_flat.length() < max_speed or vel_flat.dot(wish_dir) <= 0:
			self.velocity += frame_move

		var fric_force = vel_flat * friction * delta * -1
		if not no_friction_on_bhop or _on_floor_last_frame:
			self.velocity += fric_force

		# this stops the player from sliding around when they're close to 0 vel
		if input == Vector3.ZERO and vel_flat.length() < fric_force.length()/2:
			self.velocity.x = 0
			self.velocity.z = 0

	else: # Air Movement
		var proj = self.velocity.project(wish_dir)
		var is_away = wish_dir.dot(proj) <= 0

		if proj.length() < max_air_speed or is_away:
			var vel_added = wish_dir * air_accel * delta

			# Hud stuff
			speed_gained.max_value = vel_added.length()
			speed_lost.max_value = vel_added.length()

			# I don't understand this but it works.. probably
			vel_added = vel_added.limit_length(
				max_air_speed + proj.length() * (int(is_away)*2 - 1))

			# Hud stuff
			speed_gained.value = vel_added.length() * (int(!is_away)*2 - 1)
			speed_lost.value = vel_added.length() * (int(is_away)*2 - 1)

			self.velocity += vel_added


	if _coyote_mode and (Input.is_action_just_pressed("jump") or
			auto_bhop and Input.is_action_pressed("jump")):
		self.velocity.y += jump_power
		self.floor_snap_length = 0
		_coyote_mode = false # so they don't get a boost from jump

	if Input.is_action_pressed("crouch") and not _crouching:
		_crouching = true
		get_tree().create_tween().tween_property(
			hull, "shape:size:y", crouch_height, crouch_time)
		get_tree().create_tween().tween_property(hull, "position",
			Vector3(0, (stand_height-crouch_height)/2, 0), crouch_time)

	if (not Input.is_action_pressed("crouch")) and _crouching:
		_crouching = false
		get_tree().create_tween().tween_property(
			hull, "shape:size:y", stand_height, crouch_time)
		get_tree().create_tween().tween_property(hull, "position",
			Vector3.ZERO, crouch_time)


	var speed: float = snappedf(vel_flat.length(), 0.01)
	var speed_int_part: float = floorf(speed)
	speed_label_int.text = str(speed_int_part)
	speed_label_fract.text = str(floorf((speed - speed_int_part)*100))


	if not _coyote_mode:
		self.velocity += get_gravity() * delta

	_on_floor_last_frame = _coyote_mode

	self.move_and_slide()
