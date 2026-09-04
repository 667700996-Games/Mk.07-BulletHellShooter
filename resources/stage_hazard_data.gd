class_name StageHazardData
extends Resource

## One deterministic route-hazard window. The manager interprets a small,
## reusable vocabulary so authored stages can change pressure without scripting.

const VALID_KINDS := [
	"lightning_lane", "debris_field", "shock_ring",
	"solar_flare", "molten_fragments", "corona_wave"
]

@export_group("Identity")
@export var hazard_id := ""
@export_enum("lightning_lane", "debris_field", "shock_ring", "solar_flare", "molten_fragments", "corona_wave") var kind := "lightning_lane"

@export_group("Timeline")
@export_range(0.0, 3600.0, 0.1) var start_time := 0.0
@export_range(0.0, 3600.0, 0.1) var end_time := 0.0
@export_range(0.2, 60.0, 0.1) var interval := 5.0
@export_range(0.2, 5.0, 0.05) var warning_time := 1.2
@export_range(0.1, 8.0, 0.05) var active_time := 0.65

@export_group("Shape")
@export_enum("vertical", "horizontal", "alternate") var orientation := "alternate"
@export_range(1, 4, 1) var lane_count := 1
@export_range(12.0, 160.0, 1.0) var width := 46.0
@export_range(1, 12, 1) var burst_count := 4
@export_range(40.0, 900.0, 1.0) var speed := 320.0
@export_range(40.0, 700.0, 1.0) var max_radius := 360.0
@export var color := Color("8d63ff")

func validation_errors(route_duration: float = 3600.0) -> PackedStringArray:
	var errors := PackedStringArray()
	if hazard_id.strip_edges().is_empty():
		errors.append("hazard_id is empty")
	if not VALID_KINDS.has(kind):
		errors.append("unknown hazard kind: %s" % kind)
	if start_time < 0.0 or end_time <= start_time or end_time > route_duration:
		errors.append("hazard window is outside the route")
	if interval <= 0.0 or warning_time < 0.2 or active_time <= 0.0:
		errors.append("hazard timing is invalid")
	if lane_count < 1 or burst_count < 1 or width <= 0.0 or speed <= 0.0 or max_radius <= 0.0:
		errors.append("hazard shape is invalid")
	return errors

func is_valid(route_duration: float = 3600.0) -> bool:
	return validation_errors(route_duration).is_empty()
