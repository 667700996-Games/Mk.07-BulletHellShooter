extends Node

## Contract test for pluggable boss signatures. It protects the shipped support
## attack grammar and proves that future signatures can be injected without a
## BossController source edit.

class ProbeSignature extends BossSignatureBehavior:
	var emit_calls := 0
	var draw_calls := 0

	func emit_support(_context: Dictionary) -> int:
		emit_calls += 1
		return 7

	func draw_transition(_host: Node2D, _context: Dictionary) -> void:
		draw_calls += 1


const EXPECTED_IDS := [
	"arbiter", "blackbody", "crown_arc", "first_ignition", "furnace_lock", "halo",
	"last_dawn", "last_light", "lattice", "maelstrom", "perimeter", "photosphere",
	"prominence", "rotary", "sentence", "solar_reap"
]

var failures: Array[String] = []
var created_managers: Array[BulletManager] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry := BossSignatureRegistry.new()
	_check(Array(registry.registered_ids()) == EXPECTED_IDS, "built-in signature catalog changed or is unsorted")
	_check(Array(BossSignatureRegistry.builtin_ids()) == EXPECTED_IDS, "static built-in catalog differs from runtime registry")
	for signature_id in EXPECTED_IDS:
		_check(BossSignatureRegistry.supports_builtin(signature_id), "built-in signature is not discoverable: %s" % signature_id)

	_test_trigger_contracts(registry)
	_test_pattern_contracts(registry)
	_test_determinism(registry)
	_test_extension_contract(registry)
	_finish()


func _test_trigger_contracts(registry: BossSignatureRegistry) -> void:
	_check(_emit_count(registry, "perimeter", "ring", 1) == 0, "perimeter fired on an odd attack cursor")
	_check(_emit_count(registry, "perimeter", "aimed", 2) == 0, "perimeter fired for a non-ring primary")
	_check(_emit_count(registry, "arbiter", "spread", 3) == 0, "arbiter fired before its fourth attack")
	_check(_emit_count(registry, "maelstrom", "spread", 2) == 0, "maelstrom fired before its third attack")
	_check(_emit_count(registry, "sentence", "ring", 1) == 0, "sentence fired for a non-aimed primary")
	_check(_emit_count(registry, "solar_reap", "spread", 1) == 0, "solar reap fired before its second attack")
	_check(_emit_count(registry, "first_ignition", "ring", 1) == 0, "first ignition fired for a non-spread primary")
	_check(_emit_count(registry, "blackbody", "ring", 1) == 0, "blackbody fired for a non-geometric primary")
	_check(_emit_count(registry, "unknown_signature", "ring", 2) == 0, "unknown signature did not fail closed")


func _test_pattern_contracts(registry: BossSignatureRegistry) -> void:
	var perimeter := _emit(registry, "perimeter", "ring", 2, 0.4)
	_check(perimeter.count() == 8, "perimeter echo no longer emits eight bullets")
	var ring_speed := GameDatabase.pattern("ring").speed * 0.72
	_check(_near(perimeter.velocities[0].length(), ring_speed), "perimeter speed scale changed")
	_check(_angle_near(perimeter.velocities[0].angle(), 0.4 + PI / 8.0), "perimeter rotation offset changed")

	var rotary := _emit(registry, "rotary", "rotating", 1, 0.4)
	_check(rotary.count() == 4, "rotary counter-pattern no longer emits four bullets")
	_check(rotary.strengths[0] < 0.0, "rotary counter-pattern no longer reverses curvature")
	_check(_angle_near(rotary.velocities[0].angle(), -0.4), "rotary counter-pattern rotation changed")

	var arbiter := _emit(registry, "arbiter", "spread", 4)
	_check(arbiter.count() == 3 and _near(arbiter.velocities[1].length(), 168.0), "arbiter aimed fan contract changed")
	var sentence := _emit(registry, "sentence", "aimed", 1)
	_check(sentence.count() == 2 and _near(sentence.velocities[0].length(), 188.0), "sentence aimed fan contract changed")

	var halo := _emit(registry, "halo", "ring", 1)
	_check(halo.count() == 9, "halo support no longer emits nine bullets")
	_check(halo.modifiers[0] == BulletManager.MOD_ACCELERATE and _near(halo.strengths[0], 12.0), "halo acceleration contract changed")

	var maelstrom := _emit(registry, "maelstrom", "spread", 3)
	_check(maelstrom.count() == 1, "maelstrom seeker no longer emits one aimed bullet")
	_check(_near(maelstrom.velocities[0].length(), GameDatabase.pattern("aimed").speed + 34.0), "maelstrom seeker speed changed")

	var lattice := _emit(registry, "lattice", "geometric", 1)
	_check(lattice.count() == 20, "lattice support no longer emits two layers of ten bullets")
	_check(_angle_near(lattice.velocities[0].angle(), 0.4 + PI / 10.0), "lattice rotation offset changed")

	var last_light := _emit(registry, "last_light", "spread", 4)
	_check(last_light.count() == 3 and _near(last_light.velocities[1].length(), 218.0), "last-light aimed fan contract changed")

	var solar_reap := _emit(registry, "solar_reap", "aimed", 2)
	_check(solar_reap.count() == 3 and _near(solar_reap.velocities[1].length(), 176.0), "solar-reap aimed fan contract changed")
	var crown_arc := _emit(registry, "crown_arc", "rotating", 1, 0.4)
	_check(crown_arc.count() == 6 and crown_arc.strengths[0] < 0.0, "crown-arc counter-rotation contract changed")
	var furnace_lock := _emit(registry, "furnace_lock", "spread", 3)
	_check(furnace_lock.count() == 10 and furnace_lock.modifiers[0] == BulletManager.MOD_ACCELERATE, "furnace-lock ring contract changed")
	var first_ignition := _emit(registry, "first_ignition", "spread", 1)
	_check(first_ignition.count() == 3 and _near(first_ignition.velocities[1].length(), 182.0), "first-ignition fan contract changed")
	var photosphere := _emit(registry, "photosphere", "ring", 1)
	_check(photosphere.count() == 11 and photosphere.modifiers[0] == BulletManager.MOD_ACCELERATE, "photosphere ring contract changed")
	var prominence := _emit(registry, "prominence", "aimed", 3)
	_check(prominence.count() == 3, "prominence stream contract changed")
	var blackbody := _emit(registry, "blackbody", "geometric", 1)
	_check(blackbody.count() == 24, "blackbody lattice contract changed")
	var last_dawn := _emit(registry, "last_dawn", "aimed", 4)
	_check(last_dawn.count() == 4 and _near(last_dawn.velocities[2].length(), 224.0), "last-dawn fan contract changed")


func _test_determinism(registry: BossSignatureRegistry) -> void:
	var first := _emit(registry, "lattice", "geometric", 1, 1.234)
	var second := _emit(registry, "lattice", "geometric", 1, 1.234)
	_check(first.positions == second.positions, "identical lattice contexts produced different origins")
	_check(first.velocities == second.velocities, "identical lattice contexts produced different trajectories")
	_check(first.delays == second.delays, "identical lattice contexts produced different delays")


func _test_extension_contract(registry: BossSignatureRegistry) -> void:
	var probe := ProbeSignature.new()
	_check(registry.register("custom_probe", probe), "custom signature could not be registered")
	_check(not registry.register("custom_probe", ProbeSignature.new()), "duplicate registration overwrote an existing signature")
	_check(registry.supports("custom_probe"), "registered custom signature is not discoverable")
	_check(registry.emit_support("custom_probe", {}) == 7 and probe.emit_calls == 1, "custom support behavior was not dispatched")
	registry.draw_transition("custom_probe", null, {})
	_check(probe.draw_calls == 1, "custom transition behavior was not dispatched")
	_check(registry.unregister("custom_probe") and not registry.supports("custom_probe"), "custom signature could not be cleanly removed")
	_check(not registry.register("", probe), "empty signature ID was accepted")


func _emit_count(registry: BossSignatureRegistry, signature_id: String, primary_id: String, cursor: int) -> int:
	return _emit(registry, signature_id, primary_id, cursor).count()


func _emit(registry: BossSignatureRegistry, signature_id: String, primary_id: String, cursor: int, rotation: float = 0.4) -> BulletManager:
	var manager := BulletManager.new()
	created_managers.append(manager)
	var emitted := registry.emit_support(signature_id, {
		"bullet_manager": manager,
		"origin": Vector2(270.0, 180.0),
		"target": Vector2(310.0, 720.0),
		"primary_id": primary_id,
		"cursor": cursor,
		"rotation": rotation,
		"difficulty": 1.0,
		"accent": Color("ff4e9b")
	})
	_check(emitted == manager.count(), "registry reported a different bullet count for %s" % signature_id)
	return manager


func _near(a: float, b: float) -> bool:
	return absf(a - b) <= 0.001


func _angle_near(a: float, b: float) -> bool:
	return absf(wrapf(a - b, -PI, PI)) <= 0.001


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	for manager in created_managers:
		manager.free()
	created_managers.clear()
	if failures.is_empty():
		print("BOSS_SIGNATURE_REGISTRY_TEST_OK builtins=%d triggers=ok patterns=ok deterministic=ok injection=ok" % EXPECTED_IDS.size())
		get_tree().quit(0)
		return
	printerr("BOSS_SIGNATURE_REGISTRY_TEST_FAILED errors=%d" % failures.size())
	for failure in failures:
		printerr("BOSS_SIGNATURE_REGISTRY_ERROR %s" % failure)
	get_tree().quit(1)
