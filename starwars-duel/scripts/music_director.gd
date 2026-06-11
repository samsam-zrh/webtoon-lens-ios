class_name MusicDirector
extends Node

# Adaptive music: three orchestral layers (tension / battle / finale) playing
# in parallel, crossfaded by combat intensity. Tracks: Kevin MacLeod, CC-BY.

const MUTED := -50.0

# Custom soundtrack: players can drop their own files (personal use) in a
# "music" folder next to the game executable, or in user://music/. Files can
# use the exact slot names (menu/tension/battle/finale .mp3/.ogg/.wav), or
# ANY name: keywords are matched, and leftovers fill the remaining slots.
const SLOT_KEYWORDS := {
	"menu": ["menu", "main", "title"],
	"battle": ["battle", "asteroid", "field", "combat", "fight", "march"],
	"finale": ["finale", "final", "force", "duel", "throne"],
	"tension": ["tension", "ambient", "calm", "imperial", "dark"],
}
static var _assignments: Dictionary = {}
static var _scanned := false

static func _scan() -> void:
	if _scanned:
		return
	_scanned = true
	var files: Array = []
	for dir in [OS.get_executable_path().get_base_dir() + "/music", "user://music", "res://assets/custom_music"]:
		var da := DirAccess.open(dir)
		if da == null:
			continue
		var seen: Array = []
		for f in da.get_files():
			var name := f
			# in exported builds, imported audio appears as .import/.remap stubs
			if name.ends_with(".import") or name.ends_with(".remap"):
				name = name.get_basename()
			if name.get_extension().to_lower() in ["mp3", "ogg", "wav"] and name not in seen:
				seen.append(name)
				files.append(dir + "/" + name)
	if files.is_empty():
		return
	var taken: Array = []
	# pass 1: exact slot names, pass 2: keywords, pass 3: leftovers in order
	for slot in ["menu", "battle", "finale", "tension"]:
		for path: String in files:
			if path in taken:
				continue
			if path.get_file().get_basename().to_lower() == slot:
				_assignments[slot] = path
				taken.append(path)
				break
	for slot in ["menu", "battle", "finale", "tension"]:
		if _assignments.has(slot):
			continue
		for path: String in files:
			if path in taken:
				continue
			var lower: String = path.get_file().to_lower()
			for kw: String in SLOT_KEYWORDS[slot]:
				if kw in lower:
					_assignments[slot] = path
					taken.append(path)
					break
			if _assignments.has(slot):
				break
	for slot in ["menu", "battle", "finale", "tension"]:
		if _assignments.has(slot):
			continue
		for path: String in files:
			if path not in taken:
				_assignments[slot] = path
				taken.append(path)
				break
	for slot in _assignments:
		print("Musique personnalisée [", slot, "] : ", _assignments[slot].get_file())

static func detected_count() -> int:
	_scan()
	return _assignments.size()

static func external_stream(slot: String) -> AudioStream:
	_scan()
	if not _assignments.has(slot):
		return null
	var path: String = _assignments[slot]
	var stream: AudioStream
	if path.begins_with("res://"):
		# bundled track: goes through the imported-resource pipeline
		stream = load(path)
		if stream != null:
			stream = stream.duplicate()
			if "loop" in stream:
				stream.loop = true
			elif stream is AudioStreamWAV:
				stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
				stream.loop_end = stream.data.size() / 2
		return stream
	match path.get_extension().to_lower():
		"mp3":
			var mp3 := AudioStreamMP3.new()
			mp3.data = FileAccess.get_file_as_bytes(path)
			mp3.loop = true
			stream = mp3
		"ogg":
			stream = AudioStreamOggVorbis.load_from_file(path)
			if stream != null:
				stream.loop = true
		"wav":
			stream = AudioStreamWAV.load_from_file(path)
	return stream

var _tension: AudioStreamPlayer
var _battle: AudioStreamPlayer
var _finale: AudioStreamPlayer
var _arena: GroundArena
var _heat := 0.0  # recent-combat accumulator

func setup(arena: GroundArena) -> void:
	_arena = arena
	_tension = _layer("res://assets/audio/music_tension.mp3", -14.0)
	_battle = _layer("res://assets/audio/music_battle.mp3", MUTED)
	_finale = _layer("res://assets/audio/music_finale.mp3", MUTED)

func _layer(path: String, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	var stream: AudioStream = external_stream(path.get_file().get_basename().trim_prefix("music_"))
	if stream == null and ResourceLoader.exists(path):
		stream = load(path).duplicate()
		stream.loop = true
	if stream == null and ResourceLoader.exists("res://assets/audio/music_tension.mp3"):
		stream = load("res://assets/audio/music_tension.mp3").duplicate()
		stream.loop = true
	if stream == null:
		add_child(p)
		return p
	p.stream = stream
	p.volume_db = db
	p.bus = "Music"
	add_child(p)
	p.play()
	return p

func combat_event(amount := 1.0) -> void:
	_heat = clampf(_heat + amount, 0.0, 6.0)

func _process(delta: float) -> void:
	if _arena == null or _arena.player == null:
		return
	_heat = maxf(0.0, _heat - delta * 0.5)
	var p := _arena.player
	var e := _arena.enemy
	var dist := p.global_position.distance_to(e.global_position)
	var fighting := (dist < 10.0 and p.controls_enabled) or _heat > 0.5
	var low_hp: float = minf(p.hp / p.cfg["hp"], e.hp / e.cfg["hp"])
	var finale := fighting and low_hp < 0.35
	var ended: bool = _arena._ended

	var t_target := -14.0
	var b_target := MUTED
	var f_target := MUTED
	if finale or ended:
		t_target = MUTED
		b_target = MUTED
		f_target = -11.0
	elif fighting:
		t_target = -24.0
		b_target = -12.0

	_fade(_tension, t_target, delta)
	_fade(_battle, b_target, delta)
	_fade(_finale, f_target, delta)

func _fade(p: AudioStreamPlayer, target: float, delta: float) -> void:
	# fade in faster than out so the action hits immediately
	var rate := 16.0 if target > p.volume_db else 7.0
	p.volume_db = move_toward(p.volume_db, target, rate * delta)
