extends Node

## Runtime synthesizer: all music and SFX are original and generated in memory.

var music_player: AudioStreamPlayer
var music_playback: AudioStreamGeneratorPlayback
var sfx_players: Array[AudioStreamPlayer] = []
var sfx_cache: Dictionary = {}
var rng := RandomNumberGenerator.new()
var sample_clock := 0
var theme := ""
var theme_time := 0.0
var beat_flash := 0.0
var music_duck := 0.0

const MIX_RATE := 44100.0
const THEMES := {
	"title": {"bpm": 108.0, "root": 43.65, "drive": 0.55},
	"stage": {"bpm": 154.0, "root": 55.0, "drive": 0.82},
	"boss": {"bpm": 172.0, "root": 46.25, "drive": 1.0},
	"result": {"bpm": 124.0, "root": 65.41, "drive": 0.62}
}

func _ready() -> void:
	rng.seed = 0x50535943
	_setup_buses()
	music_player = AudioStreamPlayer.new()
	music_player.name = "ProceduralMusic"
	music_player.bus = "Music"
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = MIX_RATE
	generator.buffer_length = 0.25
	music_player.stream = generator
	add_child(music_player)
	for i in 12:
		var player := AudioStreamPlayer.new()
		player.name = "SFX_%02d" % i
		player.bus = "SFX"
		add_child(player)
		sfx_players.append(player)
	_build_sfx()
	call_deferred("play_music", "title")

func _exit_tree() -> void:
	shutdown()

func shutdown() -> void:
	set_process(false)
	if music_player and is_instance_valid(music_player):
		music_player.stop()
		music_player.stream = null
		music_player.free()
	music_player = null
	music_playback = null
	for player in sfx_players:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
			player.free()
	sfx_players.clear()
	sfx_cache.clear()

func _setup_buses() -> void:
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
	var music_index := AudioServer.get_bus_index("Music")
	var sfx_index := AudioServer.get_bus_index("SFX")
	AudioServer.set_bus_send(music_index, "Master")
	AudioServer.set_bus_send(sfx_index, "Master")
	var music_value := float(SaveManager.settings.get("music", 0.68))
	var sfx_value := float(SaveManager.settings.get("sfx", 0.82))
	AudioServer.set_bus_volume_db(music_index, linear_to_db(maxf(0.001, music_value)))
	AudioServer.set_bus_volume_db(sfx_index, linear_to_db(maxf(0.001, sfx_value)))
	# Keep dense barrages punchy without letting stacked one-shots clip harshly.
	if AudioServer.get_bus_effect_count(sfx_index) == 0:
		AudioServer.add_bus_effect(sfx_index, AudioEffectCompressor.new())
		AudioServer.add_bus_effect(sfx_index, AudioEffectLimiter.new())
	if AudioServer.get_bus_effect_count(music_index) == 0:
		AudioServer.add_bus_effect(music_index, AudioEffectCompressor.new())
	GameManager.settings_changed.connect(_refresh_bus_levels)

func _refresh_bus_levels() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(maxf(0.001, float(SaveManager.settings.music))))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(maxf(0.001, float(SaveManager.settings.sfx))))

func play_music(next_theme: String) -> void:
	if theme == next_theme and music_player.playing:
		return
	theme = next_theme if THEMES.has(next_theme) else "title"
	theme_time = 0.0
	sample_clock = 0
	if not music_player.playing:
		music_player.play()
	music_playback = music_player.get_stream_playback() as AudioStreamGeneratorPlayback

func stop_music() -> void:
	music_player.stop()
	music_playback = null

func _process(delta: float) -> void:
	theme_time += delta
	beat_flash = maxf(0.0, beat_flash - delta * 3.0)
	music_duck = maxf(0.0, music_duck - delta * 1.7)
	if music_player:
		music_player.volume_db = lerpf(music_player.volume_db, -7.0 * music_duck, minf(1.0, delta * 18.0))
	if music_playback == null:
		return
	var available := music_playback.get_frames_available()
	var config: Dictionary = THEMES[theme]
	for i in available:
		var frame := _music_frame(sample_clock, config)
		music_playback.push_frame(frame)
		sample_clock += 1

func _music_frame(index: int, config: Dictionary) -> Vector2:
	var t := float(index) / MIX_RATE
	var bpm := float(config.bpm)
	var root := float(config.root)
	var drive := float(config.drive)
	var beat := t * bpm / 60.0
	var step := int(floor(beat * 4.0))
	var beat_phase := fmod(beat, 1.0)
	var sixteenth := fmod(beat * 4.0, 1.0)
	var progression: Array[float] = [1.0, 1.1892, 1.4983, 1.3348]
	var chord_root: float = root * progression[(int(beat / 4.0)) % progression.size()]
	var bass_note: float = chord_root * ([1.0, 1.0, 2.0, 1.4983][step % 4] as float)
	var bass_env := exp(-sixteenth * 4.8)
	var bass := (sin(TAU * bass_note * t) + 0.32 * sin(TAU * bass_note * 2.01 * t)) * bass_env * 0.13
	var arp_ratios: Array[float] = [2.0, 2.3784, 2.9966, 3.5636, 2.9966, 2.3784, 4.0, 3.5636]
	var arp_note: float = chord_root * arp_ratios[step % arp_ratios.size()]
	var arp := (2.0 * absf(fmod(arp_note * t, 1.0) - 0.5) - 0.5) * exp(-sixteenth * 7.0) * 0.075
	var kick_phase := fmod(beat, 1.0)
	var kick_freq := 47.0 + 95.0 * exp(-kick_phase * 20.0)
	var kick := sin(TAU * kick_freq * t) * exp(-kick_phase * 13.0) * 0.24
	var snare_phase := fmod(beat + 0.5, 1.0)
	var noise := sin(float(index * 7919 % 104729))
	var snare := noise * exp(-snare_phase * 18.0) * (0.11 if int(floor(beat * 2.0)) % 2 == 1 else 0.025)
	var hat := noise * exp(-sixteenth * 28.0) * 0.035
	var pad := (sin(TAU * chord_root * 2.0 * t) + sin(TAU * chord_root * 2.9966 * t)) * 0.018
	var mix := (bass + arp + kick + snare + hat + pad) * drive
	mix = tanh(mix * 1.65) * 0.48
	var pan := sin(t * 0.73) * 0.12
	return Vector2(mix * (1.0 - pan), mix * (1.0 + pan))

func play_sfx(id: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if not sfx_cache.has(id):
		return
	if id == "player_hit" or id == "barrier" or id == "boss_die":
		music_duck = maxf(music_duck, 1.0)
	elif id == "phase" or id == "warning":
		music_duck = maxf(music_duck, 0.55)
	var target: AudioStreamPlayer
	for player in sfx_players:
		if not player.playing:
			target = player
			break
	if target == null:
		target = sfx_players[0]
	target.stream = sfx_cache[id]
	target.pitch_scale = clampf(pitch, 0.55, 1.8)
	target.volume_db = volume_db
	target.play()

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
	sfx_cache["boss_die"] = _make_noise(1.4, 0.42, 2.2, 48.0)

func _make_tone(freq: float, duration: float, gain: float, sweep: float, grit: float) -> AudioStreamWAV:
	var frames := int(MIX_RATE * duration)
	var bytes := PackedByteArray()
	bytes.resize(frames * 4)
	for i in frames:
		var t := float(i) / MIX_RATE
		var p := t / duration
		var current_freq := freq * lerpf(1.0, sweep, p)
		var wave := sin(TAU * current_freq * t)
		wave += sin(TAU * current_freq * 2.01 * t) * grit
		wave *= exp(-p * 5.2) * gain
		var sample := int(clampf(wave, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 4, sample)
		bytes.encode_s16(i * 4 + 2, sample)
	return _wav(bytes)

func _make_noise(duration: float, gain: float, decay: float, tone: float = 0.0) -> AudioStreamWAV:
	var frames := int(MIX_RATE * duration)
	var bytes := PackedByteArray()
	bytes.resize(frames * 4)
	var phase := 0.0
	for i in frames:
		var p := float(i) / float(frames)
		phase += TAU * tone / MIX_RATE
		var wave := rng.randf_range(-1.0, 1.0) * 0.7 + sin(phase) * 0.3
		wave *= exp(-p * decay) * gain
		var sample := int(clampf(wave, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 4, sample)
		bytes.encode_s16(i * 4 + 2, sample)
	return _wav(bytes)

func _wav(bytes: PackedByteArray) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = int(MIX_RATE)
	wav.stereo = true
	wav.data = bytes
	return wav
