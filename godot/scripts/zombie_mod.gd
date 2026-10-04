extends SkeletonModifier3D
# Оторванная рука/нога зомби: кость сжимается в ноль (после анимации).
var z

func _process_modification() -> void:
	if z == null:
		return
	var skel := get_skeleton()
	for part in z.lost:
		var bn: String = {"armL": "LeftArm", "armR": "RightArm", "legL": "LeftLeg", "legR": "RightLeg"}[part]
		var i := skel.find_bone("mixamorig_" + bn)
		if i >= 0:
			var g := skel.get_bone_global_pose(i)
			g.basis = g.basis * Basis.from_scale(Vector3(0.001, 0.001, 0.001))
			skel.set_bone_global_pose(i, g)
