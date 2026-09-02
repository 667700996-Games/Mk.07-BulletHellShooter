extends Node

signal shake_requested(level: int)
signal flash_requested(color: Color, strength: float)
signal freeze_requested(duration: float)

func shake(level: int) -> void:
	var safe_level := clampi(level, 1, 5)
	shake_requested.emit(safe_level)
	var haptic_scale := float(SaveManager.settings.get("shake", 0.85))
	for device in Input.get_connected_joypads():
		var weak := clampf(0.08 * safe_level * haptic_scale, 0.0, 0.7)
		var strong := clampf(0.035 * safe_level * safe_level * haptic_scale, 0.0, 1.0)
		Input.start_joy_vibration(device, weak, strong, 0.045 + safe_level * 0.035)

func flash(color: Color = Color.WHITE, strength: float = 0.5) -> void:
	flash_requested.emit(color, clampf(strength, 0.0, 1.0))

func hit_stop(duration: float) -> void:
	freeze_requested.emit(clampf(duration, 0.0, 0.08))
