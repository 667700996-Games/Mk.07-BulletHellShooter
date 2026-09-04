extends Node

signal state_changed(new_state: StringName)
signal settings_changed

const VIEW_SIZE := Vector2(540.0, 960.0)
const PLAY_BOUNDS := Rect2(22.0, 70.0, 496.0, 850.0)

enum GameState { TITLE, TRAINING, CHARACTER_SELECT, PLAYING, RESULTS }

var state: GameState = GameState.TITLE
var selected_character := 0
var difficulty_id := "normal"
var debug_enabled := OS.is_debug_build()
var last_result: Dictionary = {}

const CHARACTERS := [
	{
		"name": "KIRA VOSS", "role": "VECTOR BALANCE", "code": "A",
		"speed": 315.0, "focus_speed": 150.0, "power": 1.0,
		"shot_style": "TRI-VECTOR", "description": "Stable spread / adaptive focus",
		"primary_color": Color("39e7ff"), "accent": Color("9c62ff")
	},
	{
		"name": "DAE RYU", "role": "GRAVITY POWER", "code": "B",
		"speed": 260.0, "focus_speed": 122.0, "power": 1.32,
		"shot_style": "CRUSH LANCE", "description": "Narrow field / maximum impact",
		"primary_color": Color("ffb03a"), "accent": Color("ff3f78")
	},
	{
		"name": "MINA ZERO", "role": "PHASE SPEED", "code": "C",
		"speed": 380.0, "focus_speed": 178.0, "power": 0.82,
		"shot_style": "PHASE FAN", "description": "Wide coverage / rapid movement",
		"primary_color": Color("63ff9b"), "accent": Color("26a9ff")
	}
]

const DIFFICULTY_ORDER := ["story", "normal", "expert"]
const DIFFICULTIES := {
	"story": {"threat_scale": 0.78, "starting_lives": 5},
	"normal": {"threat_scale": 1.0, "starting_lives": 3},
	"expert": {"threat_scale": 1.18, "starting_lives": 2}
}

func set_state(next_state: GameState) -> void:
	state = next_state
	state_changed.emit(GameState.keys()[state].to_lower())

func character() -> Dictionary:
	return CHARACTERS[selected_character]

func difficulty(id: String = difficulty_id) -> Dictionary:
	return DIFFICULTIES.get(id, DIFFICULTIES.normal)

func start_run(character_index: int, next_difficulty: String = "normal", persist_difficulty: bool = true) -> void:
	selected_character = clampi(character_index, 0, CHARACTERS.size() - 1)
	difficulty_id = next_difficulty if DIFFICULTY_ORDER.has(next_difficulty) else "normal"
	SaveManager.set_selected_character(selected_character)
	if persist_difficulty:
		SaveManager.set_selected_difficulty(difficulty_id)
	ScoreManager.reset_run()
	set_state(GameState.PLAYING)

func start_replay(character_index: int, next_difficulty: String) -> void:
	selected_character = clampi(character_index, 0, CHARACTERS.size() - 1)
	difficulty_id = next_difficulty if DIFFICULTY_ORDER.has(next_difficulty) else "normal"
	ScoreManager.reset_run()
	set_state(GameState.PLAYING)

func finish_run(result: Dictionary, ranked: bool = true) -> void:
	last_result = result.duplicate(true)
	if String(result.get("mode", "campaign")) == "campaign":
		SaveManager.record_run(result, selected_character)
	if ranked:
		SaveManager.submit_score(
			int(result.get("total_score", 0)),
			String(result.get("difficulty", difficulty_id)),
			String(result.get("stage_id", StageManager.DEFAULT_STAGE_ID))
		)
	set_state(GameState.RESULTS)
