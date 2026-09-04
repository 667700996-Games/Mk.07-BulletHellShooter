class_name RiskRouteOverlay
extends Control

## Small route-risk readout layered beside, not inside, GameHUD. Keeping this
## independent lets the scoring contract evolve without coupling the main HUD
## to bank timing or result persistence.

const PANEL_RECT := Rect2(8, 70, 82, 40)
const FEEDBACK_SECONDS := 1.45

var route_scoring_enabled := true
var reserve := 0
var capacity := 40
var feedback_text := ""
var feedback_kind := ""
var feedback_time := 0.0


func setup(enabled: bool) -> void:
	route_scoring_enabled = enabled
	visible = enabled
	capacity = maxi(1, int(ScoreManager.RISK_ROUTE_RULES.reserve_capacity))
	reserve = int(ScoreManager.risk_reserve) if enabled else 0
	queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process_input(false)
	set_process_unhandled_input(false)
	if not ScoreManager.risk_reserve_changed.is_connected(_on_reserve_changed):
		ScoreManager.risk_reserve_changed.connect(_on_reserve_changed)
	if not ScoreManager.risk_bank_committed.is_connected(_on_bank_committed):
		ScoreManager.risk_bank_committed.connect(_on_bank_committed)
	if not ScoreManager.risk_reserve_forfeited.is_connected(_on_reserve_forfeited):
		ScoreManager.risk_reserve_forfeited.connect(_on_reserve_forfeited)
	visible = route_scoring_enabled


func _process(delta: float) -> void:
	if feedback_time <= 0.0:
		return
	feedback_time = maxf(0.0, feedback_time - delta)
	if feedback_time <= 0.0:
		feedback_text = ""
		feedback_kind = ""
	queue_redraw()


func _on_reserve_changed(current: int, current_capacity: int) -> void:
	capacity = maxi(1, current_capacity)
	reserve = clampi(current, 0, capacity)
	queue_redraw()


func _on_bank_committed(_checkpoint_id: String, _units: int, bonus: int) -> void:
	feedback_kind = "bank"
	feedback_text = "+%06d" % maxi(0, bonus)
	feedback_time = FEEDBACK_SECONDS
	queue_redraw()


func _on_reserve_forfeited(_reason: String, units: int) -> void:
	feedback_kind = "lost"
	feedback_text = "-%02d" % maxi(0, units)
	feedback_time = FEEDBACK_SECONDS
	queue_redraw()


func _draw() -> void:
	if not route_scoring_enabled:
		return
	var font := ThemeDB.fallback_font
	var feedback_active := feedback_time > 0.0 and not feedback_text.is_empty()
	var accent := Color("ffc55f") if feedback_kind == "bank" else (Color("ff5577") if feedback_kind == "lost" else Color("69eaff"))
	var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.018) if feedback_active else 1.0
	draw_rect(PANEL_RECT, Color(0.01, 0.02, 0.065, 0.88))
	draw_rect(PANEL_RECT, Color(accent, 0.48 * pulse), false, 1.0)
	draw_line(PANEL_RECT.position, PANEL_RECT.position + Vector2(25, 0), Color(accent, pulse), 2.0)
	if feedback_active:
		draw_string(font, Vector2(13, 84), "%s %s" % [GameText.text("risk_reserve_short"), "↑" if feedback_kind == "bank" else "↓"], HORIZONTAL_ALIGNMENT_LEFT, 72, 9, Color(accent, pulse))
		draw_string(font, Vector2(13, 103), feedback_text, HORIZONTAL_ALIGNMENT_RIGHT, 72, 14, Color.WHITE)
		return
	draw_string(font, Vector2(13, 84), GameText.text("risk_reserve_short"), HORIZONTAL_ALIGNMENT_LEFT, 34, 9, Color(0.55, 0.75, 0.9))
	draw_string(font, Vector2(43, 84), "%02d/%02d" % [reserve, capacity], HORIZONTAL_ALIGNMENT_RIGHT, 42, 9, Color.WHITE)
	draw_rect(Rect2(13, 94, 72, 7), Color(0.13, 0.19, 0.30, 0.92))
	var ratio := float(reserve) / float(capacity)
	draw_rect(Rect2(13, 94, 72.0 * ratio, 7), Color("69eaff").lerp(Color("ffc55f"), ratio))
