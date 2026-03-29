

const GDScriptParser = preload("res://addons/addon_lib/brohd/alib_runtime/utils/resource/gdscript/parser/gdscript_parser.gd")
const ParserClass = GDScriptParser.ParserClass
const ParserFunc = GDScriptParser.ParserFunc
const Utils = GDScriptParser.Utils
const Keys = Utils.Keys
const UString = GDScriptParser.UString
const UFile = GDScriptParser.UFile
const UClassDetail = GDScriptParser.UClassDetail
const AccessObject = GDScriptParser.Access.AccessObject

const BuiltInChecker = preload("res://addons/addon_lib/brohd/alib_runtime/utils/resource/gdscript/parser/utils/builtin/builtin_checker.gd")

const ENUM_SUFFIX = Keys.ENUM_PATH_SUFFIX
const OTHER_TYPES = ["void", "Variant"]


const PLUGIN_EXPORTED = false
const PRINT_DEBUG = true # not PLUGIN_EXPORTED



var _parser:WeakRef
var code_edit:CodeEdit

var create_non_script_parsers:=true

var use_parsers_for_outside_script:=true

# for resolve inner class
var class_resolution:=false
var class_resolution_obj:ParserClass

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
	print("GET FUNC DATA::", identifier , "::IN::", class_obj.get_script_class_path())
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
				print("SIMPLE GET::", func_obj.get_function_data())
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
		var member_data = class_obj.get_inherited_member(identifier)
		if member_data != null:
			calling_script_path = member_data.get(Keys.SCRIPT_PATH)
			calling_script_access = member_data.get(Keys.ACCESS_PATH)
		
		#var inherited_script = _find_member_inheriting_script(stripped_identifier, class_obj.script_resource)
		#if inherited_script != "": # this needs to account for inner classes
			#calling_script_path = inherited_script
	
	
	
	return _outside_script_get_function_data(calling_script_path, calling_script_access, identifier)




func _outside_script_get_function_data(script_path:String, access_path:String, identifier:String) -> Dictionary:
	print("OUTSIDE::PATH::", script_path, "::ACCESS::", access_path, "::ID::", identifier)
	if script_path == "":
		return BuiltInChecker.get_func_data(access_path, identifier)
	#Color.html()
	
	var script = load(script_path)
	if use_parsers_for_outside_script:
		var parser = _get_parser_for_script(script_path)
		var class_obj = parser.get_class_object(access_path) as ParserClass
		var function = class_obj.get_function(identifier) as ParserFunc
		if is_instance_valid(function):
			print("SIMPLE GET::", function.get_function_data())
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


## This call is almost identical to the normal resolve, except it will not use inheritance in the current class.
## This is because the class must be declared by something in the current script, impossible to be an inherited member.
func resolve_inner_class_at_line(expression:String, line:int):
	class_resolution = true
	var class_data = get_parser_objects_and_local_vars(line)
	var class_obj = class_data.class_obj
	class_resolution_obj = class_obj
	var local_vars = class_data.local_vars
	var result = resolve_expression(expression, class_obj, local_vars)
	class_resolution = false
	return result


func resolve_expression_at_line(expression:String, line:int):
	if class_resolution == true:
		print("CLASS RES TRUE")
	class_resolution = false
	var class_data = get_parser_objects_and_local_vars(line)
	var class_obj = class_data.class_obj
	var local_vars = class_data.local_vars
	var result = resolve_expression(expression, class_obj, local_vars)
	return result 


func resolve_expression(expression: String, initial_class_obj: ParserClass, local_vars:Dictionary, recursions:int=0) -> String:
	if recursions >= 10:
		return expression
	
	var parser = _get_parser()
	var main_script = parser.get_current_script()
	var main_script_path = main_script.resource_path
	
	if expression.begins_with("res://"):
		print_deb(T.RESOLVE, "EARLY EXIT", "BEGIN WITH RES", expression)
		return Utils.file_path_to_type(expression)
		#return expression
	
	if expression == "self": # if self, we can just return the path to the class
		return UString.dot_join(main_script_path, initial_class_obj.access_path)
	elif expression.begins_with("self."):
		expression = expression.trim_prefix("self.")
	
	if _valid_identifier(expression):
		print_deb(T.RESOLVE, "EARLY EXIT", "IS VALID", expression)
		if initial_class_obj.class_has_member(expression):
			return _class_member_type(initial_class_obj.script_base_type, expression)
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
			#return _class_member_type(current_type_path, identifier) # this is how it was
			# TEST
			print("EXIT")
			resolved_type = _class_member_type(current_type_path, identifier)
		if current_class_obj.class_has_member(identifier):
			print("EXIT CLASS HAS MEMBER")
			if identifier != "get":
				return _class_member_type(current_class_obj.script_base_type, identifier)
			else: # get can be tricky, the built in returns Nil, but we can attempt to infer more. Maybe limit to Dictionary?
				resolved_type = _resolve_builtin_class_member(current_part, current_type_path, current_class_obj, local_vars)
		
		if resolved_type == "":
			if current_part_in_script: #^ --- IN SCRIPT ---
				print_deb(T.RESOLVE, "IN_SCRIPT", identifier, "IN", main_script_path, "CLASS", current_class_obj.access_path)
				print_deb(T.RESOLVE, "CLASS OR LOCAL" if member_in_class_or_local_vars(identifier, current_class_obj, local_vars) else "NON SCRIPT")
				
				if member_in_class_or_local_vars(identifier, current_class_obj, local_vars):
					resolved_type = _resolve_process_in_script_data(identifier, current_class_obj, local_vars)
				else:
					resolved_type = _get_inherited_member_type(current_part, current_class_obj)
				
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
		if resolved_type is not String and resolved_type is not StringName:
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
	if current_type_path.begins_with("res://"):
		current_type_path = Utils.file_path_to_type(current_type_path)
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

func get_dic():
	var dic = {}
	return dic.get(Keys.ACCESS_PATH)

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
				return "Variant"
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
	if not use_parsers_for_outside_script:# or _class_has_member(script.get_instance_base_type(), identifier):
		
		var script = load(script_path) as GDScript # need to handl
		if class_access_path != "":
			script = get_script_member_info_by_path(script, class_access_path)
		if script == null:
			print("EXTERNAL NO SCRIPT::", script_path, "::ACCESS::" ,class_access_path)
		var member_info = get_script_member_info_by_path(script, identifier)
		if member_info != null:
			return _property_info_to_type_no_class(member_info)
		return ""
	else:
		var t = ALibRuntime.Utils.UProfile.TimeFunction.new("OUTSIDE PARSER: " + identifier + " -> " + str(script_path.get_file()))
		var external_parser = _get_parser_for_script(script_path)
		var class_obj = external_parser.get_class_object(class_access_path) as ParserClass
		var type = external_parser.resolve_expression(identifier, class_obj.line_indexes[0])
		t.stop()
		
		return type

## Get property info of inherited var, return type as string.
func _get_inherited_member_type(identifier:String, class_obj:ParserClass):
	var is_func = identifier.find("(") > -1
	var stripped_identifer = identifier.substr(0, identifier.find("(")) if is_func else identifier
	var script = class_obj.get_script_resource()
	if not is_instance_valid(script):
		print_deb(T.INHERITED, "INVALID SCRIPT", class_obj.script_access_path)
		return ""
	
	var base_type = script.get_instance_base_type()
	if _class_has_member(base_type, stripped_identifer):
		return stripped_identifer
	
	if class_resolution and class_obj == class_resolution_obj:
		#^r IMPLEMENT OUTER SCRIPT CONSTANTS HERE
		print_deb(T.INHERITED, "CLASS RESOLUTION IN INHERIT", class_resolution_obj.get_script_class_path())
		return ""
	
	var member_data = class_obj.get_inherited_member(identifier)
	if member_data != null:
		var script_path = member_data.get(Keys.SCRIPT_PATH)
		if script_path != null:
			var access_path = member_data.get(Keys.ACCESS_PATH)
			return _process_external_identifier(identifier, script_path, access_path) # may need access path for class?
	
	
	print_deb(T.INHERITED, "MEMBER_DATA", member_data)
	
	var base_script = script.get_base_script()
	if is_instance_valid(base_script):
		var inheriting_script = _find_inheriting_script(stripped_identifer, class_obj)
		if inheriting_script != "":
			var script_data = UString.get_script_path_and_suffix(inheriting_script)
			print_deb(T.INHERITED, "EXTERNAL SCRIPT", inheriting_script)
			return _process_external_identifier(identifier, script_data[0], script_data[1]) # may need access path for class?
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
	
	print_deb(T.VAR_TO_CONST, "ACCESS OBJECT START", expression)
	
	var access_object = AccessObject.new()
	
	# ALERT testing with back, was front before
	var dec_symbol = _resolve_access_object([front], initial_class_obj, local_vars, true)
	if dec_symbol == front:
		var new = expression
		#new = _validate_const_chain(expression, initial_class_obj)
		print_deb(T.VAR_TO_CONST, "DECLARATION RAW SWITCH", dec_symbol, " -> ", new)
		dec_symbol = expression
		#dec_symbol = _validate_const_chain(expression, initial_class_obj) # this is for type hints var:SomeClass.Type, returns the whole string
	# ALERT
	print_deb(T.VAR_TO_CONST, "DECLARATION RAW", dec_symbol)
	if dec_symbol.begins_with("res://"):
		var script_data = UString.get_script_path_and_suffix(dec_symbol)
		if script_data[0] == main_script_path:
			var access = script_data[1]
			if access == "":
				access = "self"
			dec_symbol = access
	elif dec_symbol == "":
		dec_symbol = "self"
	#else: # TEST NEW #^r causes issues, but this makes sense, cannot declare as self..., can access from self
		#dec_symbol = "self"
	
	access_object.declaration_symbol = dec_symbol
	
	var access_symbol = _resolve_access_object([front], initial_class_obj, local_vars)
	print_deb(T.VAR_TO_CONST, "ACCESS RAW", access_symbol)
	if access_symbol.begins_with("res://"):
		var script_data = UString.get_script_path_and_suffix(access_symbol)
		if script_data[0] == main_script_path:
			var access = script_data[1]
			if access == "":
				access = "self" #^r what purpose does this even serve? don't seem to use it anywhere?
			access_symbol = access
	elif access_symbol == "":
		access_symbol = "self"
	#else: # TEST NEW #^r this is causing some to not work right, NewScript with the renamed time funcs
		#access_symbol = "self" #^r this was for when base types were here? EditorInterface, String etc.. where was it an issue though?
	access_object.access_symbol = access_symbol
	
	access_object.declaration_type = resolve_expression(dec_symbol, initial_class_obj, local_vars)
	if access_object.declaration_type.begins_with("res://"):
		var member_data = parser.get_member_info_from_script(access_object.declaration_type)
		if member_data != null:
			access_object.declaration_access_path = member_data.get(Keys.ACCESS_PATH)
	
	access_object.access_type = resolve_expression(access_symbol, initial_class_obj, local_vars)
	
	print_deb(T.VAR_TO_CONST, "TYPE", access_object.declaration_type, "DEC",access_object.declaration_symbol, "ACCESS" ,access_object.access_symbol)
	return access_object


func _resolve_access_object(parts:Array, initial_class_obj: ParserClass, local_vars:Dictionary, first_const:=false):
	if parts[0] == "self": # if self, we can just return the path to the class
		return "self"
	
	var current_class_obj:ParserClass = initial_class_obj
	print_deb(T.VAR_TO_CONST, "&&&& START: %s ----------" % [parts])
	
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
			print_deb(T.VAR_TO_CONST, "IN CLASS RESOLVED", resolved_type)
			var front = UString.get_member_access_front(resolved_type)
			
			if current_class_obj.has_constant_or_class(front):
				if resolved_type.contains("."):
					resolved_type = _validate_const_chain(resolved_type, current_class_obj)
				return resolved_type
			if resolved_type != identifier:
				parts.push_front(front)
				continue
			else:
				return resolved_type
		elif current_class_obj.has_inherited_member(identifier):
			#return ""
			#^c Unsure about this, technically, if it is inherited, the access is self? Not sure what this should resolve to.
			var inh_script_path = _find_member_inheriting_script(identifier, current_class_obj.script_resource)
			if inh_script_path == "":
				return ""
			var parser_data = _get_parser_and_class_for_script(inh_script_path)
			var parser = parser_data.get(Keys.GET_PARSER)
			var inh_class_obj = parser_data.get(Keys.GET_CLASS_OBJ)
			var type_lookup = parser.get_type_lookup()
			
			var resolved = type_lookup._resolve_access_object([identifier], inh_class_obj, {}, first_const)
			print_deb(T.VAR_TO_CONST, "INHERITED", identifier, "RESOLVED", resolved) # should this return self? func could return something else
			if resolved != identifier:
				parts.push_front(UString.get_member_access_front(resolved))
				continue
			else:
				return resolved
		
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
			print_deb(T.VAR_TO_CONST, "COUNTED OUT")
			break
		var next_result
		if class_obj.has_function(result):
			var function:ParserFunc = class_obj.get_function(result)
			next_result = function.get_return_type(false) # returns the raw declaration
		else:
			next_result = _check_class_obj_member_data(result, class_obj, local_vars)
		if next_result == null:
			break
		if result == next_result or next_result.begins_with("res://"):
			break
		result = next_result
	
	return result

func _var_to_const_get_inh_func_return(identifier:String, class_obj:ParserClass, first_const:=false):
	var inh_script_path = _find_inheriting_script(identifier, class_obj)
	var parser_data = _get_parser_and_class_for_script(inh_script_path)
	var inh_class_obj = parser_data.get(Keys.GET_CLASS_OBJ)
	
	#var script_data = UString.get_script_path_and_suffix(inh_script_path)
	#var parser = _get_parser_for_script(script_data[0])
	#var inh_class_obj = parser.get_class_object(script_data[1])
	var function = inh_class_obj.get_function(identifier) as ParserFunc
	var return_type = function.get_return_type(false)
	print_deb(T.VAR_TO_CONST, return_type)
	return return_type


func _resolve_const_path(member_name:String, class_obj:ParserClass):
	var full_chain_parts:= []
	var count = 0
	var result = member_name
	while member_in_class_or_local_vars(result, class_obj, {}):
		count += 1
		if count > 50:
			print_deb(T.VAR_TO_CONST, "COUNTED OUT")
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

const CONST_TYPES = [Keys.MEMBER_TYPE_CLASS, Keys.MEMBER_TYPE_CONST]
func _validate_const_chain(chain_text:String, class_obj:ParserClass):
	var parser = _get_parser()
	
	if chain_text.begins_with("res://"):
		print_deb(T.VAR_TO_CONST, "EARLY EXIT", "BEGIN WITH RES", chain_text)
		return chain_text
	
	var string_map = parser.get_string_map(chain_text)
	var parts = UString.split_member_access(chain_text, string_map)
	
	var working_path = ""
	for i in range(parts.size()):
		var part = parts[i]
		var type = ""
		if UClassDetail.get_global_class_path(part) != "":
			type = UClassDetail.get_global_class_path(part)
		else:
			var member_data = class_obj.get_member(part)
			if member_data == null or member_data is ParserFunc:
				break
			var member_type = member_data.get(Keys.MEMBER_TYPE)
			if member_type == Keys.MEMBER_TYPE_ENUM:
				working_path = UString.dot_join(working_path, part)
				break
			if member_type not in CONST_TYPES:
				break
			
			type = class_obj.get_member_type(part)
			if not type.begins_with("res://"):
				break
		working_path = UString.dot_join(working_path, part)
		var next_parser_data = parser.get_parser_and_class_obj_for_script(type)
		parser = next_parser_data.parser
		class_obj = next_parser_data.class_obj
		#var result = next_parser.
	
	return working_path

#endregion


#region Utils
## Get member type in class obj. Returns declaration or converted to type if it is a simple check [method _simple_type_check].
## Allow rebuild param will determine if the script will reparse if not found at it's line index.
func get_class_obj_member_type(member_name:String, class_obj:ParserClass, local_vars:Dictionary={}, allow_rebuild:=true):
	return _check_class_obj_member_data(member_name, class_obj, local_vars, allow_rebuild)

func _check_class_obj_member_data(member_name:String, class_obj:ParserClass, local_vars:Dictionary, allow_rebuild:=true):
	var is_local = false
	var member_data = local_vars.get(member_name)
	if member_data != null:
		is_local = true
	else:
		member_data = class_obj.get_member(member_name)
	
	if member_data == null:
		print("MEMBER NULL, WHAT TO DO???: ", member_name, " CLASS:: ", class_obj.get_name())
		return "" # only time I have triggered is deleting a var and then quickly trying to access, difficult to trigger
	
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
		if not is_local: # local is parsed every auto complete cycle, only necessary on body members
			var code_edit_parser = _get_code_edit_parser()
			if not code_edit_parser.check_member_line(member_type, member_name, line_index, column, allow_rebuild):
				if allow_rebuild:
					return _check_class_obj_member_data(member_name, class_obj, local_vars, false)
				else:
					print("ABORT CHECK MEMBER DATA")
					return "" # this should be handled by the above member_data check
		
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
	
	#TEST
	var parser = Utils.ParserRef.get_parser(self)
	var string_map = parser.get_string_map(type_hint)
	for bool_op in Utils.Keywords.BOOL_OPERATORS:
		var bool_op_idx = type_hint.find(bool_op)
		if bool_op_idx > -1 and not string_map.index_in_string_or_comment(bool_op_idx):
			print("TYPE HINT::BOOL::", type_hint, "::OP::", bool_op)
			return "bool"
	#TEST
	
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
	elif type_hint.begins_with("Array"): # for Array[SomeType]
		return "Array"
	elif type_hint.begins_with("Dictionary"): # for keyed dicts Dictionary[Key, Val]
		return "Dictionary"
	
	#TEST
	for non_bool_op in Utils.Keywords.NON_BOOL_OPERATORS:
		var non_bool_op_idx = type_hint.find(non_bool_op)
		if non_bool_op_idx > -1 and not string_map.index_in_string_or_comment(non_bool_op_idx):
			var identifier = ""
			var i = 0
			while i < type_hint.length():
				var _char = type_hint[i]
				if _char in Utils.Keywords.NON_BOOL_OPERATORS:
					break
				identifier += _char
				i += 1
			print("TYPE HINT::NON-BOOL::", type_hint, "::OP::", non_bool_op, "::ID::", identifier)
			return identifier.strip_edges()
	#TEST
	
	if _is_class_name_valid(type_hint):
		return type_hint
	
	return ""


func _get_script_member_type(line:int, column:int=0): # thjs could be a bit more efficient, if not needed, could use what you got already, 
	var code_edit_parser = _get_code_edit_parser() # but also maybe speeding up scan by not getting types could be good
	var get_type_data = code_edit_parser.get_type_from_line(line, column)
	var result = get_type_data.get("result")
	if result == null:
		return ""
	elif result is Array and result.is_empty():
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



func member_in_class_or_local_vars(identifier:String, class_obj:ParserClass, local_vars:Dictionary):
	return class_obj.has_script_member(identifier) or local_vars.has(identifier)

#^r THESE MAY BE OBSOLETE
func _find_inheriting_script(identifier:String, class_obj:ParserClass):
	var inherited_scripts = class_obj.get_inherited_scripts()
	for path in inherited_scripts:
		var parser_data = _get_parser_and_class_for_script(path)
		#var parser = _get_parser_for_script(path)
		var inh_class = parser_data.get(Keys.GET_CLASS_OBJ) as ParserClass
		if inh_class.has_script_member(identifier):
			return path
	return ""

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
#^r THESE MAY BE OBSOLETE


func _get_inherited_func_return(identifier:String, class_obj:ParserClass, inferred:=true):
	
	var member_data = class_obj.get_inherited_member(identifier)
	if member_data != null:
		var script_path = member_data.get(Keys.SCRIPT_PATH)
		if script_path != null:
			var access_path = member_data.get(Keys.ACCESS_PATH)
			var parser = _get_parser_for_script(script_path)
			var next_class = parser.get_class_object(access_path)
			var funct = next_class.get_function(identifier)
			if is_instance_valid(funct):
				return funct.get_return_type(inferred)
			return ""
	
	var inh_script_path = _find_member_inheriting_script(identifier, class_obj.script_resource)
	var parser_data = _get_parser_and_class_for_script(inh_script_path)
	#var parser = _get_parser_for_script(inh_script_path)
	#var inh_class_obj = parser.get_class_object()
	var inh_class_obj = parser_data.get(Keys.GET_CLASS_OBJ)
	var function = inh_class_obj.get_function(identifier) as ParserFunc
	if is_instance_valid(function):
		return function.get_return_type(inferred)
	return ""


func _get_parser_for_script(script_path:String):
	var parser = Utils.ParserRef.get_parser(self)
	return parser.get_parser_for_path(script_path)

func _get_parser_and_class_for_script(full_script_path:String):
	var parser = Utils.ParserRef.get_parser(self)
	var script_data = UString.get_script_path_and_suffix(full_script_path)
	var script_path = script_data[0]
	var class_access = script_data[1]
	return parser.get_parser_and_class_obj(script_path, class_access)


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
				


#! arg_location section:T
static func print_deb(section:String, ...msg:Array):
	if not PRINT_DEBUG:
		return
	if section in _PRINT:
		msg.push_front(section)
		ALibEditor.PrintDebug.print(msg)

const _PRINT = [
	#T.BUILTIN, 
	#T.INHERITED,
	#T.VAR_TO_CONST,
	#T.RESOLVE,
	#T.ACCESS_PATH
	]


class T:
	const RESOLVE = "RESOLVE"
	const BUILTIN = "BUILTIN"
	const INHERITED = "INHERITED"
	const VAR_TO_CONST = "VAR TO CONST"
	const ACCESS_PATH = "ACCESS PATH"
