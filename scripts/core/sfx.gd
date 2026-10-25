extends Node
## Procedurally synthesized sound effects (no external audio assets needed).
## Yukkuri Strike - created by ゆっくりP

const RATE := 22050
var streams := {}
var _pool: Array[AudioStreamPlayer] = []

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	streams["ar"] = _gunshot(rng, 0.42, 95.0, 0.55, 0.9)
	streams["smg"] = _gunshot(rng, 0.30, 120.0, 0.35, 0.8)
	streams["dmr"] = _gunshot(rng, 0.9, 70.0, 0.9, 1.0)
	streams["rpg"] = _gunshot(rng, 0.7, 50.0, 0.5, 0.6)
	streams["explosion"] = _explosion(rng, 2.2)
	streams["hit"] = _tone(1800.0, 0.05, 0.5, 2600.0)
	streams["kill"] = _tone(900.0, 0.18, 0.5, 1400.0)
	streams["click"] = _tone(2400.0, 0.025, 0.35, 1200.0)
	streams["reload"] = _clacks(rng, [0.0, 0.35, 0.9, 1.1])
	streams["empty"] = _tone(3000.0, 0.03, 0.4, 2000.0)
	streams["step"] = _noise_burst(rng, 0.09, 0.25, 0.08)
	streams["whiz"] = _whiz(rng)
	streams["impact"] = _noise_burst(rng, 0.12, 0.5, 0.35)
	streams["debris"] = _noise_burst(rng, 0.6, 0.6, 0.05)
	streams["engine"] = _engine()
	for i in 12:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)

func play(name: String, volume_db := 0.0, pitch := 1.0) -> void:
	if not streams.has(name):
		return
	for p in _pool:
		if not p.playing:
			p.stream = streams[name]
			p.volume_db = volume_db
			p.pitch_scale = pitch * randf_range(0.96, 1.04)
			p.play()
			return

func play_at(name: String, pos: Vector3, parent: Node, volume_db := 0.0, max_dist := 600.0) -> void:
	if not streams.has(name) or parent == null or not parent.is_inside_tree():
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = streams[name]
	p.volume_db = volume_db
	p.max_distance = max_dist
	p.unit_size = 12.0
	p.pitch_scale = randf_range(0.93, 1.06)
	p.attenuation_filter_cutoff_hz = 3500.0
	parent.add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)

func _make(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = samples.size()
	return s

func _gunshot(rng: RandomNumberGenerator, length: float, thump_hz: float, tail: float, gain: float) -> AudioStreamWAV:
	var n := int(RATE * length)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		lp += (noise - lp) * 0.35
		lp2 += (noise - lp2) * 0.06
		var crack := noise * exp(-t * 90.0)
		var body := lp * exp(-t * 18.0)
		var tail_n := lp2 * exp(-t / maxf(tail, 0.05) * 3.0) * 1.6
		var thump := sin(TAU * thump_hz * t * (1.0 - t * 0.8)) * exp(-t * 22.0)
		out[i] = (crack * 0.9 + body * 0.8 + tail_n + thump * 0.9) * gain
	return _make(out)

func _explosion(rng: RandomNumberGenerator, length: float) -> AudioStreamWAV:
	var n := int(RATE * length)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		lp += (noise - lp) * 0.08
		lp2 += (noise - lp2) * 0.015
		var boom := sin(TAU * 38.0 * t * (1.0 - t * 0.3)) * exp(-t * 4.0)
		var rumble := lp2 * exp(-t * 1.6) * 5.0
		var crack := lp * exp(-t * 12.0) * 1.5
		out[i] = clampf(boom * 0.9 + rumble + crack, -1.0, 1.0)
	return _make(out)

func _tone(hz: float, length: float, gain: float, end_hz: float) -> AudioStreamWAV:
	var n := int(RATE * length)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / n
		ph += TAU * lerpf(hz, end_hz, t) / RATE
		out[i] = sin(ph) * gain * (1.0 - t) * minf(1.0, t * 40.0)
	return _make(out)

func _noise_burst(rng: RandomNumberGenerator, length: float, gain: float, lp_k: float) -> AudioStreamWAV:
	var n := int(RATE * length)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / n
		lp += (rng.randf_range(-1.0, 1.0) - lp) * lp_k
		out[i] = lp * gain * pow(1.0 - t, 2.0) * (3.0 if lp_k < 0.1 else 1.0)
	return _make(out)

func _clacks(rng: RandomNumberGenerator, times: Array) -> AudioStreamWAV:
	var n := int(RATE * 1.3)
	var out := PackedFloat32Array()
	out.resize(n)
	for t0 in times:
		var s := int(t0 * RATE)
		for j in int(RATE * 0.05):
			if s + j < n:
				var tt := float(j) / RATE
				out[s + j] += (rng.randf_range(-1, 1) * 0.5 + sin(TAU * 1700.0 * tt) * 0.4) * exp(-tt * 120.0)
	return _make(out)

func _whiz(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var n := int(RATE * 0.25)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / n
		lp += (rng.randf_range(-1, 1) - lp) * 0.5
		out[i] = (lp * 0.4 + sin(TAU * lerpf(3200.0, 1400.0, t) * float(i) / RATE) * 0.15) * sin(PI * t)
	return _make(out)

func _engine() -> AudioStreamWAV:
	var n := RATE # 1 second loop
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var v := sin(TAU * 45.0 * t) * 0.5 + sin(TAU * 90.0 * t) * 0.25 + sin(TAU * 135.0 * t) * 0.12
		v += signf(sin(TAU * 22.5 * t)) * 0.08
		out[i] = v * 0.5
	return _make(out, true)
