class_name MusicDirector
extends Node

# Adaptive music: three orchestral layers (tension / battle / finale) playing
# in parallel, crossfaded by combat intensity. Tracks: Kevin MacLeod, CC-BY.

const MUTED := -50.0

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
	var stream: AudioStream = load(path).duplicate()
	stream.loop = true
	p.stream = stream
	p.volume_db = db
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
