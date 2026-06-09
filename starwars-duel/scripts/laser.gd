class_name Laser
extends Node3D

# A laser bolt: emissive capsule + light, moved manually each physics frame.
# Hits are segment-vs-sphere tests against the opposing ship and asteroids.

var shooter: Ship
var dir := Vector3.FORWARD
var color := Color.RED
var damage := 8.0
var speed := 320.0
var life := 2.6

func setup(p_shooter: Ship, origin: Vector3, p_dir: Vector3, p_color: Color, p_damage: float, p_speed: float) -> void:
	shooter = p_shooter
	dir = p_dir.normalized()
	color = p_color
	damage = p_damage
	speed = p_speed
	position = origin
	look_at_from_position(origin, origin + dir, Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT)

func _ready() -> void:
	# Hot white core
	var core := CapsuleMesh.new()
	core.radius = 0.09
	core.height = 5.5
	var core_mat := StandardMaterial3D.new()
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.albedo_color = Color(1, 1, 1)
	core_mat.emission_enabled = true
	core_mat.emission = color.lerp(Color.WHITE, 0.6)
	core_mat.emission_energy_multiplier = 8.0
	core.material = core_mat
	var core_mi := MeshInstance3D.new()
	core_mi.mesh = core
	core_mi.rotation.x = PI / 2.0  # capsule is Y-aligned; bolt flies along -Z
	add_child(core_mi)

	# Colored halo around the core
	var halo := CapsuleMesh.new()
	halo.radius = 0.30
	halo.height = 6.0
	var halo_mat := StandardMaterial3D.new()
	halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_mat.albedo_color = Color(color.r, color.g, color.b, 0.30)
	halo_mat.emission_enabled = true
	halo_mat.emission = color
	halo_mat.emission_energy_multiplier = 3.0
	halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo.material = halo_mat
	var halo_mi := MeshInstance3D.new()
	halo_mi.mesh = halo
	halo_mi.rotation.x = PI / 2.0
	add_child(halo_mi)

	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 1.8
	light.omni_range = 10.0
	add_child(light)

func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	var from := global_position
	var to := from + dir * speed * delta
	global_position = to

	# Hit the opposing ship?
	var target: Ship = shooter.enemy
	if target != null and target.alive:
		if _segment_hits_sphere(from, to, target.global_position, target.collision_radius):
			target.take_damage(damage, shooter)
			_spawn_spark(target.global_position + (from - target.global_position).normalized() * target.collision_radius * 0.7)
			queue_free()
			return

	# Hit an asteroid?
	var arena := shooter.arena
	if arena != null and "asteroids" in arena:
		for a in arena.asteroids:
			if _segment_hits_sphere(from, to, a["pos"], a["radius"]):
				_spawn_spark(to)
				queue_free()
				return

func _segment_hits_sphere(a: Vector3, b: Vector3, center: Vector3, radius: float) -> bool:
	var ab := b - a
	var t := 0.0
	var ab_len2 := ab.length_squared()
	if ab_len2 > 0.000001:
		t = clampf((center - a).dot(ab) / ab_len2, 0.0, 1.0)
	var closest := a + ab * t
	return closest.distance_squared_to(center) <= radius * radius

func _spawn_spark(at: Vector3) -> void:
	var p := GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 14.0
	mat.initial_velocity_max = 30.0
	mat.gravity = Vector3.ZERO
	mat.scale_min = 0.2
	mat.scale_max = 0.5
	mat.color = color
	mat.damping_min = 8.0
	mat.damping_max = 14.0
	var dm := SphereMesh.new()
	dm.radius = 0.12
	dm.height = 0.24
	var dmm := StandardMaterial3D.new()
	dmm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmm.albedo_color = color
	dmm.emission_enabled = true
	dmm.emission = color
	dmm.emission_energy_multiplier = 4.0
	dm.material = dmm
	p.draw_pass_1 = dm
	p.process_material = mat
	p.amount = 24
	p.lifetime = 0.5
	p.one_shot = true
	p.emitting = true
	p.position = at
	var arena := shooter.arena
	if arena != null:
		arena.add_child(p)
		var t := arena.get_tree().create_timer(1.2)
		t.timeout.connect(func() -> void:
			if is_instance_valid(p):
				p.queue_free())
