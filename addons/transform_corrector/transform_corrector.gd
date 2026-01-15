@tool
extends EditorPlugin

var inspector_plugin: EditorInspectorPlugin
var precision: int = 6
var selected_nodes: Array[Node] = []
var last_transforms: Dictionary = {}

func _enter_tree():
	inspector_plugin = TransformCorrectorInspectorPlugin.new()
	inspector_plugin.precision = precision
	add_inspector_plugin(inspector_plugin)
	
	# Add settings
	if not ProjectSettings.has_setting("transform_corrector/precision"):
		ProjectSettings.set_setting("transform_corrector/precision", 6)
		ProjectSettings.set_initial_value("transform_corrector/precision", 6)
		ProjectSettings.add_property_info({
			"name": "transform_corrector/precision",
			"type": TYPE_INT,
			"hint": PROPERTY_HINT_RANGE,
			"hint_string": "1,10,1"
		})
	
	# Connect to scene changes
	get_editor_interface().get_selection().selection_changed.connect(_on_selection_changed)

func _exit_tree():
	remove_inspector_plugin(inspector_plugin)
	get_editor_interface().get_selection().selection_changed.disconnect(_on_selection_changed)

func _process(_delta):
	# Monitor selected nodes for transform changes
	for node in selected_nodes:
		if not is_instance_valid(node):
			continue
		
		if node is Node3D:
			_check_and_correct_node3d(node)
		elif node is Node2D:
			_check_and_correct_node2d(node)

func _on_selection_changed():
	selected_nodes.clear()
	last_transforms.clear()
	
	var selection = get_editor_interface().get_selection()
	selected_nodes = selection.get_selected_nodes()
	
	# Store initial transforms
	for node in selected_nodes:
		if node is Node3D:
			last_transforms[node] = {
				"position": node.position,
				"rotation": node.rotation,
				"scale": node.scale
			}
		elif node is Node2D:
			last_transforms[node] = {
				"position": node.position,
				"rotation": node.rotation,
				"scale": node.scale
			}

func _check_and_correct_node3d(node: Node3D):
	var snap_step = pow(10.0, -precision)
	var changed = false
	
	# Check position
	var corrected_pos = Vector3(
		snappedf(node.position.x, snap_step),
		snappedf(node.position.y, snap_step),
		snappedf(node.position.z, snap_step)
	)
	if not node.position.is_equal_approx(corrected_pos):
		node.position = corrected_pos
		changed = true
	
	# Check rotation
	var corrected_rot = Vector3(
		snappedf(node.rotation.x, snap_step),
		snappedf(node.rotation.y, snap_step),
		snappedf(node.rotation.z, snap_step)
	)
	if not node.rotation.is_equal_approx(corrected_rot):
		node.rotation = corrected_rot
		changed = true
	
	# Check scale
	var corrected_scale = Vector3(
		snappedf(node.scale.x, snap_step),
		snappedf(node.scale.y, snap_step),
		snappedf(node.scale.z, snap_step)
	)
	if not node.scale.is_equal_approx(corrected_scale):
		node.scale = corrected_scale
		changed = true
	
	if changed:
		# Update the inspector
		node.notify_property_list_changed()

func _check_and_correct_node2d(node: Node2D):
	var snap_step = pow(10.0, -precision)
	var changed = false
	
	# Check position
	var corrected_pos = Vector2(
		snappedf(node.position.x, snap_step),
		snappedf(node.position.y, snap_step)
	)
	if not node.position.is_equal_approx(corrected_pos):
		node.position = corrected_pos
		changed = true
	
	# Check rotation
	var corrected_rot = snappedf(node.rotation, snap_step)
	if not is_equal_approx(node.rotation, corrected_rot):
		node.rotation = corrected_rot
		changed = true
	
	# Check scale
	var corrected_scale = Vector2(
		snappedf(node.scale.x, snap_step),
		snappedf(node.scale.y, snap_step)
	)
	if not node.scale.is_equal_approx(corrected_scale):
		node.scale = corrected_scale
		changed = true
	
	if changed:
		# Update the inspector
		node.notify_property_list_changed()

class TransformCorrectorInspectorPlugin extends EditorInspectorPlugin:
	var precision: int = 6
	
	func _can_handle(object: Object) -> bool:
		return object is Node3D or object is Node2D
	
	func _parse_property(object: Object, type: Variant.Type, name: String, hint_type: PropertyHint, hint_string: String, usage_flags: int, wide: bool) -> bool:
		if name in ["position", "rotation", "rotation_degrees", "scale", "global_position", "global_rotation", "global_rotation_degrees"]:
			var property_editor = TransformPropertyEditor.new()
			property_editor.precision = precision
			add_property_editor(name, property_editor)
			return true
		return false

class TransformPropertyEditor extends EditorProperty:
	var precision: int = 6
	var updating: bool = false
	var spin_boxes: Array[EditorSpinSlider] = []
	var container: HBoxContainer
	var axis_labels: Array[String] = ["X", "Y", "Z"]
	var axis_colors: Array[Color] = [
		Color(0.732, 0.458, 0.447, 1.0),  # Red for X
		Color(0.632, 0.797, 0.503, 1.0),  # Green for Y
		Color(0.38, 0.549, 0.674, 1.0)   # Blue for Z
	]
	
	func _init():
		container = HBoxContainer.new()
		container.add_theme_constant_override("separation", 4)
		add_child(container)
		
		set_bottom_editor(container)
		
		# Create spin boxes with labels for x, y, z (or x, y for 2D)
		for i in range(3):
			var axis_container = HBoxContainer.new()
			axis_container.add_theme_constant_override("separation", 2)
			
			# Add colored axis label
			var label = Label.new()
			label.text = axis_labels[i]
			label.add_theme_color_override("font_color", axis_colors[i])
			label.custom_minimum_size.x = 12
			axis_container.add_child(label)
			
			# Add spin box
			var spin = EditorSpinSlider.new()
			spin.flat = true
			spin.hide_slider = false
			spin.step = 0.001
			spin.custom_minimum_size.x = 70
			spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			spin.value_changed.connect(_on_value_changed.bind(i))
			spin_boxes.append(spin)
			axis_container.add_child(spin)
			
			container.add_child(axis_container)
	
	func _update_property():
		if updating:
			return
		
		var current_value = get_edited_object().get(get_edited_property())
		
		if current_value is Vector3:
			_update_vector3(current_value)
		elif current_value is Vector2:
			_update_vector2(current_value)
			spin_boxes[2].hide()
	
	func _update_vector3(vec: Vector3):
		var corrected = Vector3(
			snappedf(vec.x, pow(10.0, -precision)),
			snappedf(vec.y, pow(10.0, -precision)),
			snappedf(vec.z, pow(10.0, -precision))
		)
		
		updating = true
		spin_boxes[0].value = corrected.x
		spin_boxes[1].value = corrected.y
		spin_boxes[2].value = corrected.z
		spin_boxes[2].show()
		updating = false
		
		# Apply correction if values differ
		if not vec.is_equal_approx(corrected):
			get_edited_object().set(get_edited_property(), corrected)
	
	func _update_vector2(vec: Vector2):
		var corrected = Vector2(
			snappedf(vec.x, pow(10.0, -precision)),
			snappedf(vec.y, pow(10.0, -precision))
		)
		
		updating = true
		spin_boxes[0].value = corrected.x
		spin_boxes[1].value = corrected.y
		updating = false
		
		# Apply correction if values differ
		if not vec.is_equal_approx(corrected):
			get_edited_object().set(get_edited_property(), corrected)
	
	func _on_value_changed(value: float, index: int):
		if updating:
			return
		
		var current_value = get_edited_object().get(get_edited_property())
		var corrected_value = snappedf(value, pow(10.0, -precision))
		
		if current_value is Vector3:
			var new_vec = current_value
			new_vec[index] = corrected_value
			emit_changed(get_edited_property(), new_vec)
		elif current_value is Vector2:
			var new_vec = current_value
			new_vec[index] = corrected_value
			emit_changed(get_edited_property(), new_vec)
