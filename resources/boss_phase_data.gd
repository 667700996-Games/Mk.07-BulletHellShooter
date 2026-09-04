class_name BossPhaseData
extends Resource

## Stable localization key authored into boss-definition resources. The
## controller resolves this into `name` on a per-encounter runtime copy so the
## shared resource never depends on the language that happened to load it.
@export var name_key := ""
@export var name := "PHASE"
@export var hp := 1000.0
@export var duration := 30.0
@export var pattern_ids: PackedStringArray = []
@export var attack_sequence: PackedStringArray = []
@export var fire_interval := 0.8
@export var telegraph_time := 0.36
@export var transition_time := 0.8
@export var movement_id := "hover"
@export var signature_id := "standard"
@export var accent := Color("ff4e9b")
@export var bonus := 10000
