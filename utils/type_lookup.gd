

const GDScriptParser = preload("res://addons/addon_lib/brohd/alib_runtime/utils/resource/gdscript/parser/gdscript_parser.gd")
const ParserClass = GDScriptParser.ParserClass
const ParserFunc = GDScriptParser.ParserFunc
const Utils = GDScriptParser.Utils
const Keys = Utils.Keys
const UString = GDScriptParser.UString
const UFile = GDScriptParser.UFile
const UClassDetail = GDScriptParser.UClassDetail

const BuiltInChecker = preload("res://addons/addon_lib/brohd/alib_runtime/utils/resource/gdscript/parser/utils/builtin/builtin_checker.gd")

const OTHER_TYPES = ["void", "Variant"]


const PLUGIN_EXPORTED = false
const PRINT_DEBUG = true # not PLUGIN_EXPORTED


var _parser:WeakRef
var code_edit:CodeEdit

var create_non_script_parsers:=true

var use_parsers_for_outside_script:=true

#var _resolve_to_script:=false



func _get_parser() -> GDScriptParser:
	return _parser.get_ref()

func _get_code_edit_parser() -> GDScriptParser.CodeEditParser:
	return _get_parser().code_edit_parser

func _get_parser_main_script():
	return Utils.ParserRef.get_parser(self).get_current_script()


#region Get Function Data

func get_function_data_at_line(identifier:String, line:int):
	var class_data = get_parser_objects_and_local_vars(line)
	return get_function_data(identifier, class_data.class_obj, line)


func get_function_data(identifier, class_obj:ParserClass, line:int=-1):
	var inherited_func:=false
	var complex_identifier = identifier.find(".") != -1
	var stripped_identifier = identifier
	
	if not complex_identifier:
		if identifier.find("(") > -1:
			stripped_identifier = identifier.substr(0, identifier.find("("))
		
		if not class_obj.has_script_member(stripped_identifier):
			inherited_func = true
		else:
			var func_obj = class_obj.get_function(identifier) as ParserFunc
			if is_instance_valid(func_obj):
				return func_obj.get_function_data()
			return {}
	
	var parser = Utils.ParserRef.get_parser(self)
	var calling_script_path = ""
	var calling_script_access = ""
	if complex_identifier:
		var string_map = UString.get_string_map(identifier)
		var access = UString.trim_member_access_back(identifier, string_map)
		identifier = UString.get_member_access_back(identifier, string_map)
		#var resolved_symbol = resolve_identifier_to_symbol(access, _line)
		var resolved_symbol = resolve_expression_at_line(access, line)
		print("FUNC DATA::SYMBOL::", resolved_symbol)
		if resolved_symbol != "":
			if BuiltInChecker.is_builtin_class(resolved_symbol):
				print("HAS SYMB::", resolved_symbol, "::ID::", identifier)
				calling_script_access = resolved_symbol
			else:
				var resolved_script = resolve_expression_at_line(resolved_symbol, line)
				print("FUNC DATA::RESOLVED::", resolved_script)
				if not resolved_script.begins_with("res://"):
					calling_script_access = resolved_script
				else:
					var script_data = UString.get_script_path_and_suffix(resolved_script)
					print("FUNC DATA::SCRIPT::",script_data)
					calling_script_path = script_data[0]
					calling_script_access = script_data[1]
					
					if calling_script_path.begins_with(class_obj.main_script_path):
						var new_class_obj = parser.get_class_object(calling_script_access)
						return get_function_data(identifier, new_class_obj)
	
	elif inherited_func:
		var inherited_script = _find_member_inheriting_script(stripped_identifier, class_obj.script_resource)
		if inherited_script != "": # this needs to account for inner classes
			calling_script_path = inherited_script
	
	
	
	return _outside_script_get_function_data(calling_script_path, calling_script_access, identifier)
	#Utils.ParserRef.get_class_obj()
	
	#if not in_script_function:
	#
		#var string_map = UString.get_string_map(identifier)
		#var access = UString.trim_member_access_back(identifier, string_map)
		#var method_name = UString.get_member_access_back(identifier, string_map)
		#calling_script = resolve_expression(access, class_obj, {})
		#print("FUNC DATA::SCRIPT::", calling_script)
		#if calling_script != "": # need to account for access path?
			#if calling_script.begins_with(parser):
				#pass
			#var script_data = UString.get_script_path_and_suffix(calling_script)
			#var script = load(script_data[0])
			##var parser = _get_parser_for_script(script)
			#var nested_class_obj = parser.get_class_object(script_data[1])
			#var func_data = get_function_data(method_name, nested_class_obj)
			#var func_args = func_data.get(Keys.FUNC_ARGS)
			#for name in func_args.keys():
				#var arg_data = func_args[name]
				#var type = arg_data.get(Keys.TYPE, "")
				#if type == "" or _valid_identifier(type):
					#continue
				#arg_data[Keys.TYPE_RESOLVED] = parser.get_identifier_type(type)
			#print("FUNC DATA::", func_data)
			#return func_data
		#
	#
	#return {}




func _outside_script_get_function_data(script_path:String, access_path:String, identifier:String) -> Dictionary:
	print("OUTSIDE::PATH::", script_path, "::ACCESS::", access_path, "::ID::", identifier)
	if script_path == "":
		return BuiltInChecker.get_func_data(access_path, identifier)
	#Color.html()
	
	var script = load(script_path)
	if use_parsers_for_outside_script:
		var parser = _get_parser_for_script(script)
		var class_obj = parser.get_class_object(access_path) as ParserClass
		var function = class_obj.get_function(identifier) as ParserFunc
		if is_instance_valid(function):
			return function.get_function_data()
	
	var data = UClassDetail.get_member_info_by_path(script, UString.dot_join(access_path, identifier))
	if data != null:
		print("MEMBER DATA::", data)
		var result = _property_info_to_function_data(data)
		print("MEMBER DATA::RESULT::", result)
		return result
	
	return {}


func _property_info_to_function_data(property_info:Dictionary):
	var data = {
		Keys.FUNC_ARGS:{},
		Keys.FUNC_RETURN:""
	}
	var args = property_info.get(&"args", [])
	for arg_data in args:
		var type = arg_data.get("class_name")
		if type == &"":
			type = type_string(arg_data.get("type"))
		data[Keys.FUNC_ARGS][arg_data.name] = {
			Keys.TYPE: type,
			Keys.MEMBER_TYPE: Keys.MEMBER_TYPE_FUNC_ARG
			}
	
	var return_data = property_info.get(&"return")
	if return_data != null:
		var type = return_data.get("class_name")
		if type == &"":
			type = type_string(return_data.get("type"))
		data[Keys.FUNC_RETURN] = type
	
	return data

#endregion

#region Resolve Expression

func resolve_expression_at_line(expression:String, line:int):
	var class_data = get_parser_objects_and_local_vars(line)
	var class_obj = class_data.class_obj
	var local_vars = class_data.local_vars
	return resolve_expression(expression, class_obj, local_vars)


func resolve_expression(expression: String, initial_class_obj: ParserClass, local_vars:Dictionary, recursions:int=0) -> String:
	if recursions >= 10:
		return expression
	
	var parser = _get_parser()
	var main_script = parser.get_current_script()
	var main_script_path = main_script.resource_path
	
	if expression.begins_with("res://"):
		print_deb(T.RESOLVE, "EARLY EXIT", "BEGIN WITH RES", expression)
		return expression
	
	if expression == "self": # if self, we can just return the path to the class
		return UString.dot_join(main_script_path, initial_class_obj.access_path)
	elif expression.begins_with("self."):
		expression = expression.trim_prefix("self.")
	
	if _valid_identifier(expression):
		print_deb(T.RESOLVE, "EARLY EXIT", "IS VALID", expression)
		return expression
	if _simple_type_check(expression) != "":
		print_deb(T.RESOLVE, "EARLY EXIT", "IS SIMPLE", expression)
		return _simple_type_check(expression)
	
	var string_map = parser.get_string_map(expression)
	var parts: Array = UString.split_member_access(expression, string_map)
	
	var current_class_obj:ParserClass = initial_class_obj
	var current_type_path = ""
	#var current_script_path = main_script_path
	
	var external_script_path:String
	var external_script_class_access:String
	
	#var current_script = main_script # GDScript Resource
	var current_part_in_script = true
	
	print_deb(T.RESOLVE, "START:%s - %s ----------" % [recursions, expression])
	print_deb(T.RESOLVE, "PARTS", parts)
	
	var count = 0
	while parts.size() > 0 and count < 10:
		count += 1
		var current_part: String = parts.pop_front()
		var is_func = current_part.find("(") != -1
		var identifier = current_part.split("(", false, 1)[0] if is_func else current_part
		
		if is_func and identifier == "new":
			if current_type_path == "":
				current_type_path = current_class_obj.get_script_class_path()
			continue
		
		print_deb(T.RESOLVE, "CYCLE ----------")
		print_deb(T.RESOLVE, "CHECK", identifier, "CURRENT TYPE", current_type_path)
		
		var resolved_type = ""
		if BuiltInChecker.is_builtin_class(identifier):
			resolved_type = identifier
		elif UClassDetail.get_global_class_path(identifier) != "":
			resolved_type = UClassDetail.get_global_class_path(identifier)
		elif _class_has_member(current_type_path, identifier):
			return _class_member_type(current_type_path, identifier)
		if current_class_obj.class_has_member(identifier):
			return _class_member_type(current_class_obj.script_base_type, identifier)
		
		if resolved_type == "":
			if current_part_in_script: #^ --- IN SCRIPT ---
				print_deb(T.RESOLVE, "IN_SCRIPT", identifier, "IN", main_script_path, "CLASS", current_class_obj.access_path)
				print_deb(T.RESOLVE, "CLASS OR LOCAL" if member_in_class_or_local_vars(identifier, current_class_obj, local_vars) else "NON SCRIPT")
				
				if member_in_class_or_local_vars(identifier, current_class_obj, local_vars):
					resolved_type = _resolve_process_in_script_data(identifier, current_class_obj, local_vars)
				else:
					#resolved_type = _resolve_process_non_script_class_member(identifier, current_class_obj, local_vars)
					resolved_type = _get_inherited_member_type(identifier, current_class_obj)
				
			else: #^ --- OUTSIDE SCRIPT ---
				if current_type_path.begins_with("res://"):
					resolved_type = _process_external_identifier(identifier, external_script_path, external_script_class_access)
					print_deb(T.RESOLVE, "EXTERNAL", "%s -> %s" % [identifier, resolved_type])
		
		
		if resolved_type == "" and not current_type_path.begins_with("res://"):# pass through current part so that you can get full context
			print_deb(T.RESOLVE, "OUTSIDE BUILT IN", identifier)
			resolved_type = _resolve_builtin_class_member(current_part, current_type_path, current_class_obj, local_vars) # ie. Dictionary.get(), can infer default
		
		if resolved_type == "":
			print_deb(T.RESOLVE, "ATTEMPT GLOBAL", identifier)
			resolved_type = UClassDetail.get_global_class_path(identifier) # YOUR IMPLEMENTATION
		
		print_deb(T.RESOLVE, "BASE ID", resolved_type)
		
		#^ --- HANDLE THE RESULT ---
		if resolved_type is not String:
			resolved_type = ""
		if resolved_type == "": # If we hit a dead end (untyped var, unknown function)
			return ""
		
		# RECURSION CHECK: Did the variable return a literal expression instead of a parsed type?
		# e.g., local_vars["my_var"] resulted in the string "SomeClass.get_instance()"
		# We must resolve that expression into a true path before continuing!
		if _is_unresolved_expression(resolved_type): 
			# Pass the initial context because expressions are evaluated where they were declared!
			var recursive = resolve_expression(resolved_type, initial_class_obj, local_vars, recursions + 1)
			if recursive != resolved_type:
				print_deb(T.RESOLVE, "RECURSE RESOLVED TYPE %s -> %s" %[resolved_type, recursive])
				resolved_type = recursive
			else:
				print_deb(T.RESOLVE, "RECUR == INPUT", resolved_type)
				return ""
		else:
			print_deb(T.RESOLVE, "RESOLVED_EXPRESSION", resolved_type)
		
		if resolved_type.ends_with(Keys.ENUM_PATH_SUFFIX):
			return resolved_type
		
		if not resolved_type.begins_with("res://"):
			current_part_in_script = false
		else:
			var script_data = UString.get_script_path_and_suffix(resolved_type)
			var current_script_path = script_data[0]
			var access_path = script_data[1]
			current_part_in_script = resolved_type.begins_with(main_script_path)
			if current_part_in_script:
				#current_script = main_script
				var new_class_obj = parser.get_class_object(access_path)
				print_deb(T.RESOLVE, "SWITCH OBJ", script_data, "%s -> %s" % [current_class_obj, new_class_obj])
				current_class_obj = new_class_obj
				if new_class_obj == null:
					print_deb(T.RESOLVE, "UNHANDLED CLASS OBJECT", resolved_type)
				
			else:
				external_script_path = current_script_path
				external_script_class_access = access_path
				#if access_path != "":
					#parts.push_front(access_path)
				#current_script = load(current_script_path)
		
		var old_path = current_type_path
		print_deb(T.RESOLVE, "SET PATH %s -> %s" % [old_path, resolved_type])
		print_deb(T.RESOLVE, "PARTS_LEFT",".".join(parts))
		
		current_type_path = resolved_type # last thing
	
	print_deb(T.RESOLVE, "RETURN", str(recursions), " ==== ", current_type_path)
	return current_type_path


func _is_unresolved_expression(identifier:String):
	if identifier.begins_with("res://"):
		return false
	elif _valid_identifier(identifier):
		return false
	elif identifier.begins_with("typedarray::"):
		return false
	elif identifier.find(".") > -1:
		var sm = Utils.ParserRef.get_parser(self).get_string_map(identifier)
		var front = UString.get_member_access_front(identifier, sm)
		var back = UString.trim_member_access_front(identifier, sm)
		if _class_has_member(front, back):
			return false
		return true
	return true


func _resolve_process_in_script_data(member_name:String, class_obj:ParserClass, local_vars:Dictionary):
	var count = 0
	var result = member_name
	while member_in_class_or_local_vars(result, class_obj, local_vars):
		count += 1
		if count > 50:
			print("COUNTED OUT")
			break
		var next_result = _check_class_obj_member_data(result, class_obj, local_vars)
		if next_result == null:
			break
		if result == next_result:
			break
		result = next_result
	
	return result


func _resolve_builtin_class_member(identifier:String, current_type_path:String, _class_obj:ParserClass, _local_vars:Dictionary):
	var type_to_check = ""
	var is_func = identifier.find("(") > -1
	var stripped_identifer = identifier.substr(0, identifier.find("(")) if is_func else identifier
	print_deb(T.BUILTIN, identifier, "TYPE", current_type_path)
	var method_handled = false
	if current_type_path == &"Dictionary":
		if identifier.begins_with("get"):
			var args = identifier.get_slice("(", 1)
			print(identifier, args)
			args = args.substr(0, args.rfind(")"))
			if args.find(",") == -1:
				return identifier
			type_to_check = args.get_slice(",", 1).strip_edges()
			method_handled = true
	
	if not method_handled and BuiltInChecker.is_builtin_class(current_type_path):
		var return_type = BuiltInChecker.get_func_return(current_type_path, stripped_identifer)
		print_deb(T.BUILTIN, "ID", stripped_identifer, "RETURN", return_type)
		return return_type
	
	if type_to_check == "":
		return ""
	var check = _simple_type_check(type_to_check)
	if check != "":
		return check
	
	return type_to_check



func _process_external_identifier(identifier:String, script_path:String, class_access_path:String = ""):
	var script = load(script_path) as GDScript
	if not use_parsers_for_outside_script:# or _class_has_member(script.get_instance_base_type(), identifier):
		if class_access_path != "":
			script = get_script_member_info_by_path(script, class_access_path)
		if script == null:
			print("EXTERNAL NO SCRIPT::", script_path, "::ACCESS::" ,class_access_path)
		var member_info = get_script_member_info_by_path(script, identifier)
		if member_info != null:
			return _property_info_to_type_no_class(member_info)
		return ""
	else:
		#var t = ALibRuntime.Utils.UProfile.TimeFunction.new("OUTSIDE PARSER: " + identifier + " -> " + str(script))
		var parser = GDScriptParser.new()
		parser.set_current_script(script)
		parser.set_source_code(script.source_code)
		parser.parse()
		var class_obj = parser.get_class_object(class_access_path) as ParserClass
		var type = parser.resolve_expression(identifier, class_obj.line_indexes[0])
		#t.stop()
		
		return type

## Get property info of inherited var, return type as string.
func _get_inherited_member_type(identifier:String, class_obj:ParserClass):
	var script = class_obj.get_script_resource()
	if not is_instance_valid(script):
		print_deb(T.INHERITED, "INVALID SCRIPT", class_obj.script_access_path)
		return ""
	
	var base_type = script.get_instance_base_type()
	if _class_has_member(base_type, identifier):
		return identifier
	
	var base_script = script.get_base_script()
	if is_instance_valid(base_script):
		var inheriting_script = _find_member_inheriting_script(identifier, base_script)
		if inheriting_script != "":
			print_deb(T.INHERITED, "EXTERNAL SCRIPT", base_script)
			return _process_external_identifier(identifier, inheriting_script) # may need access path for class?
	return ""


#endregion

#region Resolve Access Object

func resolve_expression_to_access_object_at_line(expression:String, line:int):
	var parser_data = get_parser_objects_and_local_vars(line)
	return resolve_expression_to_access_object(expression, parser_data.class_obj, parser_data.local_vars)

func resolve_expression_to_access_object(expression: String, initial_class_obj: ParserClass, local_vars:Dictionary):
	
	var parser = _get_parser()
	var main_script = parser.get_current_script()
	var main_script_path = main_script.resource_path
	
	if expression.begins_with("res://"):
		print_deb(T.VAR_TO_CONST, "EARLY EXIT", "BEGIN WITH RES", expression)
		return expression
	
	var string_map = parser.get_string_map(expression)
	var front = UString.get_member_access_front(expression, string_map)
	var back = UString.get_member_access_back(expression, string_map)
	
	
	var access_object = AccessObject.new()
	
	# ALERT testing with back, was front before
	var dec_symbol = _resolve_access_object([front], initial_class_obj, local_vars, true)
	if dec_symbol == front:
		dec_symbol = expression # this is for type hints var:SomeClass.Type, returns the whole string
	print("DECLARATION RAW::", dec_symbol)
	if dec_symbol.begins_with("res://"):
		var script_data = UString.get_script_path_and_suffix(dec_symbol)
		if script_data[0] == main_script_path:
			var access = script_data[1]
			if access == "":
				access = "self"
			dec_symbol = access
	elif dec_symbol == "":
		dec_symbol = "self"
	
	access_object.declaration_symbol = dec_symbol
	
	var access_symbol = _resolve_access_object([front], initial_class_obj, local_vars)
	print("ACCESS RAW::", access_symbol)
	if access_symbol.begins_with("res://"):
		var script_data = UString.get_script_path_and_suffix(access_symbol)
		if script_data[0] == main_script_path:
			var access = script_data[1]
			if access == "":
				access = "self"
			access_symbol = access
	elif access_symbol == "":
		access_symbol = "self"
	access_object.access_symbol = access_symbol
	
	access_object.type = resolve_expression(dec_symbol, initial_class_obj, local_vars)
	access_object.access_type = resolve_expression(access_symbol, initial_class_obj, local_vars)
	
	print_deb(T.VAR_TO_CONST, access_object.type, access_object.declaration_symbol, access_object.access_symbol)
	return access_object


func _resolve_access_object(parts:Array, initial_class_obj: ParserClass, local_vars:Dictionary, first_const:=false):
	if parts[0] == "self": # if self, we can just return the path to the class
		return "self"
	var current_class_obj:ParserClass = initial_class_obj
	
	print_deb(T.VAR_TO_CONST, "&&&& START: %s ----------" % [parts[0]])
	print_deb(T.VAR_TO_CONST, "PARTS", parts)
	
	var count = 0
	while parts.size() > 0 and count < 10:
		count += 1
		var current_part: String = parts.pop_front()
		var is_func = current_part.find("(") != -1
		var identifier = current_part.split("(", false, 1)[0] if is_func else current_part
		
		if is_func and identifier == "new":
			return current_class_obj.get_script_class_path()
		
		print_deb(T.VAR_TO_CONST, "CYCLE ----------")
		print_deb(T.VAR_TO_CONST, "CHECK", identifier)
		
		var resolved_type = ""
		if member_in_class_or_local_vars(identifier, current_class_obj, local_vars):
			print_deb(T.VAR_TO_CONST, "IN CLASS", identifier)
			if current_class_obj.has_constant_or_class(identifier):
				if first_const:
					return identifier
				else:
					#pass
					return _resolve_const_path(identifier, current_class_obj)
			
			resolved_type = _var_to_const(identifier, current_class_obj, local_vars, first_const)
			if resolved_type != identifier:
				parts.push_front(UString.get_member_access_front(resolved_type))
				continue
			else:
				return resolved_type
		elif current_class_obj.has_inherited_member(identifier):
			print_deb(T.VAR_TO_CONST, "INHERITED", identifier) # should this return self? func could return something else
			if is_func:
				print_deb(T.VAR_TO_CONST, "INHERITED FUNC", identifier, "TO IMPLEMENT")
				#resolved_type = ret
				pass
			else:
				return identifier
				#resolved_type = identifier
		
		if BuiltInChecker.is_builtin_class(identifier):
			return identifier
		elif UClassDetail.get_global_class_path(identifier) != "":
			return identifier
		elif _is_class_name_valid(identifier):
			return identifier
		
		#if resolved_type == "":# pass through current part so that you can get full context
			#print_deb(T.VAR_TO_CONST, "OUTSIDE BUILT IN", identifier)
			#resolved_type = _resolve_builtin_class_member(current_part, current_type_path, current_class_obj, local_vars) # ie. Dictionary.get(), can infer default
		
		print_deb(T.VAR_TO_CONST, "NONE", identifier, "RES", resolved_type)
		
		#^ --- HANDLE THE RESULT ---
		if resolved_type is not String or resolved_type == "":
			return ""
	return ""



func _var_to_const(member_name:String, class_obj:ParserClass, local_vars:Dictionary, first_const:=false):
	var count = 0
	var result = member_name
	while member_in_class_or_local_vars(result, class_obj, local_vars):
		if first_const:
			if class_obj.has_constant_or_class(result):
				return result
		count += 1
		if count > 50:
			print("COUNTED OUT")
			break
		var next_result = _check_class_obj_member_data(result, class_obj, local_vars)
		if next_result == null:
			break
		if result == next_result or next_result.begins_with("res://"):
			break
		result = next_result
	
	return result
	
	#test_tf_sim()
	
	#test_tf_sim()


func _resolve_const_path(member_name:String, class_obj:ParserClass):
	var full_chain_parts:= []
	var count = 0
	var result = member_name
	while member_in_class_or_local_vars(result, class_obj, {}):
		count += 1
		if count > 50:
			print("COUNTED OUT")
			break
		var next_result = _check_class_obj_member_data(result, class_obj, {})
		var not_valid = next_result == null or result == next_result or next_result.begins_with("res://")
		if not_valid:
			break
		var parts = next_result.split(".", false)
		parts.reverse()
		var p_sz = parts.size()
		for i in range(p_sz):
			var part = parts[i]
			if i == p_sz - 1:
				result = part
			else:
				full_chain_parts.push_front(part)
	
	full_chain_parts.push_front(result)
	return ".".join(full_chain_parts)

#endregion

#region Utils


func _check_class_obj_member_data(member_name:String, class_obj:ParserClass, local_vars:Dictionary):
	var member_data = local_vars.get(member_name)
	if member_data == null:
		member_data = class_obj.get_member(member_name)
	
	if member_data == null:
		print("MEMBER NULL, WHAT TO DO???: ", member_name)
		#return _simple_type_check(member_name)
	
	
	var type_declaration = ""
	
	var member_type = member_data.get(Keys.MEMBER_TYPE)
	var line_index = member_data.get(Keys.LINE_INDEX)
	if member_type == Keys.MEMBER_TYPE_CLASS:
		return member_data.get(Keys.TYPE)
	elif member_data is ParserFunc:
		#type_declaration = _get_func_return_type(member_name, class_obj)
		type_declaration = member_data.get_return_type()
		print_deb(T.RESOLVE, "GET FUNC: ", type_declaration)
	elif member_type == Keys.MEMBER_TYPE_FUNC_ARG:
		type_declaration = member_data.get(Keys.TYPE)
	else:
		var column = member_data.get(Keys.COLUMN_INDEX, 0)
		print_deb(T.RESOLVE, "COLUMN ", column)
		type_declaration = _get_script_member_type(line_index, column)
	
	var type_check = _simple_type_check(type_declaration)
	if type_check != "":
		print_deb(T.RESOLVE, "TYPE CHECK SUCCESS: ", type_declaration, " -> ", type_check)
		return type_check
	
	print_deb(T.RESOLVE, "FUNC OR VAR: ", type_declaration)
	
	return type_declaration


## Get script member info, ignores Godot Native class inheritance properties.
func get_script_member_info_by_path(script:GDScript, member_path:String, member_hints:=UClassDetail._MEMBER_ARGS, check_global:=true):
	return UClassDetail.get_member_info_by_path(script, member_path, member_hints, false, false, false, check_global)

func _valid_identifier(identifier:String):
	if _is_class_name_valid(identifier): # don't allow global so they are resolved to script.
		return true
	if BuiltInChecker.is_global_method(identifier):
		return true
	if BuiltInChecker.is_builtin_class(identifier):
		return true
	if identifier in OTHER_TYPES:
		return true
	return false

## Check that class name is Godot Native or member of the class. A valid user global class will also return true.
func _is_class_name_valid(identifier:String):
	#if identifier.find(".") > -1:
		#identifier = identifier.substr(0, identifier.find("."))
	if ClassDB.class_exists(identifier):
		return true
	var current_script = _get_parser_main_script()
	var base = current_script.get_instance_base_type()
	if (ClassDB.class_has_enum(base, identifier) or ClassDB.class_has_integer_constant(base, identifier) or 
	ClassDB.class_has_method(base, identifier) or ClassDB.class_has_signal(base, identifier)):
		return true
	return false

## Check that ClassDB class contains member.
func _class_has_member(base_type:String, identifier:String):
	if not ClassDB.class_exists(base_type):
		return false
	if ClassDB.class_has_enum(base_type, identifier):
		return true
	elif ClassDB.class_has_integer_constant(base_type, identifier):
		return true
	elif ClassDB.class_has_method(base_type, identifier):
		return true
	elif ClassDB.class_has_signal(base_type, identifier):
		return true
	#var prop_list = ClassDB.class_get_property_list(base_type)
	#print("HAS MEMBER")
	#for p:Dictionary in prop_list:
		#print(p)
		#if p.name == identifier:
			#return true
	return false

func _class_member_type(base_type:String, identifier:String):
	if ClassDB.class_has_enum(base_type, identifier):
		return UString.dot_join(base_type, identifier)
	elif ClassDB.class_has_integer_constant(base_type, identifier):
		return UString.dot_join(base_type, identifier)
	elif ClassDB.class_has_signal(base_type, identifier):
		return "Signal"
	elif ClassDB.class_has_method(base_type, identifier):
		var func_data_array = ClassDB.class_get_method_list(base_type)
		for d:Dictionary in func_data_array:
			if d.name != identifier:
				continue
			var resolved_data = _property_info_to_function_data(d)
			return resolved_data.get(Keys.FUNC_RETURN)
	#var prop_list = ClassDB.class_get_property_list(base_type)
	#for p:Dictionary in prop_list:
		#if identifier.begins_with(p.get("hint_string"), ""):
			#return 
			#
	return ""

## Get a class_name from property info and convert to a type if possible.
## If method data, uses return data.
func property_info_to_type(property_info, class_obj:ParserClass) -> String:
	var type = _property_info_to_type(property_info, class_obj)
	return type

func _property_info_to_type(property_info, class_obj:ParserClass) -> String:
	if property_info is Dictionary:
		if property_info.has("return"):
			property_info = property_info.get("return", {})
		
		if property_info.has("class_name"):
			var _class_name = property_info.get("class_name")
			if _class_name == "":
				var type = property_info.get("type")
				return type_string(type)
			
			if not _class_name.begins_with("res://"):
				return _class_name
			
			var class_path = _class_name
			var const_name = class_obj.has_preload(class_path)
			if const_name:
				return const_name
			
			#var class_path = _class_name #^ old version
			#var access_name = ""
			##if _class_name.find(".gd.") > -1: #^ maybe able comment this with preload map modified
				##class_path = _class_name.substr(0, _class_name.find(".gd.") + 3) # + 3 to keep ext
				##access_name = _class_name.substr(_class_name.find(".gd.") + 4) # + 4 to omit ext
			#var const_name = preload_map.get(class_path)
			#if const_name:
				#if access_name == "":
					#return const_name
				#else:
					#return const_name + "." + access_name
			
			return _class_name # return class name as path or class to process elsewhere
		
	elif property_info is GDScript:
		var current_script = _get_parser_main_script()
		var member_path = UClassDetail.script_get_member_by_value(current_script, property_info)
		if member_path != null:
			return member_path
		
		var path = property_info.resource_path
		var const_name = class_obj.has_preload(path)
		if const_name:
			return const_name
	
	if PRINT_DEBUG:
		printerr("UNHANDLED PROPERTY INFO OR UNFOUND: ", property_info)
	return ""


func _property_info_to_type_no_class(property_info) -> String:
	if property_info is Dictionary:
		if property_info.has("return"):
			property_info = property_info.get("return", {})
		
		if property_info.has("class_name"):
			var _class_name = property_info.get("class_name")
			if _class_name == "":
				var type = property_info.get("type")
				return type_string(type)
			
			if not _class_name.begins_with("res://"):
				return _class_name
			return _class_name # return class name as path or class to process elsewhere
		
	elif property_info is GDScript:
		return property_info.resource_path
	
	if PRINT_DEBUG:
		printerr("UNHANDLED PROPERTY INFO OR UNFOUND: ", property_info)
	return ""


func _simple_type_check(type_hint:String):
	if type_hint.find(" as ") > -1:
		type_hint = type_hint.get_slice(" as ", 1)
		if type_hint.find("#") > -1:
			type_hint = type_hint.get_slice("#", 0)
		type_hint = type_hint.strip_edges()
	
	
	if type_hint.find(".new(") > -1:
		type_hint = type_hint.substr(0, type_hint.find(".new(")) # was rfind, prob should be find?
		if _is_class_name_valid(type_hint):
			return type_hint
	
	if BuiltInChecker.is_builtin_class(type_hint):
		return type_hint
	if type_hint in OTHER_TYPES:
		return type_hint
	if type_hint.begins_with("res://"):
		return type_hint
	if type_hint.begins_with("uid:"):
		return UFile.uid_to_path(type_hint)
	
	if type_hint == "true" or type_hint == "false":
		return "bool"
	elif type_hint.is_valid_int():
		return "int"
	elif type_hint.is_valid_float():
		return "float"
	elif type_hint.begins_with("["):
		return "Array"
	elif type_hint.begins_with("{"):
		return "Dictionary"
	elif type_hint.begins_with("&"):
		return "StringName"
	elif type_hint.begins_with("^"):
		return "NodePath"
	elif type_hint.begins_with('"') or type_hint.begins_with("'"):
		return "String"
	
	if _is_class_name_valid(type_hint):
		return type_hint
	
	return ""

func test3():
	for s:String in "this":
		
		
		pass




func _get_script_member_type(line:int, column:int=0): # thjs could be a bit more efficient, if not needed, could use what you got already, 
	var code_edit_parser = _get_code_edit_parser() # but also maybe speeding up scan by not getting types could be good
	#var line_text = code_edit_parser.get_line(line, true)
	var get_type_data = code_edit_parser.get_type_from_line(line, column)
	var result = get_type_data.get("result")
	if result == null:
		return ""
	var dec_type = get_type_data.get("type", &"")
	if dec_type == Keys.MEMBER_TYPE_CONST or dec_type == Keys.MEMBER_TYPE_VAR or dec_type == Keys.MEMBER_TYPE_STATIC_VAR:
		return result[1]
	elif dec_type == Keys.MEMBER_TYPE_ENUM:
		var parser = Utils.ParserRef.get_parser(self)
		var class_at_line = parser.get_class_object(parser.get_class_at_line(line)) as ParserClass
		var access = UString.dot_join(class_at_line.access_path, result[0] + Keys.ENUM_PATH_SUFFIX)
		return UString.dot_join(class_at_line.main_script_path, access)
	elif dec_type == Keys.MEMBER_TYPE_CLASS:
		var parser = Utils.ParserRef.get_parser(self)
		var class_at_line = parser.get_class_object(parser.get_class_at_line(line)) as ParserClass
		var access = UString.dot_join(class_at_line.access_path, result[0])
		return UString.dot_join(class_at_line.main_script_path, access)
	elif dec_type == Keys.MEMBER_TYPE_FUNC or dec_type == Keys.MEMBER_TYPE_STATIC_FUNC:
		return result.get(Keys.FUNC_NAME, "")
	elif dec_type == Keys.MEMBER_TYPE_SIGNAL:
		return "Signal"
	
	return ""
	
	#if line_text.ends_with("\\") or column > 0:
		#return code_edit_parser.get_type_from_line(line, column)
	#else:
		#return code_edit_parser.get_type_from_line_text(line_text.strip_edges())



func member_in_class_or_local_vars(identifier:String, class_obj:ParserClass, local_vars:Dictionary):
	return class_obj.has_script_member(identifier) or local_vars.has(identifier)

func _find_member_inheriting_script(identifier:String, script:GDScript):
	var last_script = script
	if get_script_member_info_by_path(script, identifier) == null:
		return ""
	var current_script = script.get_base_script()
	while current_script != null:
		if get_script_member_info_by_path(current_script, identifier) == null:
			break
		last_script = current_script
		current_script = current_script.get_base_script()
	return last_script.resource_path


func _get_parser_for_script(script:GDScript):
	var parser = GDScriptParser.new()
	parser.set_current_script(script)
	parser.set_source_code(script.source_code)
	parser.parse()
	return parser


func get_parser_objects_and_local_vars(line:int) -> ClassData:
	var parser = Utils.ParserRef.get_parser(self)
	var class_data = ClassData.new(parser, line)
	return class_data

#endregion

class ClassData:
	var class_obj:ParserClass
	var func_obj:ParserFunc
	var local_vars:Dictionary = {}
	
	func _init(parser:GDScriptParser, line:int) -> void:
		class_obj = parser.get_class_object(parser.get_class_at_line(line))
		var function_name = class_obj.get_function_at_line(line)
		if function_name != Keys.CLASS_BODY:
			func_obj = class_obj.get_function(function_name)
			if is_instance_valid(func_obj):
				func_obj.parse()
				local_vars = func_obj.get_in_scope_local_vars(line)

class AccessObject:
	var type:String
	var declaration_symbol:String
	var access_type:String
	var access_symbol:String


static func print_deb(section:String, ...msg:Array):
	if not PRINT_DEBUG:
		return
	if section in _PRINT:
		msg.push_front(section)
		ALibEditor.PrintDebug.print(msg)

const _PRINT = [
	T.BUILTIN, 
	T.INHERITED,
	T.VAR_TO_CONST,
	#T.RESOLVE
	]

#! arg_location section:T
class T:
	const RESOLVE = "RESOLVE"
	const BUILTIN = "BUILTIN"
	const INHERITED = "INHERITED"
	const VAR_TO_CONST = "VAR TO CONST"
	
