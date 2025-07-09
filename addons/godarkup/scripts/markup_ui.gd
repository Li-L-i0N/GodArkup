@tool
extends Node
class_name GodArkup

# GodArkup (formerly MarkupUI) 
# Now supports <Node path="..."> instancing and <for count="..." var="idx"> loops.

var resource_map: Dictionary = {}
var property_definitions: Dictionary = {}
var resolved_properties: Dictionary = {}
var external_id_property := "ExternalIdUiMarkup"
var logger: Logger



func _init():
	logger = Logger.new()



# Entry point: load markup, parse resources, then build UI
func load_markup(path: String, signal_target: Object, _parsed_files: Array = [], passed_properties: Dictionary = {}) -> Control:
	logger.info("Starting GodArkup processing for: %s" % path)
	resource_map.clear()
	property_definitions.clear()
	resolved_properties.clear()

	var file = FileAccess.open(path, FileAccess.READ)
	if not FileAccess.file_exists(path) or file == null:
		logger.error("[GodArkup] Failed to open file: %s" % path)
		return null

	var content_string = file.get_as_text()
	file.close()
	var regex = RegEx.new()
	regex.compile("<!--[\\s\\S]*?-->")
	var cleaned_content = regex.sub(content_string, "", true)
	var buffer := cleaned_content.to_utf8_buffer()

	var parser := XMLParser.new()
	if parser.open_buffer(buffer) != OK:
		logger.error("[GodArkup] Failed to parse buffer from: %s" % path)
		return null

	# --- CONFIG OVERRIDE PASS ---
	var parser_config := XMLParser.new()
	if parser_config.open_buffer(buffer) == OK:
		while parser_config.read() == OK:
			if parser_config.get_node_type() == XMLParser.NODE_ELEMENT and parser_config.get_node_name() == "Config":
				for i in range(parser_config.get_attribute_count()):
					var name := parser_config.get_attribute_name(i)
					var value := parser_config.get_attribute_value(i)
					if name == "external_id_property":
						external_id_property = value
						logger.info("Config override: external_id_property set to '%s'" % value)
						break
				break

	# --- SEQUENTIAL PARSING LOGIC ---
	parser.seek(0) # This moves to the start AND reads the first node.

	# Helper to advance the parser to the next significant element node.
	# It checks the CURRENT node first before trying to read.
	var advance_to_next_element = func(p: XMLParser) -> bool:
		if p.get_node_type() == XMLParser.NODE_ELEMENT:
			return true
		while p.read() == OK:
			if p.get_node_type() == XMLParser.NODE_ELEMENT:
				return true
		return false

	# Phase 1: Find the first element in the file.
	if not advance_to_next_element.call(parser):
		logger.error("[GodArkup] No elements found in file: %s" % path)
		return null

	# Phase 2: Check if the first element is <Properties>.
	if parser.get_node_name() == "Properties":
		_parse_properties(parser)
		if not advance_to_next_element.call(parser):
			logger.error("[GodArkup] No UI root element found after <Properties> in %s" % path)
			return null

	# Phase 3: Check if the current element is <Resources>.
	if parser.get_node_name() == "Resources":
		_parse_resources(parser)
		if not advance_to_next_element.call(parser):
			logger.error("[GodArkup] No UI root element found after <Resources> in %s" % path)
			return null

	# Phase 4: Resolve passed properties against definitions.
	for prop_name in property_definitions:
		var prop_def = property_definitions[prop_name]
		if passed_properties.has(prop_name):
			resolved_properties[prop_name] = passed_properties[prop_name]
		else:
			resolved_properties[prop_name] = prop_def["default"]

	# Phase 5: The current element must be the root. Build the UI tree.
	var root_node = null
	if parser.get_node_type() == XMLParser.NODE_ELEMENT:
		root_node = _build_node(parser, signal_target, resolved_properties, buffer, _parsed_files)
	
	if root_node:
		logger.info("Successfully built UI from %s" % path)
	else:
		logger.error("[GodArkup] No UI root element found in %s" % path)

	return root_node



# Parse <Resources>
func _parse_resources(parser: XMLParser) -> void:
	logger.info("Parsing resources...")
	while parser.read() == OK:
		var t := parser.get_node_type()
		if t == XMLParser.NODE_ELEMENT:
			var rid := ""
			var rpath := ""
			for j in range(parser.get_attribute_count()):
				var aname := parser.get_attribute_name(j)
				var avalue := parser.get_attribute_value(j)
				if aname == "id": rid = avalue
				elif aname == "path": rpath = avalue
			if rid != "" and rpath != "":
				var res := ResourceLoader.load(rpath)
				if res:
					resource_map[rid] = res
					logger.info("Loaded resource '%s' from '%s'" % [rid, rpath])
				else:
					logger.warning("[GodArkup] Failed to load resource '%s' at '%s'" % [rid, rpath])
		elif t == XMLParser.NODE_ELEMENT_END and parser.get_node_name() == "Resources":
			logger.info("Finished parsing resources.")
			return

# Parse <Properties>
func _parse_properties(parser: XMLParser) -> void:
	logger.info("Parsing properties...")
	while parser.read() == OK:
		var t := parser.get_node_type()
		if t == XMLParser.NODE_ELEMENT and parser.get_node_name() == "Property":
			var prop_name = ""
			var prop_type = "String" # Default type
			var prop_default = ""
			for i in range(parser.get_attribute_count()):
				var aname = parser.get_attribute_name(i)
				var avalue = parser.get_attribute_value(i)
				if aname == "name": prop_name = avalue
				elif aname == "type": prop_type = avalue
				elif aname == "default": prop_default = avalue
			
			if prop_name:
				property_definitions[prop_name] = {
					"type": prop_type,
					"default": _parse_value(prop_default)
				}
				logger.info("Defined property '%s' (type: %s, default: %s)" % [prop_name, prop_type, prop_default])
			else:
				logger.warning("[GodArkup] Found <Property> tag with no 'name' attribute.")

		elif t == XMLParser.NODE_ELEMENT_END and parser.get_node_name() == "Properties":
			logger.info("Finished parsing properties.")
			return




# Recursive builder with <Node> and <for> support
func _build_node(parser: XMLParser, signal_target: Object, var_context: Dictionary, buffer: PackedByteArray, _parsed_files: Array = []) -> Control:
	var tag = parser.get_node_name()

	# 0) Explicitly ignore <Resources> tag during node building phase
	if tag == "Resources":
		if not parser.is_empty():
			while parser.read() == OK:
				if parser.get_node_type() == XMLParser.NODE_ELEMENT_END and parser.get_node_name() == "Resources":
					break
		return null

	# 1) <for count="..." var="idx">
	if tag == "for":
		return _build_for(parser, signal_target, var_context, buffer, _parsed_files)

	# 2) <Node path="..."> instancing
	if tag == "Node":
		var scene_path := ""
		for i in range(parser.get_attribute_count()):
			if parser.get_attribute_name(i) == "path":
				scene_path = parser.get_attribute_value(i)
				break
		if scene_path == "":
			logger.error("[GodArkup] <Node> missing 'path' attribute")
			return null

		var inst: Control
		# --- RECURSIVE MARKUP PARSING ---
		if scene_path.ends_with(".godarkup"):
			# Infinite recursion guard
			if scene_path in _parsed_files:
				logger.error("[GodArkup] Infinite recursion detected. Aborting parse of '%s'." % scene_path)
				return null
			
			var new_parsed_files = _parsed_files.duplicate()
			new_parsed_files.append(scene_path)
			
			# Collect attributes from the <Node> tag to pass them as properties.
			var passed_props = {}
			for i in range(parser.get_attribute_count()):
				var an = parser.get_attribute_name(i)
				if an == "path": continue
				var av = parser.get_attribute_value(i)
				passed_props[an] = _parse_value(_interpolate(av, var_context))

			# Recursively call load_markup.
			inst = GodArkup.new().load_markup(scene_path, signal_target, new_parsed_files, passed_props)
			if not inst:
				logger.error("[GodArkup] Failed to load markup from sub-file: %s" % scene_path)
				return null
		# --- STANDARD .tscn INSTANCING ---
		else:
			var packed := ResourceLoader.load(scene_path)
			if not packed or not packed is PackedScene:
				logger.error("[GodArkup] Could not load scene: %s" % scene_path)
				return null
			inst = packed.instantiate()

		# Process remaining attributes on the <Node> tag.
		# For .godarkup files, this is handled by the property system.
		# For .tscn files, we process them as standard attributes.
		if not scene_path.ends_with(".godarkup"):
			var bindings := []
			for i in range(parser.get_attribute_count()):
				var an := parser.get_attribute_name(i)
				var av := parser.get_attribute_value(i)
				if an == "path":
					continue
				_process_attr(inst, an, av, signal_target, var_context, bindings)
			_apply_bindings(bindings)

		# Skip inner subtree of the <Node> tag
		if not parser.is_empty():
			while parser.read() == OK:
				if parser.get_node_type() == XMLParser.NODE_ELEMENT_END and parser.get_node_name() == "Node":
					break
		return inst

	# 3) Fallback to standard nodes
	return _build_standard_node(parser, signal_target, var_context, buffer, _parsed_files)

# Resolve the initial value of a binding expression, e.g. "{player.score}"
func _resolve_binding_value(expr_str: String, signal_target: Object) -> Variant:
	if not (expr_str.begins_with("{") and expr_str.ends_with("}")):
		return null

	var expr := expr_str.substr(1, expr_str.length() - 2)
	var parts := expr.split(":")
	var src_prop_pair := parts[0]
	var dot_idx := src_prop_pair.find(".")
	var src_id := src_prop_pair if dot_idx == -1 else src_prop_pair.substr(0, dot_idx)
	var src_prop := "ui_value" if dot_idx == -1 else src_prop_pair.substr(dot_idx + 1)

	var src: Node = null
	match src_id:
		"owner":
			src = signal_target
		_:
			if not signal_target.is_inside_tree():
				if not Engine.is_editor_hint():
					logger.warning("[GodArkup] Cannot resolve binding '%s', owner is not in scene tree." % expr_str)
				return null
			var scene_root = signal_target.get_tree().get_current_scene()
			if not scene_root:
				if not Engine.is_editor_hint():
					logger.warning("[GodArkup] Cannot resolve binding '%s', could not find scene root." % expr_str)
				return null
			src = _find_by_external_id(scene_root, external_id_property, src_id)

	if not src:
		if not Engine.is_editor_hint():
			logger.warning("[GodArkup] Binding source '%s' not found for expression '%s'" % [src_id, expr_str])
		return null

	return src.get(src_prop)


# Loop builder: <for count="..." var="idx">
func _build_for(parser: XMLParser, signal_target: Object, var_context: Dictionary, buffer: PackedByteArray, _parsed_files: Array) -> Control:
	var container = VBoxContainer.new()
	container.name = "ForLoop"

	# 1) Read loop attributes and process bindings
	var count_val = 0
	var idx_name  = "index"
	var bindings = []

	for j in range(parser.get_attribute_count()):
		var an = parser.get_attribute_name(j)
		var av = parser.get_attribute_value(j)
		
		var val = _interpolate(av, var_context)

		if an == "count":
			if val.begins_with("{") and val.ends_with("}"):
				var resolved_val = _resolve_binding_value(val, signal_target)
				if resolved_val != null:
					count_val = int(resolved_val)
				else:
					logger.warning("[GodArkup] Could not resolve binding for 'count': %s" % val)
			else:
				count_val = int(_parse_value(val))
		elif an == "var":
			idx_name = av
		else:
			_process_attr(container, an, av, signal_target, var_context, bindings)

	_apply_bindings(bindings)

	# 2) Build the *template* structure by saving the offsets of DIRECT children.
	var template_offsets = []
	while parser.read() == OK:
		var node_type = parser.get_node_type()
		if node_type == XMLParser.NODE_ELEMENT_END and parser.get_node_name() == "for":
			break
		if node_type == XMLParser.NODE_ELEMENT:
			# This is a direct child. Store its offset.
			template_offsets.append(parser.get_node_offset())
			# CRITICAL: Skip the entire section for this child to avoid parsing its descendants.
			# This makes the template-gathering non-recursive.
			parser.skip_section()

	# 3) Now, replay the template for each loop iteration.
	for i in range(count_val):
		var local_ctx = var_context.duplicate()
		local_ctx[idx_name] = i

		for offset in template_offsets:
			var subparser = XMLParser.new()
			subparser.open_buffer(buffer)
			subparser.seek(offset) # This moves to the offset AND reads the node there.
			
			# We are now positioned on the node we want to build.
			# DO NOT call read() again here, as that would skip the node.
			if subparser.get_node_type() == XMLParser.NODE_ELEMENT:
				var child = _build_node(subparser, signal_target, local_ctx, buffer, _parsed_files)
				if child:
					container.add_child(child)

	return container



# Original node creation logic
func _build_standard_node(parser: XMLParser, signal_target: Object, var_context: Dictionary, buffer: PackedByteArray, _parsed_files: Array) -> Control:
	var tag := parser.get_node_name()
	var node := ClassDB.instantiate(tag)
	if node == null:
		logger.error("[GodArkup] Unknown node type: %s" % tag)
		return null

	node.name = tag
	# Set attributes
	var bindings = []
	# set attributes or register bindings
	for i in range(parser.get_attribute_count()):
		_process_attr(
			node,
			parser.get_attribute_name(i),
			parser.get_attribute_value(i),
			signal_target,
			var_context,
			bindings
		)

	_apply_bindings(bindings)

	# self closing
	if parser.is_empty():
		return node

	# Children
	while parser.read() == OK:
		match parser.get_node_type():
			XMLParser.NODE_ELEMENT:
				var child := _build_node(parser, signal_target, var_context, buffer, _parsed_files)
				if child:
					node.add_child(child)
			XMLParser.NODE_ELEMENT_END:
				if parser.get_node_name() == tag:
					break
	return node

func _interpolate(text: String, var_context: Dictionary) -> String:
	# Combine resolved component properties with local loop variables.
	# Loop variables take precedence over component properties in case of a name collision.
	var full_context = resolved_properties.duplicate()
	full_context.merge(var_context, true)
	full_context.merge(resource_map, false)

	if full_context.is_empty() or text.find("#{") == -1:
		return text

	var result := text
	var regex := RegEx.new()
	regex.compile("#\\{(.+?)\\}")

	for m in regex.search_all(text):
		var code = m.get_string(1).strip_edges()
		var expr := Expression.new()

		var var_names := []
		var var_values := []
		for key in full_context:
			var_names.append(str(key))
			var_values.append(full_context[key])

		if expr.parse(code, var_names) != OK:
			if not Engine.is_editor_hint():
				logger.warning("[GodArkup] Couldn't parse expression '%s'. Error: %s" % [code, expr.get_error_text()])
			continue
			
		var val = expr.execute(var_values)
		if expr.has_execute_failed():
			logger.error("[GodArkup] Expression execution failed for: '%s'. Error: %s" % [code, expr.get_error_text()])

		result = result.replace(m.get_string(0), str(val))
	return result



# Primitive value parser
func _parse_value(text: String) -> Variant:
	if text.is_valid_int(): return int(text)
	if text.is_valid_float(): return float(text)
	var l := text.strip_edges().to_lower()
	if l == "true": return true
	if l == "false": return false
	if ";" in text:
		var parts = text.split(";", false)
		if parts.size() == 2 and parts[0].is_valid_float() and parts[1].is_valid_float():
			return Vector2(parts[0].to_float(), parts[1].to_float())
	return text

# Apply binding expressions to nodes
func _apply_bindings(bindings: Array) -> void:
	for b in bindings:
		# binding is:
		# {"node": node, "prop": name, "source": source_id, "source_prop": source_prop,
		#		"signal": signal_name, "target": signal_target}

		# 1) Find the source node by ExternalIdUiMarkup
		var src: Node = null
		
		match b.source:
			"self":
				src = b.node
			"owner":
				src = b.target
			_:
				# Search in the scene for a node with matching external id
				var scene_root = b.target.get_tree().get_current_scene()
				if not scene_root:
					if not Engine.is_editor_hint():
						logger.warning("[GodArkup] Trouble finding scene root. Maybe target %s is not valid" % b.target)
					continue
				src = _find_by_external_id(scene_root, external_id_property, b.source)

		if not src:
			logger.warning("[GodArkup] Binding source '%s' not found via property '%s'" % [b.source, external_id_property])
			continue

		# Getting the value of external node when UI is created
		if b.source_prop:
			b.node.set(b.prop, src.get(b.source_prop))

		# Signal is omitted
		if not b.signal:
			continue

		# Connect its signal to update the UI property
		if not src.has_signal(b.signal):
			logger.warning("[GodArkup] Source '%s' has no signal '%s'" % [b.target, b.signal])
			continue

		var callable_lambda := func (val, prop): b.node.set(prop, val) 
		var call = callable_lambda.bind(b.prop) 
		if not src.is_connected(b.signal, call):
			src.connect(b.signal, call)

func _find_by_external_id(root: Node, property_name: String, id_val: String) -> Node:
	# Depth-first search
	var prop_val = root.get(property_name)
	if prop_val != null and prop_val == id_val:
		return root
	for child in root.get_children():
		if child is Node:
			var res = _find_by_external_id(child, property_name, id_val)
			if res:
				return res
	return null

func _get_current_attributes(parser: XMLParser) -> Dictionary:
	var result := {}
	for i in range(parser.get_attribute_count()):
		var name := parser.get_attribute_name(i)
		var value := parser.get_attribute_value(i)
		result[name] = value
	return result



func _create_fake_parser(data: Dictionary) -> XMLParser:
	# This is a hack: we create a tiny XML string and re-parse it
	var xml := "<%s" % data.name
	for k in data.attributes.keys():
		xml += " %s=\"%s\"" % [k, data.attributes[k]]
	xml += " />" if data.empty else "></%s>" % data.name

	var buffer := xml.to_utf8_buffer()
	var p := XMLParser.new()
	p.open_buffer(buffer)
	return p



func _process_attr(node: Object, name: String, raw_val: String, signal_target: Object, var_ctx: Dictionary, bindings: Array):
	var processed_val = raw_val
	if processed_val.find("#{") != -1:
		processed_val = _interpolate(processed_val, var_ctx)

	if processed_val.begins_with("{") and processed_val.ends_with("}"):
		var expr := processed_val.substr(1, processed_val.length() - 2)
		var parts := expr.split(":")
		if parts.size() == 2 or parts.size() == 1:
			var src_prop_pair := parts[0]
			var sig_name := parts[1] if parts.size() == 2 else null
			var dot_idx := src_prop_pair.find(".")
			var src_id := src_prop_pair if dot_idx == -1 else src_prop_pair.substr(0, dot_idx)
			var src_prop := "ui_value" if dot_idx == -1 else src_prop_pair.substr(dot_idx + 1)
			bindings.append({
				"node": node,
				"prop": name,
				"source": src_id,
				"source_prop": src_prop,
				"signal": sig_name,
				"target": signal_target,
			})
		else:
			logger.warning("[GodArkup] Invalid binding expression format: '%s'" % expr)
		return

	if name.begins_with("on_"):
		_wire_event(node, name, processed_val, signal_target)
		return

	var parsed = _parse_value(processed_val)
	if parsed is String and resource_map.has(parsed):
		parsed = resource_map[parsed]
	
	node.set(name, parsed)



func _wire_event(node: Object, attr_name: String, handler_str: String, signal_target: Object) -> void:
	# attr_name looks like "on_pressed"
	var sig := attr_name.substr(3)
	if not node.has_signal(sig):
		logger.warning("[GodArkup] Node '%s' has no signal '%s'" % [node.name, sig])
		return

	if "." not in handler_str:
		logger.warning("[GodArkup] Invalid handler format '%s', expected node_external_id.handler_name" % handler_str)
		return

	var parts := handler_str.split(".")
	if parts.size() != 2:
		logger.warning("[GodArkup] Invalid handler format '%s', expected node_external_id.handler_name" % handler_str)
		return

	var target_ref := parts[0]
	var method_name := parts[1]
	var handler_target: Object = null

	match target_ref:
		"self":
			handler_target = node
		"owner":
			handler_target = signal_target
		_:
			var scene_root = signal_target.get_tree().get_current_scene()
			if not scene_root:
				return
			handler_target = _find_by_external_id(scene_root, external_id_property, target_ref)

	if not handler_target:
		logger.warning("[GodArkup] Cannot find handler: %s.%s" % [target_ref, method_name])
		return
	if not handler_target.has_method(method_name):
		logger.warning("[GodArkup] Cannot find method: %s" % [method_name])
		return

	var call := Callable(handler_target, method_name)
	if not node.is_connected(sig, call):
		node.connect(sig, call)
