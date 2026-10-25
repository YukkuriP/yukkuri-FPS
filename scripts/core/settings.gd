extends Node
## Persistent user settings + platform-aware quality presets.
## Yukkuri Strike - created by ゆっくりP

signal changed

const PATH := "user://settings.cfg"
const DEFAULT_SERVER := "wss://yukkuri-strike-server.onrender.com"
const CREATOR := "ゆっくりP"
const GAME_TITLE := "YUKKURI STRIKE"

enum Quality { LOW, MEDIUM, HIGH, ULTRA }

var language := ""
var mouse_sens := 0.12
var touch_sens := 0.25
var fov := 80.0
var invert_y := false
var quality := Quality.HIGH
var volume := 0.8
var touch_controls := -1 # -1 auto, 0 off, 1 on
var show_fps := false
var server_url := DEFAULT_SERVER
var player_name := ""

var is_mobile := false

func _ready() -> void:
	is_mobile = OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")
	quality = Quality.LOW if is_mobile else Quality.HIGH
	player_name = "Player%d" % (randi() % 9000 + 1000)
	load_settings()
	if language == "":
		language = _detect_language()
	_apply_audio()
	if "--low" in OS.get_cmdline_user_args():
		quality = Quality.LOW

func _detect_language() -> String:
	var loc := OS.get_locale()
	for code in ["zh_CN", "zh_TW", "pt_BR"]:
		if loc.begins_with(code):
			return code
	var lang := OS.get_locale_language()
	return lang if lang in ["ja", "en", "ko", "zh", "es", "fr", "de", "ru", "pt"] else "en"

func use_touch() -> bool:
	if touch_controls == -1:
		return is_mobile
	return touch_controls == 1

func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	language = cf.get_value("general", "language", language)
	mouse_sens = cf.get_value("input", "mouse_sens", mouse_sens)
	touch_sens = cf.get_value("input", "touch_sens", touch_sens)
	invert_y = cf.get_value("input", "invert_y", invert_y)
	touch_controls = cf.get_value("input", "touch_controls", touch_controls)
	fov = cf.get_value("video", "fov", fov)
	quality = cf.get_value("video", "quality", quality)
	show_fps = cf.get_value("video", "show_fps", show_fps)
	volume = cf.get_value("audio", "volume", volume)
	server_url = cf.get_value("net", "server_url", server_url)
	player_name = cf.get_value("net", "player_name", player_name)

func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("general", "language", language)
	cf.set_value("input", "mouse_sens", mouse_sens)
	cf.set_value("input", "touch_sens", touch_sens)
	cf.set_value("input", "invert_y", invert_y)
	cf.set_value("input", "touch_controls", touch_controls)
	cf.set_value("video", "fov", fov)
	cf.set_value("video", "quality", quality)
	cf.set_value("video", "show_fps", show_fps)
	cf.set_value("audio", "volume", volume)
	cf.set_value("net", "server_url", server_url)
	cf.set_value("net", "player_name", player_name)
	cf.save(PATH)
	_apply_audio()
	changed.emit()

func _apply_audio() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))

## Quality-dependent parameters used by the world/environment builders.
func q() -> Dictionary:
	match quality:
		Quality.LOW:
			return {"scale": 0.75, "shadow_dist": 60.0, "ssao": false, "ssr": false, "ssil": false,
				"vol_fog": false, "glow": true, "tex": 256, "trees": 500, "grass": 0, "view": 450.0,
				"terrain_res": 96, "debris": 12, "shadows": true, "taa": false, "fsr": true}
		Quality.MEDIUM:
			return {"scale": 1.0, "shadow_dist": 120.0, "ssao": true, "ssr": false, "ssil": false,
				"vol_fog": false, "glow": true, "tex": 512, "trees": 1200, "grass": 4000, "view": 800.0,
				"terrain_res": 160, "debris": 24, "shadows": true, "taa": false, "fsr": false}
		Quality.ULTRA:
			return {"scale": 1.0, "shadow_dist": 260.0, "ssao": true, "ssr": true, "ssil": true,
				"vol_fog": true, "glow": true, "tex": 1024, "trees": 3200, "grass": 16000, "view": 1600.0,
				"terrain_res": 256, "debris": 60, "shadows": true, "taa": true, "fsr": false}
		_:
			return {"scale": 1.0, "shadow_dist": 180.0, "ssao": true, "ssr": false, "ssil": false,
				"vol_fog": true, "glow": true, "tex": 1024, "trees": 2200, "grass": 9000, "view": 1200.0,
				"terrain_res": 224, "debris": 40, "shadows": true, "taa": true, "fsr": false}
