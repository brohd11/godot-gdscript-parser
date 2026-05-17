const GDScriptParser = preload("res://addons/addon_lib/brohd/alib_runtime/utils/gdscript/parser/gdscript_parser.gd")
const Keys = GDScriptParser.Keys

var member_stack:Array = []

var find_origin:bool = false

var first_expression:String = "" # think this is unused now

var _active_expressions:Dictionary = {}
var _resolved_expressions:Dictionary = {}

func has_expression(expression:String) -> bool:
	return _active_expressions.has(expression)

func start_expression(expression:String) -> void:
	if _active_expressions.is_empty():
		first_expression = expression
	_active_expressions[expression] = true

func finish_expression(expression:String, resolved:String) -> void:
	_active_expressions.erase(expression)
	if _active_expressions.is_empty():
		first_expression = ""
	_resolved_expressions[expression] = resolved


func expression_resolved(expression:String) -> bool:
	return _resolved_expressions.has(expression)

func get_resolved_expression(expression:String) -> String:
	return _resolved_expressions.get(expression)


func is_empty() -> bool:
	return _active_expressions.is_empty()

func add_to_member_stack(string:String) -> void:
	if not string in member_stack:
		member_stack.append(string)


static func get_stack_string(member_name:String, full_result:String, class_obj:GDScriptParser.ParserClass, local_vars:Dictionary) -> String:
	var stack_string:String = class_obj.get_script_class_path()
	var member_string:String = member_name
	if local_vars.has(member_name):
		var local_var_data:Variant = local_vars.get(member_name)
		member_string = "local(%s-%s)" % [member_name, local_var_data.get(Keys.LINE_INDEX)]
	
	stack_string = stack_string + "::" + member_string + Keys.MEMBER_STACK_DELIM + full_result.get_slice(Keys.MEMBER_INFER_DELIM, 1)
	return stack_string

#! keys i-GDScriptParser.resolve_expression_to_type_rich;
static func get_dependencies_from_member_stack(type_rich:Dictionary) -> Dictionary:
	return get_dependencies_from_type_rich(type_rich)

#! keys i-GDScriptParser.resolve_expression_to_type_rich;
static func get_dependencies_from_type_rich(type_rich:Dictionary) -> Dictionary:
	var deps:Dictionary = {}
	for string:String in type_rich.member_stack:
		#if not GDScriptParser.Utils.is_absolute_path(string):
			#continue
		var member_sides:PackedStringArray = string.split(Keys.MEMBER_STACK_DELIM, false)
		for side:String in member_sides:
			if not GDScriptParser.Utils.is_absolute_path(side):
				continue
			var script_data:Array[String] = GDScriptParser.Utils.type_path_get_script_data(side)
			var main_path:String = script_data[0]
			if not deps.has(main_path):
				deps[main_path] = FileAccess.get_modified_time(main_path)
	
	if GDScriptParser.Utils.is_absolute_path(type_rich.origin):
		var script_data:Array[String] = GDScriptParser.Utils.type_path_get_script_data(type_rich.origin)
		var main_path:String = script_data[0]
		if not deps.has(main_path):
			deps[main_path] = FileAccess.get_modified_time(main_path)
	return deps


static func validate_dependencies(deps:Dictionary, main_script_path:="") -> bool:
	for path:Variant in deps:
		if path == main_script_path:
			continue
		if FileAccess.get_modified_time(path) != deps[path]:
			return false
	return true

static func print_member_stack(stack:Array) -> void:
	print(" --- InferenceContext Stack ---")
	for string:Variant in stack:
		print(string)
	print(" --- /Stack ---")
