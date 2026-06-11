extends Node

# Persistent player settings (user://settings.cfg), applied at startup.
# Exposed as the GameSettings autoload.

const PATH := "user://settings.cfg"

var sensitivity := 1.0      # mouse look multiplier
var invert_y := false
var fov := 65.0
var volume_master := 1.0    # 0..1
var volume_music := 1.0
var volume_sfx := 1.0
var quality := 2            # 0 = low, 1 = medium, 2 = high
var rumble := true
var show_fps := false
var fullscreen := true

func _ready() -> void:
	# dedicated buses so music and effects have their own sliders
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	load_settings()
	apply()

func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	sensitivity = cf.get_value("input", "sensitivity", sensitivity)
	invert_y = cf.get_value("input", "invert_y", invert_y)
	rumble = cf.get_value("input", "rumble", rumble)
	fov = cf.get_value("video", "fov", fov)
	quality = cf.get_value("video", "quality", quality)
	show_fps = cf.get_value("video", "show_fps", show_fps)
	fullscreen = cf.get_value("video", "fullscreen", fullscreen)
	volume_master = cf.get_value("audio", "master", volume_master)
	volume_music = cf.get_value("audio", "music", volume_music)
	volume_sfx = cf.get_value("audio", "sfx", volume_sfx)

func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("input", "sensitivity", sensitivity)
	cf.set_value("input", "invert_y", invert_y)
	cf.set_value("input", "rumble", rumble)
	cf.set_value("video", "fov", fov)
	cf.set_value("video", "quality", quality)
	cf.set_value("video", "show_fps", show_fps)
	cf.set_value("video", "fullscreen", fullscreen)
	cf.set_value("audio", "master", volume_master)
	cf.set_value("audio", "music", volume_music)
	cf.set_value("audio", "sfx", volume_sfx)
	cf.save(PATH)

func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume_master, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(maxf(volume_music, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(maxf(volume_sfx, 0.0001)))
	var mode := DisplayServer.window_get_mode()
	if fullscreen and mode != DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif not fullscreen and mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
