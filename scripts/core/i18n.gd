extends Node
## Registers the translation table with Godot's TranslationServer so tr() works
## everywhere, and exposes language switching.
## Yukkuri Strike - created by ゆっくりP

signal language_changed

const Strings := preload("res://i18n/strings.gd")

func _ready() -> void:
	var tables := {}
	for code in Strings.LANGS.keys():
		var t := Translation.new()
		t.locale = code
		tables[code] = t
	for key in Strings.S.keys():
		var row: Dictionary = Strings.S[key]
		for code in tables.keys():
			var text: String = row.get(code, row.get("en", key))
			tables[code].add_message(key, text)
	for t in tables.values():
		TranslationServer.add_translation(t)
	set_language(Settings.language)

func languages() -> Dictionary:
	return Strings.LANGS

func set_language(code: String) -> void:
	if code == "zh" or code == "zh_TW":
		code = "zh_CN"
	if code == "pt":
		code = "pt_BR"
	if not Strings.LANGS.has(code):
		code = "en"
	Settings.language = code
	TranslationServer.set_locale(code)
	language_changed.emit()
