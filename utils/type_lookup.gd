
const PLUGIN_EXPORTED = false
const PRINT_DEBUG = true # not PLUGIN_EXPORTED

const GDScriptParser = preload("uid://c4465kdwgj042") #! resolve ALibRuntime.Utils.UGDScript.Parser

const VarInsertType = preload("res://addons/addon_lib/brohd/alib_runtime/utils/gdscript/parser/utils/type_lookup/var_insert_type.gd")

const UString = GDScriptParser.UString
const UFile = GDScriptParser.UFile
const UClassDetail = GDScriptParser.UClassDetail

const ParserClass = GDScriptParser.ParserClass
const ParserFunc = GDScriptParser.ParserFunc
const BuiltInChecker = GDScriptParser.BuiltInChecker
const Utils = GDScriptParser.Utils
const Keys = Utils.Keys
const AccessObject = GDScriptParser.Access.AccessObject
const InferenceContext = GDScriptParser.InferenceContext


const ENUM_SUFFIX = Keys.ENUM_PATH_SUFFIX
const CALLABLE_SUFFIX = "::CALLABLE"
const SIGNAL_SUFFIX = "::SIGNAL"

const OTHER_TYPES = ["void", "Variant"]
const CALL_METHODS = ["call", "callv", "call_deferred"]

const INDEX_PREFIX = &"%%INDEX"

static var _ternary_regex:RegEx
static var _ternary_if_regex:RegEx
static var _ternary_else_regex:RegEx
static var _as_regex:RegEx
static var _bitwise_op_regex:RegEx
static var _bool_op_regex:RegEx
static var _compar_op_regex:RegEx


var _parser:WeakRef
var code_edit:CodeEdit

var create_non_script_parsers:=true

var use_parsers_for_outside_script:=true

# for resolve inner class
var class_resolution:=false
var class_resolution_obj:ParserClass

#var _resolve_to_script:=false

var inference_context:InferenceContext
var _inf_weakref:WeakRef

func get_inference_context() -> InferenceContext:
	if _inf_weakref != null:
		return _inf_weakref.get_ref()
	return

func set_inference_context(inf:InferenceContext):
	_inf_weakref = weakref(inf)



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
	#print("GET FUNC DATA::", identifier , "::IN::", class_obj.get_script_class_path())
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
				#print("SIMPLE GET::", func_obj.get_function_data())
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
		var resolved_symbol = resolve_expression_to_type_at_line(access, line)
		#print("FUNC DATA::SYMBOL::", resolved_symbol)
		if resolved_symbol != "":
			if BuiltInChecker.is_builtin_class(resolved_symbol):
				#print("HAS SYMB::", resolved_symbol, "::ID::", identifier)
				calling_script_access = resolved_symbol
			else:
				var resolved_script = resolve_expression_to_type_at_line(resolved_symbol, line)
				#print("FUNC DATA::RESOLVED::", resolved_script)
				if not Utils.is_absolute_path(resolved_script):
				#if not resolved_script.begins_with("res://"):
					calling_script_access = resolved_script
				else:
					var script_data = UString.get_script_path_and_suffix(resolved_script)
					#print("FUNC DATA::SCRIPT::",script_data)
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
	#print("OUTSIDE::PATH::", script_path, "::ACCESS::", access_path, "::ID::", identifier)
	if script_path == "":
		return BuiltInChecker.get_func_data(access_path, identifier)
	#Color.html()
	
	var script = load(script_path)
	var parser = _get_parser_for_script(script_path)
	var class_obj = parser.get_class_object(access_path) as ParserClass
	var function = class_obj.get_function(identifier) as ParserFunc
	if is_instance_valid(function):
		#print("SIMPLE GET::", function.get_function_data())
		return function.get_function_data()
	
	#^r can this be removed
	var data = UClassDetail.get_member_info_by_path(script, UString.dot_join(access_path, identifier))
	if data != null:
		#print("MEMBER DATA::", data)
		var result = property_info_to_function_data(data)
		#print("MEMBER DATA::RESULT::", result)
		return result
	
	return {}


static func property_info_to_function_data(property_info:Dictionary):
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
		print("FUNC RET TYPE::", type)
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
	var result = _resolve_expression_to_val(expression, class_obj, local_vars)
	class_resolution = false
	var type_check = _simple_type_check(result)
	if type_check != "":
		return type_check
	return result


func resolve_expression_to_type_at_line(expression:String, line:int):
	if class_resolution == true:
		printerr("CLASS RES TRUE")
	class_resolution = false
	
	var result = resolve_expression_to_value_at_line(expression, line)
	
	_check_inf_on_exit()
	var type_check = _simple_type_check(result, true)
	if type_check != "":
		return type_check
	return result

func resolve_expression_to_value_at_line(expression:String, line:int):
	if class_resolution == true:
		printerr("CLASS RES TRUE")
	class_resolution = false
	
	var class_data = get_parser_objects_and_local_vars(line)
	var class_obj = class_data.class_obj
	
	var inf_context = _get_or_instance_inf_context()
	var inf_expression = _get_inf_expression(class_obj, expression)
	var inf_check = _check_inf_expression(inf_context, inf_expression)
	if inf_check != null:
		_check_inf_on_exit()
		return inf_check
	
	var local_vars = class_data.local_vars
	var result = _resolve_expression_to_val(expression, class_obj, local_vars)
	inf_context.finish_expression(inf_expression, result)
	_check_inf_on_exit()
	return result


func resolve_expression_to_type(expression: String, initial_class_obj: ParserClass, local_vars:Dictionary) -> String:
	var result = _resolve_expression_to_val(expression, initial_class_obj, local_vars)
	var type_check = _simple_type_check(result, true)
	if type_check != "":
		return type_check
	return result

func resolve_expression_to_value(expression: String, initial_class_obj: ParserClass, local_vars:Dictionary) -> String:
	return _resolve_expression_to_val(expression, initial_class_obj, local_vars)

# resolves expression to value
func _resolve_expression_to_val(expression: String, initial_class_obj: ParserClass, local_vars:Dictionary, recursions=0) -> String:
	if recursions >= 10:
		return "Variant"
	print_deb(T.RESOLVE, recursions, "CALLING AGAIN", expression)
	var parser = _get_parser()
	var main_script = parser.get_current_script()
	var main_script_path = main_script.resource_path
	
	if expression.begins_with("(") and expression.ends_with(")"):
		expression = expression.trim_prefix("(").trim_suffix(")")
	
	if Utils.is_absolute_path(expression):
		print_deb(T.RESOLVE, "EARLY EXIT", "BEGIN WITH RES", expression)
		var path = _ensure_valid_type_path(expression)
		return Utils.file_path_to_type(path)
		#return expression
	
	if expression == "self": # if self, we can just return the path to the class
		return UString.dot_join(main_script_path, initial_class_obj.access_path)
	elif expression.begins_with("self."):
		expression = expression.trim_prefix("self.")
	
	#if _valid_identifier(expression): #^ this causes issues with vars shadowing class member or globals
		#print_deb(T.RESOLVE, "EARLY EXIT", "IS VALID", expression) #^ observe for issues, but seems OK so far
		#if initial_class_obj.class_has_member(expression):
			#return get_class_member_type(initial_class_obj.script_base_type, expression)
		#return expression
	
	#var simple_check = _simple_type_check(expression)
	#if simple_check != "":
		#print_deb(T.RESOLVE, "EARLY EXIT", "IS SIMPLE", expression)
		#return expression
	
	
	var tern_check = _check_for_ternary_operation(expression, initial_class_obj, local_vars)
	if tern_check != "":
		#print("TERN::", expression, " -> ", tern_check)
		return tern_check
	var bool_bit_check = _check_for_bool_or_bitwise_operation(expression)
	if bool_bit_check != "":
		#print("COMPCHECK::bool::", expression, " -> ", bool_bit_check)
		return bool_bit_check
	var comp_check = _check_for_math_operation(expression)
	if comp_check != "":
		#print("COMPCHECK::", expression, " -> ", comp_check)
		expression = comp_check
	
	var simple_check = _simple_type_check(expression)
	if simple_check != "":
		print_deb(T.RESOLVE, "EARLY EXIT", "IS SIMPLE", expression)
		return expression
	
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
	#print("GET IDEN::LOCAL_VARS::", parts)
	#print("GET IDEN::LOCAL_VARS::", local_vars.keys())
	
	#var is_awaited = recursion_data.get("await", false)
	var is_awaited = false
	
	var count = 0
	while parts.size() > 0 and count < 10:
		count += 1
		var current_part: String = parts.pop_front()
		
		if current_part.begins_with("await "):
			is_awaited = true
			#recursion_data["await"] = true
			current_part = current_part.get_slice("await ", 1).strip_edges()
		
		var is_func = current_part.find("(") != -1
		var identifier = current_part.split("(", false, 1)[0] if is_func else current_part
		identifier = identifier.strip_edges()
		var is_callable = current_type_path.ends_with(CALLABLE_SUFFIX) # or BuiltInChecker.class_has_method(current_type_path, identifier)
		var is_signal = current_type_path.ends_with(SIGNAL_SUFFIX)
		
		if is_func and identifier == "new":
			if current_type_path == "":
				current_type_path = current_class_obj.get_script_class_path()
			continue
		
		var resolved_type = ""
		
		if not current_part.begins_with(INDEX_PREFIX):
			var index_access = not current_part.begins_with("[") and current_part.ends_with("]")
			if index_access:
				var all_index_access = get_index_access_in_string(current_part)
				for string in all_index_access:
					parts.push_front(INDEX_PREFIX + string)
			
			if not is_func:
				identifier = current_part.get_slice("[", 0)
			# proceed to process the identifier
		else:
			var identifier_name = current_part.trim_prefix(INDEX_PREFIX).trim_prefix("[").trim_suffix("]")
			if UString.is_string_or_string_name(identifier_name):
				identifier = UString.unquote(identifier_name)
			else:
				if current_type_path.begins_with("Array") or current_type_path.begins_with("Dictionary"):
					resolved_type = get_type_hint_from_collection(current_type_path)
				else:
					resolved_type = get_non_static_index(current_type_path)
		
		print_deb(T.RESOLVE, "CYCLE ----------")
		print_deb(T.RESOLVE, "CHECK", identifier, "CURRENT TYPE", current_type_path, "RAW", current_part, "RES", resolved_type)
		
		if identifier == "preload" and is_func:
			resolved_type = resolve_preload(current_part, current_class_obj)
		
		
		
		
		
		#if resolved_type == "":
		elif BuiltInChecker.is_builtin_class(identifier):
			resolved_type = identifier
		#elif UClassDetail.get_global_class_path(identifier) != "": # TEST removing this here so that shadowed vars are correctly identified
			#resolved_type = UClassDetail.get_global_class_path(identifier) # TEST watch for issues caused by it's absence
		elif _class_has_member(current_type_path, identifier) or is_callable:
			
			if not is_callable:
				if is_func:
					resolved_type = get_class_member_type(current_type_path, identifier)
				elif BuiltInChecker.class_has_signal(current_type_path, identifier):
					if is_awaited:
						resolved_type = get_class_member_type(current_type_path, identifier)
					else:
						resolved_type = UString.dot_join(current_type_path, identifier) + SIGNAL_SUFFIX
						#resolved_type = "Signal"
				elif not BuiltInChecker.class_has_method(current_type_path, identifier):
					resolved_type = get_class_member_type(current_type_path, identifier)
				else:
					resolved_type = UString.dot_join(current_type_path, identifier) + CALLABLE_SUFFIX
			else:
				if identifier in CALL_METHODS:
					var trimmed_type_path = current_type_path.trim_suffix(CALLABLE_SUFFIX)
					if Utils.is_absolute_path(current_type_path):
						identifier = UString.get_member_access_back(trimmed_type_path)
						is_func = true
					else:
						var builtin = ""
						var method_name = trimmed_type_path
						if current_type_path.contains("."):
							builtin = trimmed_type_path.get_slice(".", 0)
							method_name = trimmed_type_path.get_slice(".", 1)
						resolved_type = get_class_member_type(builtin, method_name)
					
				else:
					resolved_type = get_class_member_type("Callable", identifier)
					if resolved_type == "Callable":
						resolved_type = current_type_path
			
			# this would clash with below method?e
			#print("EXIT::", current_type_path, ".", identifier, " -> ", resolved_type)
	
	
		if resolved_type == "": # seems to be really only fired by dictionary.get()
			if current_class_obj.class_has_member(identifier):
				print("EXIT CLASS HAS MEMBER::", current_class_obj.get_script_class_path(),"::", identifier)
				if is_func and identifier in CALL_METHODS:
					var meth_str = Utils.get_string_inside_brackets(current_part)
					if meth_str != "":
						identifier = meth_str
						is_func = true
				elif identifier != "get":
					return get_class_member_type(current_class_obj.script_base_type, identifier)
				elif is_func and Utils.is_absolute_path(current_type_path):
					var prop_str = Utils.get_string_inside_brackets(current_part)
					if prop_str != "":
						identifier = prop_str
						is_func = false
				else: # get can be tricky, the built in returns Nil, but we can attempt to infer more. Maybe limit to Dictionary?
					resolved_type = _resolve_builtin_class_member(current_part, current_type_path, current_class_obj, local_vars)
		
		
		
		if resolved_type == "":
			if current_part_in_script: #^ --- IN SCRIPT ---
				print_deb(T.RESOLVE, "IN_SCRIPT", identifier, "IN", main_script_path, "CLASS", current_class_obj.access_path)
				print_deb(T.RESOLVE, "CLASS OR LOCAL" if member_in_class_or_local_vars(identifier, current_class_obj, local_vars) else "NON SCRIPT")
				
				if member_in_class_or_local_vars(identifier, current_class_obj, local_vars):
					if is_func:
						resolved_type = _resolve_process_in_script_data(identifier, current_class_obj, local_vars)
					elif current_class_obj.has_script_signal(identifier):
						if is_awaited:
							var args = current_class_obj.get_script_signal_args(identifier)
							if args == null:
								resolved_type = ""
							elif args.is_empty():
								resolved_type = "void"
							elif args.size() > 1:
								resolved_type = "Array"
							else:
								var first_type = args[args.keys()[0]]
								resolved_type = first_type
						else:
							var class_path = current_type_path
							if class_path == "":
								class_path = current_class_obj.get_script_class_path()
							resolved_type = UString.dot_join(class_path, identifier + SIGNAL_SUFFIX)
					elif not current_class_obj.has_function(identifier):
						resolved_type = _resolve_process_in_script_data(identifier, current_class_obj, local_vars)
					else:
						if current_class_obj.has_function(identifier):
							var class_path = current_type_path
							if class_path == "":
								class_path = current_class_obj.get_script_class_path()
							resolved_type = UString.dot_join(class_path, identifier + CALLABLE_SUFFIX)
					
				else:
					resolved_type = _get_inherited_member_type(current_part, current_class_obj)
				
			else: #^ --- OUTSIDE SCRIPT ---
				#if current_type_path.begins_with("res://"):
				if Utils.is_absolute_path(current_type_path):
					if is_func:
						identifier = identifier + "()"
					resolved_type = _process_external_identifier(identifier, external_script_path, external_script_class_access)
					print_deb(T.RESOLVE, "EXTERNAL", "%s -> %s" % [identifier, resolved_type])
		
		
		#if resolved_type == "" and not current_type_path.begins_with("res://"):# pass through current part so that you can get full context
		if resolved_type == "" and not Utils.is_absolute_path(current_type_path):# pass through current part so that you can get full context
			print_deb(T.RESOLVE, "OUTSIDE BUILT IN", identifier)
			resolved_type = _resolve_builtin_class_member(current_part, current_type_path, current_class_obj, local_vars) # ie. Dictionary.get(), can infer default
		
		if resolved_type == "":
			print_deb(T.RESOLVE, "ATTEMPT GLOBAL", identifier)
			resolved_type = UClassDetail.get_global_class_path(identifier) # YOUR IMPLEMENTATION
		
		print_deb(T.RESOLVE, "BASE ID", resolved_type)
		
		
		if resolved_type == "":
			var part_simple_check = _simple_type_check(current_part)
			if part_simple_check != "":
				resolved_type = part_simple_check
		
		#^ --- HANDLE THE RESULT ---
		
		if resolved_type is not String and resolved_type is not StringName:
			resolved_type = ""
		if resolved_type == "": # If we hit a dead end (untyped var, unknown function)
			print_deb(T.RESOLVE, "RETURN FAIL", expression)
			return ""
		if resolved_type == expression:
			print_deb(T.RESOLVE, "RETURN FAIL", "RESOLVE EQ EXP", expression)
			return ""
		
		if parts.size() > 0:
			var resolved_simple_check = _simple_type_check(resolved_type)
			if resolved_simple_check != "":
				resolved_type = resolved_simple_check
		
		# RECURSION CHECK: Did the variable return a literal expression instead of a parsed type?
		# e.g., local_vars["my_var"] resulted in the string "SomeClass.get_instance()"
		# We must resolve that expression into a true path before continuing!
		if _is_unresolved_expression(resolved_type):
			print_deb(T.RESOLVE, "UNRESOLVED RECURSING", resolved_type)
			# Pass the initial context because expressions are evaluated where they were declared!
			var recursive = _resolve_expression_to_val(resolved_type, initial_class_obj, local_vars, recursions + 1)
			if recursive != resolved_type:
				print_deb(T.RESOLVE, "RECURSE RESOLVED TYPE %s -> %s" %[resolved_type, recursive])
				resolved_type = recursive
			else:
				print_deb(T.RESOLVE, "RECUR == INPUT", resolved_type)
				return ""
		else:
			print_deb(T.RESOLVE, "RESOLVED_EXPRESSION", resolved_type)
		
		if resolved_type == expression:
			return ""
		
		if resolved_type.ends_with(Keys.ENUM_PATH_SUFFIX):
			return resolved_type
		
		#if not resolved_type.begins_with("res://"):
		if not Utils.is_absolute_path(resolved_type):
			current_part_in_script = false
		else:
			var script_data = UString.get_script_path_and_suffix(resolved_type)
			var current_script_path = script_data[0]
			var access_path = script_data[1]
			var suffix = path_has_suffix(access_path)
			if not suffix.is_empty():
				if access_path.contains("."):
					access_path = UString.trim_member_access_back(access_path)
				else:
					access_path = ""
			
			current_part_in_script = resolved_type.begins_with(main_script_path)
			if current_part_in_script:
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
		
		if is_awaited and resolved_type.ends_with(SIGNAL_SUFFIX):
			var type_path = ""
			var signal_name = resolved_type.trim_suffix(SIGNAL_SUFFIX)
			if resolved_type.contains("."):
				signal_name = UString.get_member_access_back(signal_name)
				type_path = UString.trim_member_access_back(resolved_type)
			parts.push_front(signal_name)
			current_type_path = type_path
		else:
			current_type_path = resolved_type # last thing
	
	print_deb(T.RESOLVE, "RETURN", str(recursions), " ==== ", current_type_path)
	
	#if current_type_path.begins_with("res://"):
	if Utils.is_absolute_path(current_type_path):
		current_type_path = _ensure_valid_type_path(current_type_path)
		current_type_path = Utils.file_path_to_type(current_type_path)
	return current_type_path


func _is_unresolved_expression(identifier:String):
	#if identifier.begins_with("res://"):
	if _simple_type_check(identifier) != "":
		return false
	if Utils.is_absolute_path(identifier):
		return false
	elif _valid_identifier(identifier):
		return false
	elif identifier.begins_with("typedarray::"):
		return false
	elif identifier.ends_with(CALLABLE_SUFFIX):
		return false
	elif identifier.ends_with(SIGNAL_SUFFIX):
		return false
	elif identifier.find(".") > -1:
		var sm = Utils.ParserRef.get_parser(self).get_string_map(identifier)
		var front = UString.get_member_access_front(identifier, sm)
		var back = UString.trim_member_access_front(identifier, sm)
		if ClassDB.class_exists(front):
			if ClassDB.class_has_enum(front, back):
				return false
		#if _class_has_member(front, back):
			#return false
		return true
	return true


func _resolve_process_in_script_data(member_name:String, class_obj:ParserClass, local_vars:Dictionary):
	var count = 0
	var result = member_name
	while member_in_class_or_local_vars(result, class_obj, local_vars):
		count += 1
		if count > 50:
			#print("COUNTED OUT")
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
			#print(identifier, args)
			args = args.substr(0, args.rfind(")"))
			if args.find(",") == -1:
				return "Variant"
			type_to_check = args.get_slice(",", 1).strip_edges()
			method_handled = true
	
	#if Utils.is_absolute_path(current_type_path): 
		#if identifier.begins_with("get"):
			#var args = identifier.get_slice("(", 1)
			##print(identifier, args)
			#args = args.substr(0, args.rfind(")"))
			#if args.find(",") == -1:
				#return "Variant"
			#type_to_check = args.get_slice(",", 1).strip_edges()
			#method_handled = true
	
	if not method_handled and BuiltInChecker.is_builtin_class(current_type_path):
		var return_type = BuiltInChecker.get_func_return(current_type_path, stripped_identifer)
		print_deb(T.BUILTIN, "ID", stripped_identifer, "RETURN", return_type)
		return return_type
	
	if not method_handled and BuiltInChecker.is_global_method(stripped_identifer):
		var return_type = BuiltInChecker.get_global_func_return(stripped_identifer)
		print_deb(T.BUILTIN, "ID", stripped_identifer, "RETURN", return_type)
		return return_type
	
	if type_to_check == "":
		return ""
	#var check = _simple_type_check(type_to_check)
	#if check != "":
		#return check
	
	return type_to_check



func _process_external_identifier(identifier:String, script_path:String, class_access_path:String = ""):
	var type = ""
	var t = ALibRuntime.Utils.UProfile.TimeFunction.new("OUTSIDE PARSER: " + identifier + " -> " + str(script_path.get_file()))
	var external_parser = _get_parser_for_script(script_path)
	#print(script_path, "::", class_access_path, "::", identifier)
	var class_obj = external_parser.get_class_object(class_access_path) as ParserClass
	print_deb(T.RESOLVE, "ATTEMPT_EXTERNAL", identifier, script_path, class_access_path)
	if is_instance_valid(class_obj):
		type = external_parser.resolve_expression_to_value(identifier, class_obj.line_indexes[0])
	print_deb(T.RESOLVE, "ATTEMPT_EXTERNAL_END", identifier, script_path, class_access_path)
	#t.stop()
	return type

#TODO this is using identifer every where, should it be stripped? _process_external needs the func'()' for proper callable management
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

func _ensure_valid_type_path(full_script_path:String):
	if full_script_path.begins_with("preload"):
		var const_data = Utils.get_var_or_const_info("const dummy = " + full_script_path)
		full_script_path = const_data[1]
		print("TYPE_PRELOAD::", full_script_path)
		## TEST
	var script_data = UString.get_script_path_and_suffix(full_script_path)
	var script_path = script_data[0]
	var class_access = script_data[1]
	if class_access == "":
		return full_script_path
	var parser = _get_parser_for_script(script_path)
	var suffix = path_has_suffix(class_access)
	if suffix != ENUM_SUFFIX:
		return full_script_path # does this need 
	elif suffix == ENUM_SUFFIX:
		var inner_class_check = ""
		var enum_name = class_access.trim_suffix(ENUM_SUFFIX)
		if enum_name.contains("."):
			inner_class_check = UString.trim_member_access_back(enum_name)
			enum_name = UString.get_member_access_back(enum_name)
		var class_obj = parser.get_class_object(inner_class_check) as ParserClass
		if is_instance_valid(class_obj):
			if class_obj.has_enum(enum_name):
				return full_script_path
	else:
		var class_obj = parser.get_class_object(class_access)
		if is_instance_valid(class_obj):
			return full_script_path
	
	
	#^ what is the reason for this? I think this should just return?
	print_deb(T.RESOLVE, "Ensure Valid Type Path - Recursing")
	return parser.resolve_expression_to_type(class_access, 0)


#endregion

#region Resolve Access Object

func resolve_expression_to_access_object_at_line(expression:String, line:int):
	if true:
		return _resolve_expression_to_access_object_at_line(expression, line)
	# the above will trigger the inference context object, bottom won't but is slightly more efficient
	var parser_data = get_parser_objects_and_local_vars(line)
	return resolve_expression_to_access_object(expression, parser_data.class_obj, parser_data.local_vars)

func _resolve_expression_to_access_object_at_line(expression: String, line):
	var parser = _get_parser()
	var main_script = parser.get_current_script()
	var main_script_path = main_script.resource_path
	
	var parser_data = get_parser_objects_and_local_vars(line)
	var initial_class_obj = parser_data.class_obj
	var local_vars = parser_data.local_vars
	
	#^ should this ever really be called? returns string instead of access_object, doesn't make sense to me..
	#if Utils.is_absolute_path(expression) and not expression.begins_with("preload"):
		#print_deb(T.VAR_TO_CONST, "EARLY EXIT", "BEGIN WITH RES", expression)
		#return expression
	
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
	#if dec_symbol.begins_with("res://"):
	if Utils.is_absolute_path(dec_symbol):
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
	#if access_symbol.begins_with("res://"):
	if Utils.is_absolute_path(access_symbol):
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
	
	access_object.declaration_type = resolve_expression_to_type_at_line(dec_symbol, line)
	#if access_object.declaration_type.begins_with("res://"):
	if Utils.is_absolute_path(access_object.declaration_type):
		var member_data = parser.get_member_info_from_script(access_object.declaration_type)
		if member_data != null:
			access_object.declaration_access_path = member_data.get(Keys.ACCESS_PATH)
	
	access_object.access_type = resolve_expression_to_type_at_line(access_symbol, line)
	
	print_deb(T.VAR_TO_CONST, "TYPE", access_object.declaration_type, "DEC",access_object.declaration_symbol, "ACCESS" ,access_object.access_symbol)
	return access_object

func resolve_expression_to_access_object(expression: String, initial_class_obj: ParserClass, local_vars:Dictionary):
	var parser = _get_parser()
	var main_script = parser.get_current_script()
	var main_script_path = main_script.resource_path
	
	#^ should this ever really be called? returns string instead of access_object, doesn't make sense to me..
	#if Utils.is_absolute_path(expression) and not expression.begins_with("preload"):
		#print_deb(T.VAR_TO_CONST, "EARLY EXIT", "BEGIN WITH RES", expression)
		#return expression
	
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
	#if dec_symbol.begins_with("res://"):
	if Utils.is_absolute_path(dec_symbol):
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
	#if access_symbol.begins_with("res://"):
	if Utils.is_absolute_path(access_symbol):
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
	
	access_object.declaration_type = _resolve_expression_to_val(dec_symbol, initial_class_obj, local_vars)
	#if access_object.declaration_type.begins_with("res://"):
	if Utils.is_absolute_path(access_object.declaration_type):
		var member_data = parser.get_member_info_from_script(access_object.declaration_type)
		if member_data != null:
			access_object.declaration_access_path = member_data.get(Keys.ACCESS_PATH)
	
	access_object.access_type = _resolve_expression_to_val(access_symbol, initial_class_obj, local_vars)
	
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
		#if result == next_result or next_result.begins_with("res://"):
		if result == next_result or Utils.is_absolute_path(next_result):
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
		#var not_valid = next_result == null or result == next_result or next_result.begins_with("res://")
		var not_valid = next_result == null or result == next_result or Utils.is_absolute_path(next_result)
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
	
	#if chain_text.begins_with("res://"):
	if Utils.is_absolute_path(chain_text):
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
			#if not type.begins_with("res://"):
			if not Utils.is_absolute_path(type):
				break
		working_path = UString.dot_join(working_path, part)
		var next_parser_data = parser.get_parser_and_class_obj_for_script(type)
		parser = next_parser_data.parser
		class_obj = next_parser_data.class_obj
		#var result = next_parser.
	
	return working_path

#endregion


#region Utils

func path_has_suffix(string:String) -> StringName:
	if string.ends_with(ENUM_SUFFIX):
		return ENUM_SUFFIX
	if string.ends_with(CALLABLE_SUFFIX):
		return CALLABLE_SUFFIX
	if string.ends_with(SIGNAL_SUFFIX):
		return SIGNAL_SUFFIX
	return &""

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
		
		
		
		
		#^r HERRRRRE
		
		#ALERT this is causing an issue for function return and signal inference.
		# if the top is uncommented, signals are resolved too much, if the bottom is not, returns aren't enough
		# perhaps the best bet is to refine signals further..
		#type_declaration = member_data.get_return_type(true)
		type_declaration = member_data.get_return_type(false, true)
		print_deb(T.RESOLVE, "GET FUNC", type_declaration)
		
		
		
		
		
		
		
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
		if type_declaration == "Signal":
			type_declaration = UString.dot_join(class_obj.get_script_class_path(), member_name + SIGNAL_SUFFIX)
		
		#prints(member_type, member_name, type_declaration)
		#^ handle for loop collection inference
		if not type_declaration.is_empty() and member_type == Keys.MEMBER_TYPE_FOR:
			if type_declaration.ends_with("values()") or type_declaration.ends_with("keys()"):
				var dict_path = UString.trim_member_access_back(type_declaration)
				var resolved_dict = resolve_expression_to_type_at_line(dict_path, line_index)
				type_declaration = get_type_hint_from_collection(resolved_dict, type_declaration.ends_with("values()"))
			else:
				var resolved_type = resolve_expression_to_type_at_line(type_declaration, line_index)
				
				type_declaration = get_type_hint_from_collection(resolved_type)
				print("RES::", resolved_type, " -> ", type_declaration)
				#if resolved_type.begins_with("Packed"):
					#type_declaration = resolved_type.get_slice("Packed", 1).get_slice("Array", 0)
				#else:
					#type_declaration = get_type_hint_from_collection(resolved_type)
	
	#var type_check = _simple_type_check(type_declaration)
	#if type_check != "":
		#print_deb(T.RESOLVE, "TYPE CHECK SUCCESS: ", type_declaration, " -> ", type_check)
		#return type_check
	
	print_deb(T.RESOLVE, "FUNC OR VAR", type_declaration)
	
	return type_declaration



## Get script member info, ignores Godot Native class inheritance properties.
func get_script_member_info_by_path(script:GDScript, member_path:String, member_hints:=UClassDetail._MEMBER_ARGS, check_global:=true):
	return UClassDetail.get_member_info_by_path(script, member_path, member_hints, false, false, false, check_global)

func _valid_identifier(identifier:String):
	if _is_class_name_valid(identifier): # don't allow global so they are resolved to script.
		return true
	#if BuiltInChecker.is_global_method(identifier):
		#return true
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


# Can I combine this with get_class member? or maybe just add a bool check to builtin checker
## Check that ClassDB class contains member.
func _class_has_member(base_type:String, identifier:String):
	if base_type.begins_with("Array"):
		base_type = "Array"
	elif base_type.begins_with("Dictionary"):
		base_type = "Dictionary"
	
	# this should be sufficient for this check
	return BuiltInChecker.class_has_member(base_type, identifier)
	
	#if not ClassDB.class_exists(base_type):
		#return false
	#if ClassDB.class_has_enum(base_type, identifier):
		#return true
	#elif ClassDB.class_has_integer_constant(base_type, identifier):
		#return true
	#elif ClassDB.class_has_method(base_type, identifier):
		#return true
	#elif ClassDB.class_has_signal(base_type, identifier):
		#return true
	##var prop_list = ClassDB.class_get_property_list(base_type)
	##print("HAS MEMBER")
	##for p:Dictionary in prop_list:
		##print(p)
		##if p.name == identifier:
			##return true
	#return false

static func get_class_member_type(base_type:String, identifier:String, resolve_const:=false):
	if base_type.contains("["):
		if base_type.begins_with("Array"):
			base_type = "Array"
		elif base_type.begins_with("Dictionary"):
			if identifier == "keys":
				return "Array[%s]" % get_type_hint_from_collection(base_type)
			elif identifier == "values":
				return "Array[%s]" % get_type_hint_from_collection(base_type, true)
			else:
				base_type = "Dictionary"
	
	# this is special for these, can either handle 'enum::SomeEnum' or keep these
	if ClassDB.class_has_enum(base_type, identifier):
		if resolve_const:
			return "Enum"
		return UString.dot_join(base_type, identifier)
	elif ClassDB.class_has_integer_constant(base_type, identifier):
		if resolve_const:
			return "int"
		return UString.dot_join(base_type, identifier)
	
	
	return BuiltInChecker.get_member_type(base_type, identifier)
	
	#if BuiltInChecker.is_builtin_class(base_type): # this checks seems to be handling things fine
		#return BuiltInChecker.get_member_type(base_type, identifier)
	
	#if ClassDB.class_has_enum(base_type, identifier):
		#if resolve_const:
			#return "Enum"
		#return UString.dot_join(base_type, identifier)
	#elif ClassDB.class_has_integer_constant(base_type, identifier):
		#if resolve_const:
			#return "int"
		#return UString.dot_join(base_type, identifier)
	#elif ClassDB.class_has_signal(base_type, identifier):
		#return "Signal"
	#elif ClassDB.class_has_method(base_type, identifier):
		#var func_data_array = ClassDB.class_get_method_list(base_type)
		#for d in func_data_array:
			#if d.name != identifier:
				#continue
			#
			#var resolved_data = property_info_to_function_data(d)
			#return resolved_data.get(Keys.FUNC_RETURN)
	##var prop_list = ClassDB.class_get_property_list(base_type)
	##for p:Dictionary in prop_list:
		##if identifier.begins_with(p.get("hint_string"), ""):
			##return 
			##
	#return ""


func _property_info_to_type_no_class(property_info) -> String:
	if property_info is Dictionary:
		if property_info.has("return"):
			property_info = property_info.get("return", {})
		
		if property_info.has("class_name"):
			var _class_name = property_info.get("class_name")
			if _class_name == "":
				var type = property_info.get("type")
				return type_string(type)
			
			#if not _class_name.begins_with("res://"):
			if not Utils.is_absolute_path(_class_name):
				return _class_name
			return _class_name # return class name as path or class to process elsewhere
		
	elif property_info is GDScript:
		return property_info.resource_path
	
	if PRINT_DEBUG:
		printerr("UNHANDLED PROPERTY INFO OR UNFOUND: ", property_info)
	return ""



func _simple_type_check(type_hint:String, exit_check:=false):
	_initialize_op_regexes()
	var as_check = _check_for_type_cast(type_hint)
	if as_check != "":
		return as_check
	
	# TEST remove this from here, forces a recursion instead of allowing SomeClass.new()
	#if type_hint.find(".new(") > -1:
		#type_hint = type_hint.substr(0, type_hint.find(".new(")) # was rfind, prob should be find?
		#if _is_class_name_valid(type_hint):
			#return type_hint
	# TEST
	
	if exit_check:
		if type_hint.ends_with(CALLABLE_SUFFIX):
			return "Callable"
		if type_hint.ends_with(SIGNAL_SUFFIX):
			return "Signal"
	
	
	if BuiltInChecker.is_builtin_class(type_hint):
		return type_hint
	if type_hint in OTHER_TYPES:
		return type_hint
	if type_hint.begins_with("uid:"):
		return UFile.uid_to_path(type_hint)
	#if type_hint.begins_with("res://"):
	if Utils.is_absolute_path(type_hint):
		return Utils.file_path_to_type(type_hint) # do this here?
		#return type_hint
	
	
	
	#TEST can remove this?
	#var bool_bit_check = _check_for_bool_or_bitwise_operation(type_hint)
	#if bool_bit_check != "":
		#return bool_bit_check
	#TEST
	
	if type_hint == "true" or type_hint == "false":
		return "bool"
	elif type_hint.is_valid_int():
		return "int"
	elif type_hint.is_valid_float():
		return "float"
	elif type_hint.begins_with("[") and type_hint.ends_with("]"):
		return "Array"
	elif type_hint.begins_with("{") and type_hint.ends_with("}"):
		return "Dictionary"
	elif type_hint.begins_with("&"):
		if Utils.token_is_string(type_hint.trim_prefix("&")):
			return "StringName"
	elif type_hint.begins_with("^"):
		if Utils.token_is_string(type_hint.trim_prefix("^")):
			return "NodePath"
	elif Utils.token_is_string(type_hint):
		return "String"
	elif type_hint.begins_with("typedarray::"):
		return "Array[%s]" % type_hint.get_slice("::", 1)
	elif type_hint.begins_with("Array"): # for Array[SomeType]
		var arr_hint = type_hint.get_slice("Array", 1).strip_edges()
		if arr_hint.begins_with("["):
			return "Array" + arr_hint
	elif type_hint.begins_with("Dictionary"): # for keyed dicts Dictionary[Key, Val]
		var type_pair = type_hint.get_slice("Dictionary", 1).strip_edges()
		if type_pair.begins_with("["):
			return "Dictionary" + type_pair
	elif type_hint.begins_with("f"): # will this cause issues?
		if type_hint.begins_with("func ") or type_hint.begins_with("func("):
			return "Callable"
	
	
	#if _is_class_name_valid(type_hint):
		#return type_hint
	
	if ClassDB.class_exists(type_hint):
		return type_hint
	var current_script = _get_parser_main_script()
	var base = current_script.get_instance_base_type()
	if (ClassDB.class_has_enum(base, type_hint) or ClassDB.class_has_integer_constant(base, type_hint) or 
	ClassDB.class_has_method(base, type_hint) or ClassDB.class_has_signal(base, type_hint)):
		return UString.dot_join(base, type_hint)
	
	
	return ""

static func get_type_hint_from_collection(string:String, value:bool=false) -> String:
	if string.begins_with("Packed"):
		return get_non_static_index(string)
	if not string.contains("["):
		return "Variant"
	if string.begins_with("Array"):
		return string.get_slice("[", 1).get_slice("]", 0).strip_edges()
	elif string.begins_with("Dictionary"):
		var key_pair = string.get_slice("[", 1).get_slice("]", 0)
		if value:
			return key_pair.get_slice(",", 1).strip_edges()
		else:
			return  key_pair.get_slice(",", 0).strip_edges()
	return "Variant"

func get_index_access_in_string(string:String):
	var string_map:GDScriptParser.UString.StringMap = _get_parser().get_string_map(string)
	var matches = []
	var i = 0
	while i < string.length():
		if string_map.string_mask[i] == 1:
			i += 1
			continue
		var _char = string[i]
		if _char == "[":
			var close = string_map.bracket_map[i] + 1
			matches.append(string.substr(i, close - i))
			i = close
			continue
		
		i += 1
	matches.reverse()
	return matches

static func get_non_static_index(type:String):
	match type:
		"PackedByteArray", "PackedInt32Array", "PackedInt64Array", "Vector2i", "Vector3i", "Vector4i":
			return "int"
		"PackedFloat32Array", "PackedFloat64Array", "Vector2", "Vector3", "Vector4", "Color":
			return "float"
		"PackedStringArray", "String", "StringName":
			return "String"
		"PackedVector2Array", "Transform2D":
			return "Vector2"
		"PackedVector3Array", "Basis":
			return "Vector3"
		"PackedColorArray":
			return "Color"
		_:
			return "Variant" # Not a known primitive index

func _check_for_type_cast(type_hint:String):
	_initialize_op_regexes()
	var parser = Utils.ParserRef.get_parser(self)
	var string_map:UString.StringMap
	var as_matches = _as_regex.search_all(type_hint)
	if not as_matches.is_empty():
		string_map = parser.get_string_map(type_hint)
		for m in as_matches:
			var i = m.get_start(0)
			if string_map.index_in_string_or_comment(i) or string_map.get_tightest_bracket_set(i) != -1:
				continue
			
			# this simplifies this alot! Seems to be functioning properly
			return m.get_string(1).strip_edges()
			
			#var cast_type_hint = type_hint.substr(i).trim_prefix("as")
			#if cast_type_hint.find("#") > -1:
				#cast_type_hint = cast_type_hint.get_slice("#", 0)
			#cast_type_hint = cast_type_hint.strip_edges()
			#print(cast_type_hint)
			#return cast_type_hint
			## ALERT valid asccii identifier causes chained access path to fail, what is the purpose?
			## ALERT for ternary and math problems?
			#if cast_type_hint.is_valid_ascii_identifier():
				#return cast_type_hint # return here, since this must a valid type of identifier?
			#else:
				#
				#break
	return ""


func _check_for_ternary_operation(text: String, class_obj:ParserClass, local_vars:Dictionary):
	_initialize_op_regexes()
	var parser = Utils.ParserRef.get_parser(self)
	var string_map = parser.get_string_map(text)
	
	var true_expr = ""
	var false_expr = ""
	
	for m in _ternary_if_regex.search_all(text):
		var i = m.get_start()
		if string_map.index_in_string_or_comment(i) or string_map.get_tightest_bracket_set(i) != -1:
			continue # Find the depth 0 'if'
		true_expr = text.substr(0, i).strip_edges()
		break
	
	if true_expr == "":
		return "" # no depth 0 'if', not ternary
	
	for m in _ternary_else_regex.search_all(text):
		var i = m.get_start()
		if string_map.index_in_string_or_comment(i) or string_map.get_tightest_bracket_set(i) != -1:
			continue # find the depth 0 'else'
		false_expr = text.substr(m.get_end()).strip_edges()
		break
	
	var true_type = resolve_expression_to_type(true_expr, class_obj, local_vars)
	var false_type = resolve_expression_to_type(false_expr, class_obj, local_vars)
	if true_type == false_type:
		return true_type
	else:
		return "Variant" # Mismatch! Fallback to Variant.


func _check_for_bool_or_bitwise_operation(type_hint:String):
	_initialize_op_regexes()
	var parser = Utils.ParserRef.get_parser(self)
	var string_map = parser.get_string_map(type_hint)
	var bit_matches = _bitwise_op_regex.search_all(type_hint)
	for m in bit_matches:
		var i = m.get_start(0)
		if string_map.index_in_string_or_comment(i):
			continue
		if string_map.get_tightest_bracket_set(i) != -1:
			continue
		return "int"
	
	var bool_matches = _bool_op_regex.search_all(type_hint)
	for m in bool_matches:
		var i = m.get_start(0)
		if string_map.index_in_string_or_comment(i):
			continue
		if string_map.get_tightest_bracket_set(i) != -1:
			continue
		return "bool"
	return ""


func _check_for_math_operation(type_hint:String):
	_initialize_op_regexes()
	var parser = Utils.ParserRef.get_parser(self)
	var string_map = parser.get_string_map(type_hint)
	var compare_matches = _compar_op_regex.search_all(type_hint)
	for m in compare_matches:
		var i = m.get_start(0)
		if string_map.get_tightest_bracket_set(i) != -1:
			continue
		if string_map.index_in_string_or_comment(i):
			continue
		var indentifier = type_hint.substr(0, i)
		return indentifier.strip_edges()
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
	if dec_type == Keys.MEMBER_TYPE_CONST or dec_type == Keys.MEMBER_TYPE_VAR or dec_type == Keys.MEMBER_TYPE_STATIC_VAR or dec_type == Keys.MEMBER_TYPE_FOR:
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


func resolve_preload(preload_call:String, class_obj:ParserClass):
	# at this point, this should not be a path, that would have been handled already
	var preload_string = preload_call.get_slice("preload", 1).strip_edges().trim_prefix("(").trim_suffix(")").strip_edges()
	var path
	if _compar_op_regex.search_all(preload_string).is_empty():
		print_deb(T.RESOLVE, "PRELOAD -> VAL_AT_LINE")
		var value = resolve_expression_to_value_at_line(preload_string, class_obj.line_indexes[0])
		path = Utils.get_full_path_from_string(value)
	else:
		path = Utils.run_expression(preload_string, class_obj.script_resource)
	
	if path == "":
		return ""
	if not Utils.is_absolute_path(path):
		path = Utils.ensure_absolute_path(path, class_obj.main_script_path)
	else:
		path = UFile.uid_to_path(path)
	
	return path


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


#region InferenceContext

func _get_or_instance_inf_context():
	var inf_context = get_inference_context()
	if not is_instance_valid(inf_context):
		inf_context = InferenceContext.new()
		inference_context = inf_context
		set_inference_context(inf_context)
	return inf_context

func _get_inf_expression(class_obj:ParserClass, expression:String):
	return class_obj.get_script_class_path() + "::" + expression

func _check_inf_expression(inf_context:InferenceContext, inf_expression:String):
	if inf_context.has_expression(inf_expression):
		inf_context.finish_expression(inf_expression, "Variant")
		return "Variant"
	else:
		inf_context.start_expression(inf_expression)
	

func _check_inf_on_exit():
	if is_instance_valid(inference_context):
		inference_context = null


#endregion


func _initialize_op_regexes():
	if not is_instance_valid(_ternary_if_regex):
		_ternary_if_regex = RegEx.new()
		_ternary_if_regex.compile("\\bif\\b")
	if not is_instance_valid(_ternary_else_regex):
		_ternary_else_regex = RegEx.new()
		_ternary_else_regex.compile("\\belse\\b")
	if not is_instance_valid(_ternary_regex):
		_ternary_regex = RegEx.new()
		_ternary_regex.compile("\\bif\\b.*?\\belse\\b")
	
	if not is_instance_valid(_as_regex):
		_as_regex = RegEx.new() # this should remove all doubt
		_as_regex.compile(r"\bas\s+([A-Za-z_][A-Za-z0-9_]*(\s*\.\s*[A-Za-z_][A-Za-z0-9_]*)*)")
		#_as_regex.compile("\\bas\\b")
	
	if not is_instance_valid(_bitwise_op_regex):
		_bitwise_op_regex = RegEx.new()
		_bitwise_op_regex.compile("(?:<<|>>|~|\\^(?![\"\'])|(?<!&)&(?!&|[\"\'])|(?<!\\|)\\|(?!\\|))")
	
	if not is_instance_valid(_bool_op_regex):
		_bool_op_regex = RegEx.new()
		_bool_op_regex.compile("(?:==|!=|<=|>=|<|>|&&|\\|\\||!|\\b(?:and|or|not)\\b)")
	
	if not is_instance_valid(_compar_op_regex):
		_compar_op_regex = RegEx.new()
		_compar_op_regex.compile("(?:\\*\\*|\\*|\\/|%|(?<![eE])[+\\-])")




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
	T.RESOLVE,
	#T.ACCESS_PATH
	]


class T:
	const RESOLVE = "RESOLVE"
	const BUILTIN = "BUILTIN"
	const INHERITED = "INHERITED"
	const VAR_TO_CONST = "VAR TO CONST"
	const ACCESS_PATH = "ACCESS PATH"
