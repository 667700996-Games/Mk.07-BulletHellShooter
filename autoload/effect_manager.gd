extends Node

signal shake_requested(level: int)
signal flash_requested(color: Color, strength: float)
signal freeze_requested(duration: float)

func shake(level: int) -> void:
	shake_requested.emit(clampi(level, 1, 5))

func flash(color: Color = Color.WHITE, strength: float = 0.5) -> void:
	flash_requested.emit(color, clampf(strength, 0.0, 1.0))

func hit_stop(duration: float) -> void:
	freeze_requested.emit(clampf(duration, 0.0, 0.08))
