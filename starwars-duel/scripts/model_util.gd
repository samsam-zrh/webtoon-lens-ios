class_name ModelUtil

# Loads a glTF scene, recenters it and scales it so its longest dimension
# equals target_len. Returns a wrapper Node3D ready to be parented.

static func load_model(path: String, target_len: float, extra_rot_y: float = 0.0) -> Node3D:
	var packed: PackedScene = load(path)
	var inst: Node3D = packed.instantiate()
	var wrapper := Node3D.new()
	wrapper.name = "Model"
	var inner := Node3D.new()
	inner.name = "Inner"
	wrapper.add_child(inner)
	inner.add_child(inst)

	var aabb := compute_aabb(inst, Transform3D.IDENTITY)
	if aabb.size.length() > 0.0001:
		var longest: float = max(aabb.size.x, max(aabb.size.y, aabb.size.z))
		var s := target_len / longest
		inner.scale = Vector3.ONE * s
		var center := aabb.get_center() * s
		inner.position = -center
	wrapper.rotation.y = extra_rot_y
	return wrapper

static func compute_aabb(node: Node, xform: Transform3D) -> AABB:
	var result := AABB()
	var has := false
	var stack: Array = [[node, xform]]
	while not stack.is_empty():
		var top: Array = stack.pop_back()
		var n: Node = top[0]
		var xf: Transform3D = top[1]
		if n is Node3D:
			xf = xf * (n as Node3D).transform
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh != null:
				var local := mi.mesh.get_aabb()
				var world := xf * local
				if has:
					result = result.merge(world)
				else:
					result = world
					has = true
		for c in n.get_children():
			stack.push_back([c, xf])
	return result
