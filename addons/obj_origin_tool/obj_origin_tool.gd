@tool
extends EditorPlugin

# Dock scene and its buttons reference variables
var dock
var dock_context_label: Label
var dock_center_mass_button: Button
var dock_center_bottom_button: Button
var dock_help_button: Button

func _enter_tree():
	# Add custom tool menu in Project -> Tools
	add_tool_menu_item("Move Origin -> Center Mass", Callable(self, "_on_center_mass_selected"))
	add_tool_menu_item("Move Origin -> Center Bottom", Callable(self, "_on_center_bottom_selected"))
	add_tool_menu_item("Move Origin -> Help", Callable(self, "_on_help_selected"))
	
	# Add docked menu to the LEFT / Upper Right dock (the one with Scene and Import)
	dock = preload("res://addons/obj_origin_tool/obj_origin_tool_dock.tscn").instantiate()
	add_control_to_dock(DOCK_SLOT_LEFT_UR, dock)
	dock_context_label = dock.get_node("TopSection/Context")
	dock_center_mass_button = dock.get_node("MiddleSection/Center Mass")
	dock_center_bottom_button = dock.get_node("MiddleSection/Center Bottom")
	dock_help_button = dock.get_node("BottomSection/Help")
	
	dock_center_mass_button.pressed.connect(_on_center_mass_selected)
	dock_center_bottom_button.pressed.connect(_on_center_bottom_selected)
	dock_help_button.pressed.connect(_on_help_selected)

func _exit_tree():
	# Remove custom tool menu items
	remove_tool_menu_item("Move Origin -> Center Mass")
	remove_tool_menu_item("Move Origin -> Center Bottom")
	remove_tool_menu_item("Move Origin -> Help")
	
	# Remove the dock menu also
	remove_control_from_docks(dock)
	dock.free()

func _on_help_selected():
	var dialog = ConfirmationDialog.new()
	dialog.title = "Move Origin Help"

	var help_text = """
	Center Mass (aka Center-Center):
	Recenter the origin to the geometric center of the mesh.

	Center Bottom:
	Recenter the origin to the bottom center of the mesh, aligned with the lowest Y coordinate.
	
	How To Use:
	1. Select a .obj file in the Godot FileSystem
	
	2a. Click the "Center Mass" or "Center Bottom" button in the dock menu
	or
	2b. Project -> Tools -> Move Origin -> Center Mass or Center Bottom
	
	3. Your adjusted .obj file will be saved next to the original with "_adjusted" appended to the file name
	"""
	var label = Label.new()
	label.text = help_text.strip_edges()
	label.set_custom_minimum_size(Vector2(400, 100))

	dialog.add_child(label)

	get_tree().root.add_child(dialog)
	dialog.popup_centered()

func _process(delta: float) -> void:
	# Check if the file they have selected in the FileSystem is a .obj file
	# and adjust the labels/buttons accordingly.
	var current_file_path = get_editor_interface().get_current_path()
	var current_file_extension = get_editor_interface().get_current_path().get_extension()
	if current_file_extension == "obj":
		dock_context_label.text = "Selected Resource: \n" + current_file_path
		dock_center_mass_button.disabled = false
		dock_center_bottom_button.disabled = false
	else:
		dock_context_label.text = "\nSelect a .obj file in the Godot FileSystem"
		dock_center_mass_button.disabled = true
		dock_center_bottom_button.disabled = true

func _get_selected_file() -> String:
	var current_path = get_editor_interface().get_current_path()
	if not current_path or current_path == "":
		return ""  # No selection
	return current_path

func _on_center_mass_selected():
	var selected_file = _get_selected_file()
	if selected_file == "":
		push_error("OBJ Origin Tool:: No file selected. Please select a .obj file in the FileSystem dock.")
		return
	if not selected_file.ends_with(".obj"):
		push_error("OBJ Origin Tool:: Selected file is not an .obj file: " + selected_file)
		return
	print("OBJ Origin Tool:: Processing Center Mass for: ", selected_file)
	_process_obj_file(selected_file, false)

func _on_center_bottom_selected():
	var selected_file = _get_selected_file()
	if selected_file == "":
		push_error("OBJ Origin Tool:: No file selected. Please select a .obj file in the FileSystem dock.")
		return
	if not selected_file.ends_with(".obj"):
		push_error("OBJ Origin Tool:: Selected file is not an .obj file: " + selected_file)
		return
	print("OBJ Origin Tool:: Processing Center Bottom for: ", selected_file)
	_process_obj_file(selected_file, true)

func _process_obj_file(file_path: String, center_bottom: bool):
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("OBJ Origin Tool:: Failed to open file: " + file_path)
		return

	var lines = file.get_as_text().split("\n")
	file.close()

	var vertices = []
	for line in lines:
		if line.begins_with("v "):
			var parts = line.split(" ", true)
			var vertex = Vector3(parts[1].to_float(), parts[2].to_float(), parts[3].to_float())
			vertices.append(vertex)

	if vertices.is_empty():
		push_error("OBJ Origin Tool:: No vertex data found in the file.")
		return

	# Calculate center of mass
	var center_of_mass = Vector3.ZERO
	for vertex in vertices:
		center_of_mass += vertex
	center_of_mass /= vertices.size()

	# Translate vertices to center of mass
	for i in range(vertices.size()):
		vertices[i] -= center_of_mass

	# If "Center Bottom" is selected, shift vertices upwards
	if center_bottom:
		var min_y = INF
		for vertex in vertices:
			min_y = min(min_y, vertex.y)
		for i in range(vertices.size()):
			vertices[i].y -= min_y

	# Update the .obj file with the modified vertices
	var new_lines = []
	var vertex_index = 0
	for line in lines:
		if line.begins_with("v "):
			var vertex = vertices[vertex_index]
			new_lines.append("v %f %f %f" % [vertex.x, vertex.y, vertex.z])
			vertex_index += 1
		else:
			new_lines.append(line)

	# Save the modified .obj file
	var output_path = file_path.get_base_dir() + "/" + file_path.get_file().get_basename() + "_adjusted.obj"
	var output_file = FileAccess.open(output_path, FileAccess.WRITE)
	if not output_file:
		push_error("OBJ Origin Tool:: Failed to create output file: " + output_path)
		return

	for new_line in new_lines:
		output_file.store_line(new_line)
	output_file.close()
	
	# Scan in and import our new .obj file
	EditorInterface.get_resource_filesystem().update_file(output_path)
	EditorInterface.get_resource_filesystem().reimport_files(PackedStringArray([output_path]))

	print("OBJ Origin Tool:: Adjusted .obj file saved to: " + output_path)
