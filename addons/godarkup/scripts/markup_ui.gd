@tool
extends Node
class_name GodArkup

# markup_ui.gd - A markup-based UI loader with embedded resource support
# DSL supports a <Resources> section and UI elements
# Usage:
#   var ui = GodArkup.load_markup("res://path/to/ui.godarkup", self)

# Holds resources by id
var resource_map: Dictionary = {}
var external_id_property := "ExternalIdUiMarkup"

# Entry point: load markup, parse resources, then build UI
func load_markup(path: String, signal_target: Object) -> Node:
	resource_map.clear()
	var parser := XMLParser.new()
	if parser.open(path) != OK:
		push_error("[GodArkup] Failed to open file: %s" % path)
		return null
		
	# First pass: scan for <Config> element and extract external_id_property override
	var parser_config := XMLParser.new()
	if parser_config.open(path) == OK:
		while parser_config.read() == OK:
			if parser_config.get_node_type() == XMLParser.NODE_ELEMENT and parser_config.get_node_name() == "Config":
				for i in range(parser_config.get_attribute_count()):
					var name := parser_config.get_attribute_name(i)
					var value := parser_config.get_attribute_value(i)
					if name == "external_id_property":
						external_id_property = value
						break
				break
				
	# Second pass: collect <Resources> if present
	while parser.read() == OK:
		if parser.get_node_type() == XMLParser.NODE_ELEMENT and parser.get_node_name() == "Resources":
			_parse_resources(parser)
		elif parser.get_node_type() == XMLParser.NODE_ELEMENT:
			# First UI element -> build UI tree
			return _build_node(parser, signal_target)
	push_error("[GodArkup] No UI root element found in %s" % path)
	return null

# Parse <Resources> and populate resource_map by id
func _parse_resources(parser: XMLParser) -> void:
	# Assume parser at <Resources>
	while parser.read() == OK:
		var t := parser.get_node_type()
		if t == XMLParser.NODE_ELEMENT:
			var rid: String = ""
			var rpath: String = ""
			# Collect attributes id and path
			for j in range(parser.get_attribute_count()):
				var aname := parser.get_attribute_name(j)
				var avalue := parser.get_attribute_value(j)
				if aname == "id":
					rid = avalue
				elif aname == "path":
					rpath = avalue
			if rid != "" and rpath != "":
				var res := ResourceLoader.load(rpath)
				if res:
					resource_map[rid] = res
				else:
					push_warning("[GodArkup] Failed to load resource '%s' at '%s'" % [rid, rpath])
		elif t == XMLParser.NODE_ELEMENT_END and parser.get_node_name() == "Resources":
			return

# Recursive builder: create nodes, set props, connect signals, handle children
func _build_node(parser: XMLParser, signal_target: Object) -> Node:
	var tag := parser.get_node_name()
	var node := ClassDB.instantiate(tag)
	if node == null:
		push_error("[GodArkup] Unknown node type: %s" % tag)
		return null

	node.name = tag
	# Set attributes
	var bindings = []
	# set attributes or register bindings
	for i in range(parser.get_attribute_count()):
		var name := parser.get_attribute_name(i)
		var val := parser.get_attribute_value(i)
		# binding syntax {source:signal}
		# where signal should have 1 param (new value) on target node
		if val.begins_with("{") and val.ends_with("}"):
			var expr := val.substr(1, val.length() - 2)  # remove {}
			var parts := expr.split(":")
			if parts.size() == 2:
				var src_prop_pair = parts[0]  # e.g., player.health
				var signal_name = parts[1]    # e.g., health_changed
				var dot_index = src_prop_pair.find(".")
				var source_id = src_prop_pair # by default, if no '.', there's no prop
				var source_prop = "ui_value"  # default fallback
				if dot_index != -1:
					source_id = src_prop_pair.substr(0, dot_index)
					source_prop = src_prop_pair.substr(dot_index + 1)

				bindings.append({
					"node": node,
					"prop": name,             # property on the UI node
					"source": source_id,      # node to bind from
					"source_prop": source_prop, # property on the source node
					"signal": signal_name,
					"target": signal_target,
				})
			elif parts.size() == 1:
				var src_prop_pair := parts[0]
				var dot_index := src_prop_pair.find(".")
				if dot_index == -1:
					push_warning("""[GodArkup] Invalid binding expression format: '%s'.
						Expected {external_id_val([.property_name][:signal_name])}
						Use '.' for properties or ':' for signals.""" % expr)
				var source_id := src_prop_pair.substr(0, dot_index)
				var source_prop := src_prop_pair.substr(dot_index + 1)
				bindings.append({
					"node": node,
					"prop": name,             # property on the UI node
					"source": source_id,      # node to bind from
					"source_prop": source_prop, # property on the source node
					"signal": null,
					"target": signal_target,
				})
			else:
				push_warning("""[GodArkup] Invalid binding expression format: '%s'. 
					Expected {external_id_val([.property_name][:signal_name])}
					Use '.' for properties or ':' for signals.""" % expr)
		elif name.begins_with("on_"):
			var sig := name.substr(3)
			if node.has_signal(sig):
				var call := Callable(signal_target, parser.get_attribute_value(i))
				if not node.is_connected(sig, call):
					node.connect(sig, call)
		else:
			var parsed = _parse_value(val)
			if parsed is String and resource_map.has(parsed):
				parsed = resource_map[parsed]
			if node.has_method("set"):
				node.set(name, parsed)

	# self closing
	if parser.is_empty():
		_apply_bindings(bindings)
		return node

	# Children
	while parser.read() == OK:
		match parser.get_node_type():
			XMLParser.NODE_ELEMENT:
				var child := _build_node(parser, signal_target)
				if child:
					node.add_child(child)
			XMLParser.NODE_ELEMENT_END:
				break
	return node

# Convert primitive types or return string/id
func _parse_value(text: String) -> Variant:
	if text.is_valid_int():
		return int(text)
	if text.is_valid_float():
		return float(text)
	var l := text.strip_edges().to_lower()
	if l == "true":
		return true
	if l == "false":
		return false
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
		# Use current scene root for search
		var scene_root = b.target.get_tree().get_current_scene()
		if not scene_root:
			continue
		src = _find_by_external_id(scene_root, external_id_property, b.source)

		if not src:
			push_warning("[GodArkup] Binding source '%s' not found via property '%s'" % [b.source, external_id_property])
			continue

		# Getting the value of external node when UI is created
		if b.source_prop:
			b.node.set(b.prop, src.get(b.source_prop))

		# Signal is omitted
		if not b.signal:
			continue

		# Connect its signal to update the UI property
		if not src.has_signal(b.signal):
			push_warning("Source '%s' has no signal '%s'" % [b.target, b.signal])
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
