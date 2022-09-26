extends KinematicBody

# One godot unit is 64 hammer units

# This (https://developer.valvesoftware.com/wiki/TF2/Team_Fortress_2_Mapper%27s_Reference)
# page was really useful.

# I'm just going to assume that the collision hull will always be a box, but it
# wouldn't be that hard to change it (e.g. for cylinder replace extents.y with
# height/2)


export var axis_align_hull: bool = true
#export var view_height: float = 68/32 setget set_view_height
export var crouch_height: float = 0.98438 # 63hu
export var stand_height: float = 1.29688 # 83hu
export var crouch_time: float = 0.2

export var max_speed: float = 4.6875 # 300hu
export var accel: float = max_speed * 10
export var friction: float = max_speed * 2
# I couldn't find exactly what this should be, but the player needs to be able
# to jump up 70hu (1.09u) with crouching, 50hu (0.78u) without.
export var jump_power: float = 4.45
# export var coyote_time: float = 0.05 # set in the timer
export var snap_distance: float = 0.125

export var sensitivity: float = 0.002
# irl you can look a bit past straight up and down ¯\_(ツ)_/¯
export var camera_max_angle: float = (PI/2)*1.05
export var camera_min_angle: float = (-PI/2)*1.05

var _vel: Vector3 = Vector3.ZERO
var _crouching: bool = false
# This isn't full coyote time, it's just supposed to help when walking down
# slopes, etc. Can be used as a replacement for is_on_floor
var _coyote_mode: bool = false

onready var head: Spatial = $Head
onready var hull: CollisionShape = $CollisionHull
onready var coyote_timer: Timer = $CoyoteTimer


func _on_coyote_timer_timeout() -> void:
	_coyote_mode = false


# From the character's feet
func set_view_height(value: float) -> void:
	var feet = hull.translation.y

	if hull.shape is BoxShape:
		feet -= hull.shape.extents.y
		head.translation.y = feet + value


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
	assert(hull.shape is BoxShape, "expected a BoxShape in the collision hull")
	set_view_height(68/64)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	coyote_timer.connect("timeout", self, "_on_coyote_timer_timeout")


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
	var vel_flat: Vector3 = Vector3(_vel.x, 0, _vel.z)
	# snapping to slopes (otherwise changing direction will throw you off)
	var snap: Vector3 = -self.get_floor_normal() * snap_distance


	if self.is_on_floor():
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

	# how far the player might move this frame
	var frame_move = wish_dir * accel * delta

	# ignore if player is going too fast, and they are trying to go faster (
	# the `dot <= 0` bit )
	if vel_flat.length() < max_speed or vel_flat.dot(wish_dir) <= 0:
		_vel += frame_move


	var fric_force = vel_flat * friction * delta * -1
	_vel += fric_force
	# this stops the player from sliding around when they're close to 0 vel
	if input == Vector3.ZERO and vel_flat.length() < fric_force.length()/2:
		_vel.x = 0
		_vel.z = 0


	if Input.is_action_just_pressed("jump") and _coyote_mode:
		_vel.y = jump_power
		snap = Vector3.ZERO
		_coyote_mode = false # so they don't get a boost from jump

	if Input.is_action_pressed("crouch") and not _crouching:
		_crouching = true
		get_tree().create_tween().tween_property(
			hull, "shape:extents:y", crouch_height/2, crouch_time)
		get_tree().create_tween().tween_property(hull, "translation",
			Vector3(0, (stand_height-crouch_height)/2, 0), crouch_time)

	if (not Input.is_action_pressed("crouch")) and _crouching:
		_crouching = false
		get_tree().create_tween().tween_property(
			hull, "shape:extents:y", stand_height/2, crouch_time)
		get_tree().create_tween().tween_property(hull, "translation",
			Vector3.ZERO, crouch_time)

	if not _coyote_mode:
		_vel += get_gravity() * delta

	# _vel = self.move_and_slide(_vel, Vector3.UP, true)
	_vel = self.move_and_slide_with_snap(_vel, snap, Vector3.UP, true)
