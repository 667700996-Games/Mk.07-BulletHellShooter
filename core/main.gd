extends Node

var current_view: Node
var pause_menu: PauseMenu
var smoke_mode := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameManager.selected_character = SaveManager.selected_character
	var args := OS.get_cmdline_user_args()
	if args.has("--smoke-stage"):
		smoke_mode = true
		call_deferred("_run_smoke_stage")
	elif args.has("--smoke-ui"):
		smoke_mode = true
		call_deferred("_run_smoke_ui")
	elif args.has("--smoke-combat"):
		smoke_mode = true
		call_deferred("_run_smoke_combat")
	elif args.has("--benchmark-bullets"):
		smoke_mode = true
		call_deferred("_run_bullet_benchmark")
	elif args.has("--benchmark-render"):
		smoke_mode = true
		call_deferred("_run_render_benchmark")
	elif args.has("--capture-title"):
		call_deferred("_capture_title")
	elif args.has("--capture-select"):
		call_deferred("_capture_select")
	elif args.has("--capture-stage"):
		call_deferred("_capture_stage")
	else:
		_show_title()

func _run_smoke_stage() -> void:
	_start_stage(0)
	await get_tree().process_frame
	if current_view is StageController:
		(current_view as StageController).player.debug_invincible = true
		(current_view as StageController).player.power = 4
	Engine.time_scale = 90.0

func _run_smoke_ui() -> void:
	_show_title()
	await get_tree().process_frame
	assert(current_view is TitleScreen, "Title screen failed")
	_show_character_select()
	await get_tree().process_frame
	assert(current_view is CharacterSelect, "Character selection failed")
	_start_stage(2)
	await get_tree().process_frame
	assert(current_view is StageController, "Stage failed to start")
	_show_pause()
	await get_tree().process_frame
	assert(get_tree().paused and pause_menu != null, "Pause menu failed")
	_resume()
	await get_tree().process_frame
	assert(not get_tree().paused, "Resume failed")
	var synthetic := ScoreManager.result(12.5, false)
	smoke_mode = false
	_on_run_finished(synthetic)
	await get_tree().process_frame
	assert(current_view is ResultsScreen, "Result screen failed")
	_start_stage(2)
	await get_tree().process_frame
	assert(current_view is StageController, "Retry failed")
	print("UI_FLOW_SMOKE_OK title=ok select=ok stage=ok pause=ok results=ok retry=ok")
	get_tree().quit()

func _run_smoke_combat() -> void:
	_start_stage(0)
	await get_tree().process_frame
	var stage := current_view as StageController
	stage.player.debug_invincible = true
	stage.player.locked = false
	stage.play_time = 20.0
	for i in 4:
		stage.enemy_manager.spawn("drone", Vector2(270 + (i-2)*28, 420-i*34), Vector2(270 + (i-2)*28, 420-i*34))
	Input.action_press("primary")
	for i in 150:
		await get_tree().process_frame
	Input.action_release("primary")
	Input.action_press("focus")
	for i in 50:
		await get_tree().process_frame
	Input.action_release("focus")
	var before_barriers := stage.player.barriers
	Input.action_press("barrier")
	await get_tree().process_frame
	Input.action_release("barrier")
	var graze_bullet := BulletData.new()
	graze_bullet.speed = 0.0
	graze_bullet.lifetime = 0.5
	stage.bullet_manager.spawn_bullet(stage.player.position + Vector2(16,0), 0.0, graze_bullet)
	for i in 5:
		await get_tree().process_frame
	assert(ScoreManager.enemies_destroyed > 0, "Primary/focus combat failed to destroy enemies")
	assert(stage.player.barriers == before_barriers - 1, "Barrier resource was not consumed")
	assert(ScoreManager.graze > 0, "Graze did not register")
	print("COMBAT_SMOKE_OK kills=%d graze=%d barrier=ok score=%d" % [ScoreManager.enemies_destroyed, ScoreManager.graze, ScoreManager.score])
	get_tree().quit()

func _run_bullet_benchmark() -> void:
	_start_stage(0)
	await get_tree().process_frame
	var stage := current_view as StageController
	stage.set_process(false)
	stage.bullet_manager.collision_enabled = false
	var data := BulletData.new()
	data.speed = 26.0
	data.lifetime = 20.0
	data.radius = 5.0
	for i in 4000:
		var p := Vector2(45 + (i * 47) % 450, 95 + (i * 83) % 760)
		stage.bullet_manager.spawn_bullet(p, float(i % 360) * PI / 180.0, data)
	var start_us := Time.get_ticks_usec()
	for frame in 300:
		stage.bullet_manager.update_bullets(1.0/60.0, Vector2(-500,-500), false)
	var elapsed_ms := float(Time.get_ticks_usec() - start_us) / 1000.0
	var average_ms := elapsed_ms / 300.0
	assert(stage.bullet_manager.count() >= 3000, "Bullet array corrupted during benchmark")
	print("BULLET_BENCHMARK_OK bullets=%d frames=300 average_update_ms=%.3f" % [stage.bullet_manager.count(), average_ms])
	get_tree().quit()

func _run_render_benchmark() -> void:
	_start_stage(0)
	await get_tree().process_frame
	var stage := current_view as StageController
	stage.set_process(false)
	stage.bullet_manager.collision_enabled = false
	var data := BulletData.new()
	data.speed = 9.0
	data.lifetime = 30.0
	data.radius = 5.0
	for i in 4000:
		var p := Vector2(28 + (i * 47) % 484, 72 + (i * 83) % 820)
		data.color = Color("ff4b91") if i % 3 else Color("ffb340")
		stage.bullet_manager.spawn_bullet(p, float(i % 360) * PI / 180.0, data)
	for frame in 180:
		stage.bullet_manager.update_bullets(1.0/60.0, Vector2(-500,-500), false)
		await get_tree().process_frame
	print("BULLET_RENDER_STRESS_OK bullets=%d frames=180" % stage.bullet_manager.count())
	get_tree().quit()

func _capture_title() -> void:
	_show_title()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png("res://tests/title_capture.png")
	print("TITLE_CAPTURE status=%s size=%s" % [error_string(error), str(image.get_size())])
	get_tree().quit()

func _capture_select() -> void:
	_show_character_select()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png("res://tests/select_capture.png")
	print("SELECT_CAPTURE status=%s size=%s" % [error_string(error), str(image.get_size())])
	get_tree().quit()

func _capture_stage() -> void:
	_start_stage(0)
	await get_tree().process_frame
	var stage := current_view as StageController
	stage.set_process(false)
	stage.player.locked = false
	stage.player.position = Vector2(270,820)
	stage.play_time = 350.0
	stage.background.time = 350.0
	var showcase := ["gunship","guard","shield","sniper","heavy_drone"]
	for i in showcase.size():
		var unit := stage.enemy_manager.spawn(showcase[i],Vector2(72+i*96,160+(i%2)*85),Vector2(72+i*96,160+(i%2)*85),i==2)
		unit.entering = false
	var ring := GameDatabase.pattern("ring")
	var layered := GameDatabase.pattern("layered")
	var spread := GameDatabase.pattern("spread")
	PatternEmitter.emit(stage.bullet_manager,Vector2(120,230),stage.player.position,ring,0.17,1.0)
	PatternEmitter.emit(stage.bullet_manager,Vector2(420,235),stage.player.position,layered,0.42,1.0)
	PatternEmitter.emit(stage.bullet_manager,Vector2(270,330),stage.player.position,spread,0.0,1.0)
	stage.bullet_manager.collision_enabled = false
	stage.bullet_manager.update_bullets(1.25,Vector2(-500,-500),false)
	for i in 18:
		stage.projectile_manager.spawn(stage.player.position+Vector2((i%5-2)*7,-i*18),Vector2(0,-900),8.0,3.0,GameManager.character().primary_color)
	stage.hud.announce("HOSTILE SURGE","CENTRAL SPINE // DENSITY LEVEL 4",2.0)
	stage.enemy_manager.queue_redraw()
	stage.bullet_manager.queue_redraw()
	stage.projectile_manager.queue_redraw()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png("res://tests/stage_capture.png")
	print("STAGE_CAPTURE status=%s size=%s bullets=%d" % [error_string(error), str(image.get_size()), stage.bullet_manager.count()])
	get_tree().quit()

func _replace_view(next_view: Node) -> void:
	if current_view != null and is_instance_valid(current_view):
		current_view.queue_free()
	current_view = next_view
	add_child(current_view)

func _show_title() -> void:
	get_tree().paused = false
	GameManager.set_state(GameManager.GameState.TITLE)
	var screen := TitleScreen.new()
	screen.start_pressed.connect(_show_character_select)
	_replace_view(screen)

func _show_character_select() -> void:
	GameManager.set_state(GameManager.GameState.CHARACTER_SELECT)
	var screen := CharacterSelect.new()
	screen.character_confirmed.connect(_start_stage)
	screen.cancelled.connect(_show_title)
	_replace_view(screen)

func _start_stage(index: int = GameManager.selected_character) -> void:
	get_tree().paused = false
	GameManager.start_run(index)
	var stage := StageController.new()
	stage.run_finished.connect(_on_run_finished)
	stage.pause_requested.connect(_show_pause)
	_replace_view(stage)

func _show_pause() -> void:
	if pause_menu != null:
		return
	get_tree().paused = true
	pause_menu = PauseMenu.new()
	pause_menu.resume_pressed.connect(_resume)
	pause_menu.restart_pressed.connect(_restart_stage)
	pause_menu.title_pressed.connect(_quit_to_title)
	add_child(pause_menu)

func _resume() -> void:
	if pause_menu != null:
		pause_menu.queue_free()
		pause_menu = null
	get_tree().paused = false

func _restart_stage() -> void:
	_resume()
	_start_stage(GameManager.selected_character)

func _quit_to_title() -> void:
	_resume()
	_show_title()

func _on_run_finished(result: Dictionary) -> void:
	if smoke_mode:
		Engine.time_scale = 1.0
		print("ACCEPTANCE_SMOKE_OK total_score=%d clear_time=%.2f cleared=%s" % [int(result.get("total_score",0)), float(result.get("clear_time",0.0)), str(result.get("cleared",false))])
		get_tree().quit()
		return
	if bool(result.get("restart",false)):
		_start_stage(GameManager.selected_character)
		return
	GameManager.finish_run(result)
	var screen := ResultsScreen.new()
	screen.setup(result)
	screen.retry_pressed.connect(func(): _start_stage(GameManager.selected_character))
	screen.title_pressed.connect(_show_title)
	_replace_view(screen)
