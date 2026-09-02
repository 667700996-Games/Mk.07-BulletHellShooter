class_name BossPhaseData
extends Resource

@export var name := "PHASE"
@export var hp := 1000.0
@export var duration := 30.0
@export var pattern_ids: PackedStringArray = []
@export var fire_interval := 0.8
@export var movement_id := "hover"
@export var accent := Color("ff4e9b")
@export var bonus := 10000
