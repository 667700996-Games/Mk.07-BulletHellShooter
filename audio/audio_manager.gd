extends Node

## Runtime synthesizer: all music and SFX are original and generated in memory.

var music_player: AudioStreamPlayer
var music_playback: AudioStreamGeneratorPlayback
var music_frames := PackedVector2Array()
var sfx_players: Array[AudioStreamPlayer] = []
var sfx_voice_priorities: Array[int] = []
var sfx_voice_started: Array[int] = []
var sfx_cache: Dictionary = {}
var rng := RandomNumberGenerator.new()
var audio_output_enabled := true
var sfx_serial := 0
var sample_clock := 0
var theme := ""
var pending_theme := ""
var theme_transition := 0.0
var theme_transition_switched := false
var theme_time := 0.0
var beat_flash := 0.0
var music_duck := 0.0
var music_intensity := 0.25
var target_music_intensity := 0.25
var music_bpm := 108.0
var music_root := 43.65
var music_drive := 0.55
var music_lead := 0.020
var music_motif: Array = THEME_MOTIFS.title

const MIX_RATE := 44100.0
# The procedural score is a low-bandwidth fallback; 22.05 kHz keeps its transient
# detail while halving synthesis cost versus the authored 44.1 kHz SFX library.
const MUSIC_MIX_RATE := 22050.0
const THEME_TRANSITION_DURATION := 0.72
const THEMES := {
	"title": {"bpm": 108.0, "root": 43.65, "drive": 0.55, "lead": 0.020},
	"stage": {"bpm": 154.0, "root": 55.0, "drive": 0.82, "lead": 0.034},
	"boss": {"bpm": 172.0, "root": 46.25, "drive": 1.0, "lead": 0.046},
	"tempest": {"bpm": 162.0, "root": 49.00, "drive": 0.88, "lead": 0.039},
	"tempest_boss": {"bpm": 180.0, "root": 41.20, "drive": 1.06, "lead": 0.052},
	"forge": {"bpm": 168.0, "root": 51.91, "drive": 0.93, "lead": 0.043},
	"forge_boss": {"bpm": 186.0, "root": 38.89, "drive": 1.10, "lead": 0.057},
	"result": {"bpm": 124.0, "root": 65.41, "drive": 0.62, "lead": 0.028}
}
const THEME_INTENSITIES := {"title": 0.18, "stage": 0.34, "boss": 0.76, "tempest": 0.42, "tempest_boss": 0.82, "forge": 0.48, "forge_boss": 0.87, "result": 0.22}
const CHORD_PROGRESSION: Array[float] = [1.0, 1.1892, 1.4983, 1.3348]
const BASS_RATIOS: Array[float] = [1.0, 1.0, 2.0, 1.4983]
const ARP_RATIOS: Array[float] = [2.0, 2.3784, 2.9966, 3.5636, 2.9966, 2.3784, 4.0, 3.5636]
const NOTE_RATIOS: Array[float] = [1.0, 1.0595, 1.1225, 1.1892, 1.2599, 1.3348, 1.4142, 1.4983, 1.5874, 1.6818, 1.7818, 1.8877]
const THEME_MOTIFS := {
	"title": [0, 7, 3, 10, 0, 7, 5, 10],
	"stage": [0, 3, 7, 10, 7, 3, 10, 5],
	"boss": [0, 1, 7, 6, 0, 10, 1, 6],
	# Tritone leaps and falling semitones give NULL TEMPEST its own unstable,
	# electrical signature without increasing mix density or synthesis cost.
	"tempest": [0, 6, 1, 8, 3, 10, 6, 1],
	"tempest_boss": [0, 6, 11, 1, 8, 3, 10, 6],
	# Dorian rises and chromatic descents evoke a colossal solar mechanism rather
	# than reusing either the neon route's drive or the Tempest tritone language.
	"forge": [0, 2, 7, 9, 5, 11, 7, 1],
	"forge_boss": [0, 8, 1, 11, 5, 6, 2, 10],
	"result": [0, 4, 7, 11, 9, 7, 4, 2]
}
const SFX_PRIORITIES := {
	"boss_die": 100, "player_hit": 96, "warning": 92, "barrier": 88,
	"phase": 82, "telegraph": 76, "ui_confirm": 68, "pickup": 58,
	"enemy_die": 52, "ui_move": 44, "focus": 38, "enemy_shot": 18,
	"graze": 16, "shot": 12, "hit": 10
}

func _ready() -> void:
	rng.seed = 0x50535943
	audio_output_enabled = DisplayServer.get_name() != "headless"
	_setup_buses()
	if audio_output_enabled:
		music_player = AudioStreamPlayer.new()
		music_player.name = "ProceduralMusic"
		music_player.bus = "Music"
		var generator := AudioStreamGenerator.new()
		generator.mix_rate = MUSIC_MIX_RATE
		generator.buffer_length = 0.25
		music_player.stream = generator
		add_child(music_player)
	for i in 12:
		var player := AudioStreamPlayer.new()
		player.name = "SFX_%02d" % i
		player.bus = "SFX"
		add_child(player)
		sfx_players.append(player)
		sfx_voice_priorities.append(0)
		sfx_voice_started.append(0)
	_build_sfx()
	call_deferred("play_music", "title")

func _exit_tree() -> void:
	shutdown()

func shutdown() -> void:
	set_process(false)
	# Stop both sides of the generator and discard queued PCM before releasing the
	# handle. AudioServer then finishes its short deletion fade at a frame boundary.
	if music_playback != null:
		music_playback.stop()
		music_playback.clear_buffer()
	music_playback = null
	if music_player and is_instance_valid(music_player):
		music_player.stop()
		music_player.stream = null
		music_player.queue_free()
	music_player = null
	for player in sfx_players:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
			player.queue_free()
	sfx_players.clear()
	sfx_voice_priorities.clear()
	sfx_voice_started.clear()
	sfx_cache.clear()

func _setup_buses() -> void:
	for bus_name in ["Music", "SFX", "UI"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
	var music_index := AudioServer.get_bus_index("Music")
	var sfx_index := AudioServer.get_bus_index("SFX")
	var ui_index := AudioServer.get_bus_index("UI")
	AudioServer.set_bus_send(music_index, "Master")
	AudioServer.set_bus_send(sfx_index, "Master")
	AudioServer.set_bus_send(ui_index, "Master")
	var music_value := float(SaveManager.settings.get("music", 0.68))
	var sfx_value := float(SaveManager.settings.get("sfx", 0.82))
	AudioServer.set_bus_volume_db(music_index, linear_to_db(maxf(0.001, music_value)))
	AudioServer.set_bus_volume_db(sfx_index, linear_to_db(maxf(0.001, sfx_value)))
	AudioServer.set_bus_volume_db(ui_index, linear_to_db(maxf(0.001, sfx_value)))
	# Keep dense barrages punchy without letting stacked one-shots clip harshly.
	if AudioServer.get_bus_effect_count(sfx_index) == 0:
		var combat_compressor := AudioEffectCompressor.new()
		combat_compressor.threshold = -14.0
		combat_compressor.ratio = 4.0
		combat_compressor.attack_us = 1200.0
		combat_compressor.release_ms = 140.0
		AudioServer.add_bus_effect(sfx_index, combat_compressor)
		var combat_limiter := AudioEffectHardLimiter.new()
		combat_limiter.ceiling_db = -1.0
		combat_limiter.release = 0.08
		AudioServer.add_bus_effect(sfx_index, combat_limiter)
	if AudioServer.get_bus_effect_count(music_index) == 0:
		var music_compressor := AudioEffectCompressor.new()
		music_compressor.threshold = -10.0
		music_compressor.ratio = 2.2
		music_compressor.attack_us = 2000.0
		music_compressor.release_ms = 260.0
		AudioServer.add_bus_effect(music_index, music_compressor)
	if AudioServer.get_bus_effect_count(ui_index) == 0:
		var ui_limiter := AudioEffectHardLimiter.new()
		ui_limiter.ceiling_db = -1.5
		AudioServer.add_bus_effect(ui_index, ui_limiter)
	GameManager.settings_changed.connect(_refresh_bus_levels)

func _refresh_bus_levels() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(maxf(0.001, float(SaveManager.settings.music))))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(maxf(0.001, float(SaveManager.settings.sfx))))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("UI"), linear_to_db(maxf(0.001, float(SaveManager.settings.sfx))))

func play_music(next_theme: String) -> void:
	var requested_theme := next_theme if THEMES.has(next_theme) else "title"
	if requested_theme == theme and pending_theme.is_empty():
		return
	if music_player == null:
		_activate_theme(requested_theme)
		return
	if theme.is_empty() or not music_player.playing:
		_activate_theme(requested_theme)
		music_player.play()
		music_playback = music_player.get_stream_playback() as AudioStreamGeneratorPlayback
		return
	pending_theme = requested_theme
	theme_transition = THEME_TRANSITION_DURATION
	theme_transition_switched = false

func _activate_theme(next_theme: String) -> void:
	theme = next_theme
	theme_time = 0.0
	sample_clock = 0
	var config: Dictionary = THEMES[theme]
	music_bpm = float(config.bpm)
	music_root = float(config.root)
	music_drive = float(config.drive)
	music_lead = float(config.lead)
	music_motif = THEME_MOTIFS[theme]
	target_music_intensity = float(THEME_INTENSITIES.get(theme, 0.25))

func stop_music() -> void:
	if music_playback != null:
		music_playback.stop()
		music_playback.clear_buffer()
	music_playback = null
	if music_player != null:
		music_player.stop()
	pending_theme = ""
	theme_transition = 0.0

func set_music_intensity(value: float) -> void:
	target_music_intensity = clampf(value, 0.0, 1.0)

func _process(delta: float) -> void:
	theme_time += delta
	music_intensity = lerpf(music_intensity, target_music_intensity, 1.0 - exp(-delta * 1.7))
	beat_flash = maxf(0.0, beat_flash - delta * 3.0)
	music_duck = maxf(0.0, music_duck - delta * 1.7)
	var transition_db := 0.0
	if theme_transition > 0.0:
		theme_transition = maxf(0.0, theme_transition - delta)
		var transition_progress := 1.0 - theme_transition / THEME_TRANSITION_DURATION
		if not theme_transition_switched and transition_progress >= 0.5:
			_activate_theme(pending_theme)
			theme_transition_switched = true
		var transition_gain := absf(transition_progress * 2.0 - 1.0)
		transition_db = lerpf(-24.0, 0.0, transition_gain)
		if theme_transition <= 0.0:
			pending_theme = ""
			theme_transition_switched = false
	if music_player:
		var target_volume := -7.0 * music_duck + transition_db
		music_player.volume_db = lerpf(music_player.volume_db, target_volume, minf(1.0, delta * 18.0))
	if music_playback == null:
		return
	var available := music_playback.get_frames_available()
	if available <= 0:
		return
	music_frames.resize(available)
	for i in available:
		music_frames[i] = _music_frame(sample_clock)
		sample_clock += 1
	# Crossing the script/native boundary once per buffer is substantially cheaper
	# than calling push_frame() for every sample on the main thread.
	music_playback.push_buffer(music_frames)

func _music_frame(index: int, config: Dictionary = {}) -> Vector2:
	var t := float(index) / MUSIC_MIX_RATE
	var use_cached_theme := config.is_empty()
	var bpm := music_bpm if use_cached_theme else float(config.bpm)
	var root := music_root if use_cached_theme else float(config.root)
	var drive := music_drive if use_cached_theme else float(config.drive)
	var beat := t * bpm / 60.0
	var step := int(floor(beat * 4.0))
	var beat_phase := fmod(beat, 1.0)
	var sixteenth := fmod(beat * 4.0, 1.0)
	var chord_root: float = root * CHORD_PROGRESSION[(int(beat / 4.0)) % CHORD_PROGRESSION.size()]
	var bass_note: float = chord_root * BASS_RATIOS[step % BASS_RATIOS.size()]
	var bass_env := exp(-sixteenth * 4.8)
	var bass := (sin(TAU * bass_note * t) + 0.32 * sin(TAU * bass_note * 2.01 * t)) * bass_env * lerpf(0.095, 0.155, music_intensity)
	var arp_note: float = chord_root * ARP_RATIOS[step % ARP_RATIOS.size()]
	var arp := (2.0 * absf(fmod(arp_note * t, 1.0) - 0.5) - 0.5) * exp(-sixteenth * 7.0) * lerpf(0.046, 0.092, music_intensity)
	var kick_phase := fmod(beat, 1.0)
	var kick_freq := 47.0 + 95.0 * exp(-kick_phase * 20.0)
	var kick := sin(TAU * kick_freq * t) * exp(-kick_phase * 13.0) * lerpf(0.17, 0.29, music_intensity)
	var snare_phase := fmod(beat + 0.5, 1.0)
	var noise := sin(float(index * 7919 % 104729))
	var snare := noise * exp(-snare_phase * 18.0) * (0.11 if int(floor(beat * 2.0)) % 2 == 1 else 0.025)
	var hat := noise * exp(-sixteenth * 28.0) * lerpf(0.018, 0.052, music_intensity)
	var pad := (sin(TAU * chord_root * 2.0 * t) + sin(TAU * chord_root * 2.9966 * t)) * 0.018
	var tension_step := step % 8
	var tension_gate := 1.0 if tension_step == 3 or tension_step == 6 or tension_step == 7 else 0.0
	var tension_note := chord_root * (5.9932 if step % 2 else 4.7568)
	var tension := sin(TAU * tension_note * t) * exp(-sixteenth * 9.0) * tension_gate * music_intensity * music_intensity * 0.034
	var motif: Array = music_motif if use_cached_theme else THEME_MOTIFS[theme]
	var eighth_step := int(floor(beat * 2.0))
	var eighth_phase := fmod(beat * 2.0, 1.0)
	var lead_note := chord_root * 4.0 * NOTE_RATIOS[int(motif[eighth_step % motif.size()])]
	var lead_env := exp(-eighth_phase * 5.8)
	var lead_gain := (music_lead if use_cached_theme else float(config.lead)) * music_intensity * music_intensity
	var lead := (sin(TAU * lead_note * t) + sin(TAU * lead_note * 2.005 * t) * 0.16) * lead_env * lead_gain
	var center := (bass + kick + snare * 0.72) * drive
	var moving_pan := sin(t * 0.73) * 0.16
	var left := center + (arp + hat + tension) * (1.0 - moving_pan) + pad * 0.88 + lead * 1.12
	var right := center + (arp + hat + tension) * (1.0 + moving_pan) + pad * 1.12 + lead * 0.88
	return Vector2(tanh(left * 1.65) * 0.48, tanh(right * 1.65) * 0.48)

func play_sfx(id: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if not sfx_cache.has(id) or sfx_players.is_empty():
		return
	if id == "player_hit" or id == "barrier" or id == "boss_die":
		music_duck = maxf(music_duck, 1.0)
	elif id == "phase" or id == "warning":
		music_duck = maxf(music_duck, 0.55)
	var incoming_priority := _sfx_priority(id)
	var target_index := -1
	for i in sfx_players.size():
		if not sfx_players[i].playing:
			target_index = i
			break
	if target_index < 0:
		var lowest_priority := 1000000
		var oldest_serial := 1000000
		for i in sfx_players.size():
			if sfx_voice_priorities[i] < lowest_priority or (sfx_voice_priorities[i] == lowest_priority and sfx_voice_started[i] < oldest_serial):
				lowest_priority = sfx_voice_priorities[i]
				oldest_serial = sfx_voice_started[i]
				target_index = i
		if incoming_priority < lowest_priority:
			return
	var target := sfx_players[target_index]
	sfx_serial += 1
	sfx_voice_priorities[target_index] = incoming_priority
	sfx_voice_started[target_index] = sfx_serial
	target.bus = "UI" if id.begins_with("ui_") else "SFX"
	target.stream = sfx_cache[id]
	target.pitch_scale = clampf(pitch, 0.55, 1.8)
	target.volume_db = volume_db
	target.play()

func _sfx_priority(id: String) -> int:
	if id.begins_with("phase_"):
		return 80
	return int(SFX_PRIORITIES.get(id, 32))

func _build_sfx() -> void:
	sfx_cache["ui_move"] = _make_tone(760.0, 0.045, 0.18, 1.3, 0.0)
	sfx_cache["ui_confirm"] = _make_tone(510.0, 0.14, 0.25, 2.0, 0.12)
	sfx_cache["shot"] = _make_tone(270.0, 0.055, 0.12, 1.7, 0.28)
	sfx_cache["focus"] = _make_tone(145.0, 0.11, 0.16, 3.2, 0.05)
	sfx_cache["enemy_shot"] = _make_tone(430.0, 0.07, 0.08, 0.66, 0.2)
	sfx_cache["telegraph"] = _make_tone(880.0, 0.18, 0.14, 0.48, 0.08)
	sfx_cache["hit"] = _make_noise(0.045, 0.10, 24.0)
	sfx_cache["enemy_die"] = _make_noise(0.18, 0.24, 9.0, 105.0)
	sfx_cache["player_hit"] = _make_noise(0.48, 0.38, 4.0, 62.0)
	sfx_cache["barrier"] = _make_tone(92.0, 0.65, 0.38, 4.0, 0.0)
	sfx_cache["graze"] = _make_tone(1120.0, 0.035, 0.10, 1.15, 0.0)
	sfx_cache["pickup"] = _make_tone(620.0, 0.18, 0.22, 2.52, 0.0)
	sfx_cache["warning"] = _make_tone(73.0, 0.55, 0.35, 0.5, 0.0)
	sfx_cache["phase"] = _make_noise(0.44, 0.32, 5.0, 180.0)
	# Phase signatures are deliberately separated in register and sweep so the
	# next attack grammar is identifiable even when the screen is crowded.
	sfx_cache["phase_perimeter"] = _make_tone(118.0, 0.42, 0.28, 1.85, 0.18)
	sfx_cache["phase_rotary"] = _make_tone(246.0, 0.38, 0.24, 0.62, 0.30)
	sfx_cache["phase_arbiter"] = _make_noise(0.52, 0.31, 4.2, 156.0)
	sfx_cache["phase_sentence"] = _make_tone(760.0, 0.32, 0.22, 0.34, 0.08)
	sfx_cache["phase_halo"] = _make_tone(392.0, 0.56, 0.22, 2.02, 0.20)
	sfx_cache["phase_maelstrom"] = _make_noise(0.62, 0.30, 3.4, 92.0)
	sfx_cache["phase_lattice"] = _make_tone(184.0, 0.48, 0.27, 3.0, 0.34)
	sfx_cache["phase_last_light"] = _make_tone(64.0, 0.82, 0.38, 4.6, 0.28)
	sfx_cache["phase_solar_reap"] = _make_tone(326.0, 0.46, 0.27, 0.52, 0.24)
	sfx_cache["phase_crown_arc"] = _make_tone(214.0, 0.52, 0.28, 2.36, 0.31)
	sfx_cache["phase_furnace_lock"] = _make_noise(0.66, 0.34, 3.1, 118.0)
	sfx_cache["phase_first_ignition"] = _make_tone(156.0, 0.55, 0.29, 2.84, 0.22)
	sfx_cache["phase_photosphere"] = _make_tone(428.0, 0.58, 0.25, 1.48, 0.19)
	sfx_cache["phase_prominence"] = _make_noise(0.58, 0.33, 3.8, 204.0)
	sfx_cache["phase_blackbody"] = _make_tone(49.0, 0.76, 0.38, 0.38, 0.34)
	sfx_cache["phase_last_dawn"] = _make_tone(78.0, 0.92, 0.41, 5.2, 0.30)
	sfx_cache["boss_die"] = _make_noise(1.4, 0.42, 2.2, 48.0)

func _make_tone(freq: float, duration: float, gain: float, sweep: float, grit: float) -> AudioStreamWAV:
	var frames := int(MIX_RATE * duration)
	var bytes := PackedByteArray()
	bytes.resize(frames * 4)
	var phase_left := 0.0
	var phase_right := 0.0
	for i in frames:
		var t := float(i) / MIX_RATE
		var p := t / duration
		var current_freq := freq * lerpf(1.0, sweep, p)
		phase_left += TAU * current_freq * 0.997 / MIX_RATE
		phase_right += TAU * current_freq * 1.003 / MIX_RATE
		var attack := minf(1.0, p * 90.0)
		var envelope := attack * exp(-p * 5.2) * gain
		var transient := _sample_noise(i, 3) * exp(-p * 42.0) * (0.08 + grit * 0.18)
		var left_wave := sin(phase_left) + sin(phase_left * 2.01 + 0.18) * grit + transient
		var right_wave := sin(phase_right) + sin(phase_right * 1.99 - 0.18) * grit - transient * 0.72
		_write_stereo_sample(bytes, i, tanh(left_wave * envelope), tanh(right_wave * envelope))
	return _wav(bytes)

func _make_noise(duration: float, gain: float, decay: float, tone: float = 0.0) -> AudioStreamWAV:
	var frames := int(MIX_RATE * duration)
	var bytes := PackedByteArray()
	bytes.resize(frames * 4)
	var phase_left := 0.0
	var phase_right := 0.0
	var filtered_left := 0.0
	var filtered_right := 0.0
	for i in frames:
		var p := float(i) / float(frames)
		phase_left += TAU * tone * 0.993 / MIX_RATE
		phase_right += TAU * tone * 1.007 / MIX_RATE
		filtered_left = lerpf(filtered_left, rng.randf_range(-1.0, 1.0), 0.28)
		filtered_right = lerpf(filtered_right, rng.randf_range(-1.0, 1.0), 0.28)
		var attack := minf(1.0, p * 120.0)
		var envelope := attack * exp(-p * decay) * gain
		var left_wave := filtered_left * 0.72 + sin(phase_left) * 0.36
		var right_wave := filtered_right * 0.72 + sin(phase_right + 0.24) * 0.36
		_write_stereo_sample(bytes, i, tanh(left_wave * envelope * 1.25), tanh(right_wave * envelope * 1.25))
	return _wav(bytes)

func _sample_noise(index: int, salt: int) -> float:
	var a := sin(float((index * 7919 + salt * 104729) % 999983) * 0.017)
	var b := sin(float((index * 3571 + salt * 6151) % 524287) * 0.031)
	return (a + b) * 0.5

func _write_stereo_sample(bytes: PackedByteArray, index: int, left: float, right: float) -> void:
	bytes.encode_s16(index * 4, int(clampf(left, -0.98, 0.98) * 32767.0))
	bytes.encode_s16(index * 4 + 2, int(clampf(right, -0.98, 0.98) * 32767.0))

func _wav(bytes: PackedByteArray) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = int(MIX_RATE)
	wav.stereo = true
	wav.data = bytes
	return wav
