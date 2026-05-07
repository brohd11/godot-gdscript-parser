const GDScriptParser = preload("res://addons/addon_lib/brohd/alib_runtime/utils/gdscript/parser/gdscript_parser.gd")
const Keys = GDScriptParser.Keys

var member_stack:= []

var find_origin:bool = false

var first_expression:String = "" # think this is unused now

var _active_expressions:= {}
var _resolved_expressions:= {}

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

func add_to_member_stack(string:String):
	if not string in member_stack:
		member_stack.append(string)


static func get_stack_string(member_name:String, full_result:String, class_obj:GDScriptParser.ParserClass, local_vars:Dictionary):
	var stack_string = class_obj.get_script_class_path()
	var member_string = member_name
	if local_vars.has(member_name):
		var local_var_data = local_vars.get(member_name)
		member_string = "local(%s-%s)" % [member_name, local_var_data.get(Keys.LINE_INDEX)]
	
	stack_string = stack_string + "::" + member_string + Keys.MEMBER_STACK_DELIM + full_result.get_slice(Keys.MEMBER_INFER_DELIM, 1)
	return stack_string


static func print_member_stack(stack:Array):
	print(" --- InferenceContext Stack ---")
	for string in stack:
		print(string)
	print(" --- /Stack ---")
