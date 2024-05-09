extends CharacterBody2D

enum State {
	IDLE,
	RUNNING,
	JUMP,
	FALL,
	LANDING,
	WALL_SLIDING,
	WALL_JUMPING,
}

const GROUND_STATES := [State.RUNNING, State.IDLE, State.LANDING]
#每秒两百像素
const RUN_SPEED := 160.0 
# 二维空间，正方向朝下，所以是负数
const JUMP_VELOCITY := -320.0
# 向量
const WALL_JUMP_VELOCITY := Vector2(300, -280)
# 加速度
const FLOOR_ACCELERATION := RUN_SPEED / 0.2
const AIR_ACCELERATION := RUN_SPEED / 0.2

var default_gravity := ProjectSettings.get("physics/2d/default_gravity") as float
var is_first_tick := false

@onready var graphics: Node2D = $Graphics
@onready var animation_player = $AnimationPlayer
@onready var coyote_timer: Timer = $CoyoteTimer
@onready var jump_request_timer: Timer = $JumpRequestTimer
@onready var hand_checker: RayCast2D = $Graphics/HandChecker
@onready var foot_checker: RayCast2D = $Graphics/FootChecker
@onready var state_machine: StateMachine = $StateMachine

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("jump"):
		jump_request_timer.start()
	if event.is_action_released("jump"):
		jump_request_timer.stop()
		if velocity.y < JUMP_VELOCITY / 2:
			velocity.y = JUMP_VELOCITY / 2

func tick_physics(state: State, delta: float) -> void:
	match state:
		State.IDLE:
			move(default_gravity, delta)
		State.RUNNING:
			move(default_gravity, delta)
		State.JUMP:
			move(0.0 if is_first_tick else default_gravity, delta)
		State.FALL:
			move(default_gravity, delta)
		State.LANDING:
			stand(default_gravity, delta)
		State.WALL_SLIDING:
			move(default_gravity / 3, delta)
			graphics.scale.x = get_wall_normal().x
		State.WALL_JUMPING:
			if state_machine.state_time < 0.1:
				stand(0.0 if is_first_tick else default_gravity, delta)
				graphics.scale.x = get_wall_normal().x
			else:
				move(default_gravity, delta)
	
	is_first_tick = false

func move(gravity: float, delta: float) -> void:
	var direction := Input.get_axis("move_left", "move_right")
	var acceleration := FLOOR_ACCELERATION if is_on_floor() else AIR_ACCELERATION
	velocity.x = move_toward(velocity.x, direction * RUN_SPEED, acceleration * delta)
	velocity.y += gravity * delta
	
	if not is_zero_approx(direction):
		graphics.scale.x = -1 if direction < 0 else 1
	
	move_and_slide()

func stand(gravity: float, delta: float) -> void:
	var acceleration := FLOOR_ACCELERATION if is_on_floor() else AIR_ACCELERATION
	velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
	velocity.y += gravity * delta
	
	move_and_slide()

func can_wall_slide() -> bool:
	return is_on_wall() and hand_checker.is_colliding() and foot_checker.is_colliding()

func get_next_state(state: State) -> State:
	var direction := Input.get_axis("move_left", "move_right")
	# 静止不动
	var is_still := is_zero_approx(direction) and is_zero_approx(velocity.x)
	# 如果在地面并且剩余时间大于0则说明能够起跳
	var can_jump = is_on_floor() or coyote_timer.time_left > 0
	var should_jump = can_jump and jump_request_timer.time_left > 0
	if should_jump:
		return State.JUMP
	
	match state:
		State.IDLE:
			if not is_on_floor():
				return State.FALL
			if not is_still:
				return State.RUNNING
		State.RUNNING:
			if is_still:
				return State.IDLE
		State.JUMP:
			if velocity.y >= 0:
				return State.FALL
		State.FALL:
			if is_on_floor():
				return State.LANDING if is_still else State.RUNNING
			if can_wall_slide():
				return State.WALL_SLIDING
		State.LANDING:
			if not is_still:
				return State.RUNNING
			if not animation_player.is_playing():
				return State.IDLE
		State.WALL_SLIDING:
			if jump_request_timer.time_left > 0:
				return State.WALL_JUMPING
			if is_on_floor():
				return State.IDLE
			if not is_on_wall():
				return State.FALL
		State.WALL_JUMPING:
			if can_wall_slide() and not is_first_tick:
				return State.WALL_SLIDING
			if velocity.y >= 0:
				return State.FALL
	return state


func transition_state(from: State, to: State) -> void:
	#print("[%s] %s => %s" % [
		#Engine.get_physics_frames(),
		#State.keys()[from] if from != -1 else "<START>",
		#State.keys()[to],
	#])
	
	if from not in GROUND_STATES and to in GROUND_STATES:
		coyote_timer.stop()
	match to:
		State.IDLE:
			animation_player.play("idle")
		State.RUNNING:
			animation_player.play("running")
		State.JUMP:
			animation_player.play("jump")
			velocity.y = JUMP_VELOCITY
			coyote_timer.stop()
			jump_request_timer.stop()
		State.FALL:
			animation_player.play("fall")
			if from in GROUND_STATES:
				coyote_timer.start()
		State.LANDING:
			animation_player.play("landing")
		State.WALL_SLIDING:
			animation_player.play("wall_sliding")
		State.WALL_JUMPING:
			animation_player.play("jump")
			velocity = WALL_JUMP_VELOCITY
			# 判断wall法线方向，帮助之后蹬墙跳是向左还是向右
			velocity.x *= get_wall_normal().x
			jump_request_timer.stop()
	
	is_first_tick = true
