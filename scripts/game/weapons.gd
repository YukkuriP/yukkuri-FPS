extends RefCounted
## Weapon definitions. Ballistics are physically simulated (muzzle velocity,
## gravity, quadratic drag) - see ballistics.gd.
## Yukkuri Strike - created by ゆっくりP

const ORDER := ["ar", "smg", "dmr", "rpg"]

const DATA := {
	"ar": {"name": "W_AR", "dmg": 30.0, "rpm": 700.0, "vel": 880.0, "drag": 0.00085, "mag": 30, "reserve": 210, "reload": 2.1,
		"auto": true, "spread_hip": 2.0, "spread_ads": 0.12, "recoil": Vector2(1.05, 0.45), "ads_fov": 0.72, "scope": false,
		"sound": "ar", "tracer_every": 3, "falloff": [60.0, 420.0, 0.65], "mult_head": 2.0},
	"smg": {"name": "W_SMG", "dmg": 22.0, "rpm": 920.0, "vel": 410.0, "drag": 0.0016, "mag": 34, "reserve": 238, "reload": 1.7,
		"auto": true, "spread_hip": 2.6, "spread_ads": 0.4, "recoil": Vector2(0.75, 0.55), "ads_fov": 0.82, "scope": false,
		"sound": "smg", "tracer_every": 3, "falloff": [25.0, 160.0, 0.5], "mult_head": 1.8},
	"dmr": {"name": "W_DMR", "dmg": 96.0, "rpm": 48.0, "vel": 860.0, "drag": 0.00035, "mag": 5, "reserve": 35, "reload": 3.0,
		"auto": false, "spread_hip": 4.5, "spread_ads": 0.0, "recoil": Vector2(5.5, 1.2), "ads_fov": 0.18, "scope": true,
		"sound": "dmr", "tracer_every": 1, "falloff": [400.0, 1400.0, 0.85], "mult_head": 2.5},
	"rpg": {"name": "W_RPG", "dmg": 160.0, "rpm": 30.0, "vel": 95.0, "drag": 0.0, "mag": 1, "reserve": 5, "reload": 3.2,
		"auto": false, "spread_hip": 1.5, "spread_ads": 0.3, "recoil": Vector2(4.0, 1.0), "ads_fov": 0.7, "scope": false,
		"sound": "rpg", "tracer_every": 0, "rocket": true, "radius": 7.5, "gravity": 0.25, "falloff": [9999.0, 9999.0, 1.0], "mult_head": 1.0},
}

const GRENADE := {"dmg": 140.0, "radius": 7.0, "fuse": 3.2, "count": 3}

static func get_w(id: String) -> Dictionary:
	return DATA.get(id, DATA["ar"])

static func index_of(id: String) -> int:
	return ORDER.find(id)
