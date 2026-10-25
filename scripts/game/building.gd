extends Node3D
## Destructible building made of wall blocks and floor slabs.
## Blocks are rendered with MultiMesh (2 draw calls per building) and each has
## its own box collider that is disabled when the block is destroyed.
## Destruction is deterministic so every client computes the same result from
## the same explosion events (only events are synced, not geometry).
## Yukkuri Strike - created by ゆっくりP

const Mats := preload("res://scripts/game/textures.gd")

const SEG := 1.0       # wall segment width
const ROW_H := 1.0     # wall row height
const THICK := 0.32
const SLAB := 2.0

var blocks: Array = []   # {pos: Vector3 (local), size: Vector3, kind: 0 wall/1 slab, alive, shape, mm, idx, row, col, side}
var body: StaticBody3D
var mm_wall: MultiMeshInstance3D
var mm_slab: MultiMeshInstance3D
var aabb: AABB
var world: Node
var _grid := {} # "side:col:row" -> block index (walls)

func generate(rng: RandomNumberGenerator, w: int, d: int, floors: int, tint: Color, wall_only := false) -> void:
	body = StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	body.set_meta("building", self)
	var rows_per_floor := 3
	var total_rows := floors * rows_per_floor + (1 if not wall_only else 0)
	if wall_only:
		total_rows = 2
	var door_side := rng.randi() % 4
	var sides := [[Vector3(-w * 0.5, 0, -d * 0.5), Vector3(1, 0, 0), w], [Vector3(w * 0.5, 0, -d * 0.5), Vector3(0, 0, 1), d],
		[Vector3(w * 0.5, 0, d * 0.5), Vector3(-1, 0, 0), w], [Vector3(-w * 0.5, 0, d * 0.5), Vector3(0, 0, -1), d]]
	for s in 4:
		if wall_only and s % 2 == 1:
			continue
		var start: Vector3 = sides[s][0]
		var dir: Vector3 = sides[s][1]
		var n: int = sides[s][2]
		var door_col := n / 2
		for c in n:
			for r in total_rows:
				var floor_i := r / rows_per_floor
				var rr := r % rows_per_floor
				var is_parapet := r == total_rows - 1 and not wall_only
				if not wall_only and not is_parapet:
					if s == door_side and floor_i == 0 and (c == door_col or c == door_col - 1) and rr < 2:
						continue
					if rr == 1 and c > 0 and c < n - 1 and (c % 3 == 1) and not (s == door_side and floor_i == 0 and abs(c - door_col) <= 2):
						continue
				var p := start + dir * (c + 0.5) * SEG + Vector3(0, (r + 0.5) * ROW_H, 0)
				p -= Vector3(dir.z, 0, -dir.x) * 0.0
				var size := Vector3(SEG if dir.x != 0 else THICK, ROW_H, SEG if dir.z != 0 else THICK)
				if dir.x != 0:
					size.x = SEG + (THICK if c == n - 1 else 0.0)
				_grid["%d:%d:%d" % [s, c, r]] = blocks.size()
				blocks.append({"pos": p, "size": size, "kind": 0, "alive": true, "row": r, "col": c, "side": s})
	if not wall_only:
		for f in range(1, floors + 1):
			var y := f * rows_per_floor * ROW_H
			var nx := int(ceil(float(w) / SLAB))
			var nz := int(ceil(float(d) / SLAB))
			for ix in nx:
				for iz in nz:
					if f < floors and ix == 0 and iz <= 1:
						continue # stair well
					var sx := minf(SLAB, w - ix * SLAB)
					var sz := minf(SLAB, d - iz * SLAB)
					var p := Vector3(-w * 0.5 + ix * SLAB + sx * 0.5, y - 0.1, -d * 0.5 + iz * SLAB + sz * 0.5)
					blocks.append({"pos": p, "size": Vector3(sx, 0.2, sz), "kind": 1, "alive": true, "row": f * rows_per_floor, "col": -1, "side": -1})
		# stairs (indestructible ramp) for every floor transition
		for f in range(0, floors - 1):
			var ramp := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			var run := 4.2
			var rise := rows_per_floor * ROW_H
			var length := sqrt(run * run + rise * rise)
			bs.size = Vector3(1.6, 0.2, length)
			ramp.shape = bs
			var ang := atan2(rise, run)
			ramp.transform = Transform3D(Basis(Vector3.RIGHT, ang), Vector3(-w * 0.5 + 1.0, f * rise + rise * 0.5, -d * 0.5 + 0.2 + run * 0.5))
			body.add_child(ramp)
			var rm := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = bs.size
			rm.mesh = bm
			rm.material_override = Mats.concrete()
			rm.transform = ramp.transform
			add_child(rm)
		# ground floor slab (visual only, slightly above terrain)
		var gf := MeshInstance3D.new()
		var gbm := BoxMesh.new()
		gbm.size = Vector3(w, 0.3, d)
		gf.mesh = gbm
		gf.material_override = Mats.concrete()
		gf.position = Vector3(0, -0.1, 0)
		add_child(gf)
		var gcs := CollisionShape3D.new()
		var gbs := BoxShape3D.new()
		gbs.size = gbm.size
		gcs.shape = gbs
		gcs.position = gf.position
		body.add_child(gcs)

	var wall_mesh := BoxMesh.new()
	wall_mesh.size = Vector3.ONE
	var slab_mesh := BoxMesh.new()
	slab_mesh.size = Vector3.ONE
	mm_wall = _make_mm(wall_mesh, Mats.plaster())
	mm_slab = _make_mm(slab_mesh, Mats.concrete())
	var wi := 0
	var si := 0
	var nw := 0
	for b in blocks:
		if b.kind == 0:
			nw += 1
	mm_wall.multimesh.instance_count = nw
	mm_slab.multimesh.instance_count = blocks.size() - nw
	for b in blocks:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = b.size
		cs.shape = bs
		cs.position = b.pos
		body.add_child(cs)
		b.shape = cs
		var shade := 1.0 - 0.06 * float(b.row % 3 == 0) + rng.randf_range(-0.03, 0.03)
		var col := Color(tint.r * shade, tint.g * shade, tint.b * shade)
		if b.kind == 0:
			if b.row == 0:
				col = col.darkened(0.25) # grime at the base
			b.mm = mm_wall
			b.idx = wi
			mm_wall.multimesh.set_instance_transform(wi, Transform3D(Basis.from_scale(b.size), b.pos))
			mm_wall.multimesh.set_instance_color(wi, col)
			wi += 1
		else:
			b.mm = mm_slab
			b.idx = si
			mm_slab.multimesh.set_instance_transform(si, Transform3D(Basis.from_scale(b.size), b.pos))
			mm_slab.multimesh.set_instance_color(si, Color(0.8, 0.8, 0.78))
			si += 1
	aabb = AABB(Vector3(-w * 0.5 - 1, -1, -d * 0.5 - 1), Vector3(w + 2, total_rows * ROW_H + 2, d + 2))

func _make_mm(mesh: Mesh, mat: Material) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)
	return mmi

func alive_count() -> int:
	var n := 0
	for b in blocks:
		if b.alive:
			n += 1
	return n

## Destroy blocks in a sphere (world space). Returns destroyed world positions.
func explode(center: Vector3, radius: float) -> Array:
	var local := to_local(center)
	var out := []
	if not aabb.grow(radius).has_point(local):
		return out
	for b in blocks:
		if not b.alive:
			continue
		var r := radius * (0.75 if b.kind == 1 else 1.0)
		if b.pos.distance_to(local) < r:
			_kill(b, out)
	if out.size() > 0:
		_collapse(out)
	return out

func _kill(b: Dictionary, out: Array) -> void:
	b.alive = false
	b.shape.disabled = true
	b.mm.multimesh.set_instance_transform(b.idx, Transform3D(Basis.from_scale(Vector3.ZERO), b.pos))
	out.append(to_global(b.pos))

## Simple structural rule: an unsupported wall block (nothing below and no
## horizontal neighbours) falls; slabs fall when no wall block supports them.
func _collapse(out: Array) -> void:
	var changed := true
	var guard := 0
	while changed and guard < 12:
		changed = false
		guard += 1
		for b in blocks:
			if not b.alive or b.kind != 0 or b.row == 0:
				continue
			var below = _grid.get("%d:%d:%d" % [b.side, b.col, b.row - 1], -1)
			var below_alive: bool = below != -1 and blocks[below].alive
			if below_alive:
				continue
			var l = _grid.get("%d:%d:%d" % [b.side, b.col - 1, b.row], -1)
			var r = _grid.get("%d:%d:%d" % [b.side, b.col + 1, b.row], -1)
			var la: bool = l != -1 and blocks[l].alive
			var ra: bool = r != -1 and blocks[r].alive
			if not la and not ra:
				_kill(b, out)
				changed = true
