@tool
extends Node
class_name GodArkup

# GodArkup (formerly MarkupUI) 
# Now supports <Node path="..."> instancing and <for count="..." var="idx"> loops.

var resource_map: Dictionary = {}
var external_id_property := "ExternalIdUiMarkup"
var logger: Logger



func _init():
	logger = Logger.new()



# Entry point: load markup, parse resources, then build UI
func load_markup(path: String, signal_target: Object) -> Control:
	logger.info("Starting GodArkup processing for: %s" % path)
	resource_map.clear()

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

	# First pass: Config overrides
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

	# --- CORRECTED PARSING LOGIC (ACCOUNTING FOR SEEK BEHAVIOR) ---
	parser.seek(0) # This moves to the start AND reads the first node.

	# Phase 1: Skip any initial non-element nodes. The first read() was done by seek().
	# We loop in case there are multiple text/comment nodes at the start.
	while parser.get_node_type() != XMLParser.NODE_ELEMENT:
		if parser.read() != OK:
			logger.error("[GodArkup] No UI root element found in %s" % path)
			return null # Reached end of file without finding any elements.

	# Phase 2: Process the first element we found.
	var root_node = null
	if parser.get_node_type() == XMLParser.NODE_ELEMENT:
		if parser.get_node_name() == "Resources":
			_parse_resources(parser)

			# Now, find the *next* element, which must be the root.
			while parser.read() == OK:
				if parser.get_node_type() == XMLParser.NODE_ELEMENT:
					root_node = _build_node(parser, signal_target, {}, buffer)
					break # Found and built the root.
		else:
			# The first element was not <Resources>, so it must be the root.
			root_node = _build_node(parser, signal_target, {}, buffer)

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



# Recursive builder with <Node> and <for> support
func _build_node(parser: XMLParser, signal_target: Object, var_context: Dictionary, buffer: PackedByteArray) -> Control:
	var tag = parser.get_node_name()

	# 0) Explicitly ignore <Resources> tag during node building phase
	if tag == "Resources":
		# It's not a node, just a container. Skip its contents.
		if not parser.is_empty():
			while parser.read() == OK:
				if parser.get_node_type() == XMLParser.NODE_ELEMENT_END and parser.get_node_name() == "Resources":
					break
		return null

	# 1) <for count="..." var="idx">
	if tag == "for":
		return _build_for(parser, signal_target, var_context, buffer)

	# 2) <Node path="..."> instancing
	if tag == "Node":
		# 1) Grab the required path
		var scene_path := ""
		for i in range(parser.get_attribute_count()):
			if parser.get_attribute_name(i) == "path":
				scene_path = parser.get_attribute_value(i)
				break
		if scene_path == "":
			logger.error("[GodArkup] <Node> missing 'path' attribute")
			return null

		# 2) Load and instance
		var packed := ResourceLoader.load(scene_path)
		if not packed or not packed is PackedScene:
			logger.error("[GodArkup] Could not load scene: %s" % scene_path)
			return null
		var inst = packed.instantiate()

		# 3) Process remaining attributes using the common helper
		var bindings := []
		for i in range(parser.get_attribute_count()):
			var an := parser.get_attribute_name(i)
			var av := parser.get_attribute_value(i)
			if an == "path":
				continue
			_process_attr(inst, an, av, signal_target, var_context, bindings)

		# 4) Apply any property/signal bindings collected above
		_apply_bindings(bindings)

		# 5) Skip inner subtree (if someone wrote <Node ...>...</Node>)
		if not parser.is_empty():
			while parser.read() == OK:
				if parser.get_node_type() == XMLParser.NODE_ELEMENT_END and parser.get_node_name() == "Node":
					break
		return inst

	# 3) Fallback to standard nodes
	return _build_standard_node(parser, signal_target, var_context, buffer)

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
func _build_for(parser: XMLParser, signal_target: Object, var_context: Dictionary, buffer: PackedByteArray) -> Control:
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
				var child = _build_node(subparser, signal_target, local_ctx, buffer)
				if child:
					container.add_child(child)

	return container



# Original node creation logic
func _build_standard_node(parser: XMLParser, signal_target: Object, var_context: Dictionary, buffer: PackedByteArray) -> Control:
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
				var child := _build_node(parser, signal_target, var_context, buffer)
				if child:
					node.add_child(child)
			XMLParser.NODE_ELEMENT_END:
				if parser.get_node_name() == tag:
					break
	return node

func _interpolate(text: String, var_context: Dictionary) -> String:
	# No variables 
	if var_context.is_empty():
		return text

	var result := text
	var regex := RegEx.new()
	regex.compile("#\\{([^}]+)\\}")

	for m in regex.search_all(text):
		var code = m.get_string(1)			# expression inside #{ ... }
		var expr := Expression.new()

		# 1) Get variable names *and keep their order* in an Array
		var var_names := []
		var var_values := []
		for key in var_context.keys():
			var_names.append(str(key))
			var_values.append(var_context[key])
		
		# 2) Tell the parser which identifiers are legal
		if expr.parse(code, var_names) != OK:
			if not Engine.is_editor_hint():
				logger.warning("[GodArkup] Couldn't parse expression '%s'" % code)
			continue						# skip on parse error
			
		# 3) Build an Array of values in the SAME order
		for n in var_names:
			var_values.append(var_context[n])

		# 4) Evaluate the expression
		var val = expr.execute(var_values)
		if expr.has_execute_failed():
			logger.error("[GodArkup] Expression execution failed for: %s." % code)

		# 5) Replace the whole #{ ... } token
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
	# 
	if raw_val.find("#{") != -1 and not var_ctx.is_empty():
		raw_val = _interpolate(raw_val, var_ctx)

	# 
	if raw_val.begins_with("{") and raw_val.ends_with("}"):
		var expr := raw_val.substr(1, raw_val.length() - 2)
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

	# 
	if name.begins_with("on_"):
		_wire_event(node, name, raw_val, signal_target)
		return

	# 
	var parsed = _parse_value(raw_val)
	if parsed is String and resource_map.has(parsed):
		parsed = resource_map[parsed]
	if node.has_method("set"):
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
