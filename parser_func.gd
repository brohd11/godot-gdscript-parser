
const GDScriptParser = preload("uid://c4465kdwgj042") #! resolve ALibRuntime.Utils.UGDScript.Parser
const Utils = GDScriptParser.Utils
const UString = GDScriptParser.UString
const Keys = Utils.Keys
const ParserRef = Utils.ParserRef

@warning_ignore_start("unused_private_class_variable")
var _parser:WeakRef
var _class_obj:WeakRef
var _code_edit_parser:WeakRef
@warning_ignore_restore("unused_private_class_variable")

var _cache_dirty:=true

var _cache:= {} # not related to above member

var func_lines:PackedInt32Array
var declaration_line:int
var end_line:int
var class_indent:int = 0

var name:String
var member_data:={}

var _return_type_raw:= ""
var _return_type_raw_line:= -1
var _return_type:= "" # done
var arguments = {} # done

var _has_static_types:bool=false

## All mapped local vars in function.
var local_vars:= {}

## In scope local vars, set during type look up.
var in_scope_local_vars:= {}
var _local_vars_set:=false


func is_static():
	return member_data.get(Keys.MEMBER_TYPE, "").begins_with("static")

func queue_refresh():
	_cache_dirty = true
	_local_vars_set = false
	in_scope_local_vars.clear() # not sure how this will interact with parse
	
	# these are not related to type lookup local vars
	local_vars.clear()

func set_in_scope_local_vars(new_vars:Dictionary):
	_local_vars_set = true
	end_line = func_lines[func_lines.size() - 1]
	_set_function_data()
	in_scope_local_vars = new_vars
	in_scope_local_vars.merge(arguments.duplicate())

func parse():
	end_line = func_lines[func_lines.size() - 1]
	_set_function_data()
	map_variables()



func _set_function_data():
	if not _cache_dirty:
		return arguments
	
	var column:int = member_data.get(Keys.COLUMN_INDEX, 0)
	var code_edit_parser = ParserRef.get_code_edit_parser(self)
	if not code_edit_parser.check_member_line(member_data.get(Keys.MEMBER_TYPE), name, declaration_line, column):
		print("FUNCTION DATA: NOT VALID")
		return
	
	_has_static_types = true
	
	var func_data = code_edit_parser.get_type_from_line(declaration_line, column)
	
	arguments.clear()
	var result = func_data.get("result")
	_cache_dirty = false # at this point it has been read
	if result == null:
		_return_type_raw = ""
		return
	if not result is Dictionary:
		print(result, "::", name)
	
	var arg_data = result.get(Keys.FUNC_ARGS, {}) as Dictionary[String, Array]
	for arg in arg_data.keys():
		var arg_data_array = arg_data[arg] as Array[String]
		var arg_type = arg_data_array[1]
		var arg_assign = arg_data_array[2]
		var has_static_type = true
		if arg_type.is_empty():
			has_static_type = arg_data_array[3] # implicit type check
			arg_type = arg_assign
		elif not GDScriptParser.BuiltInChecker.is_variant_type(arg_type):
			arg_type = arg_type + Keys.INS_DELIM
		else:
			pass
		arguments[arg] = {
			Keys.TYPE: arg_type, 
			Keys.HAS_STATIC_TYPE: has_static_type,
			Keys.MEMBER_TYPE: Keys.MEMBER_TYPE_FUNC_ARG,
			Keys.LINE_INDEX: declaration_line
			}
	
	var ret_str = result.get(Keys.FUNC_RETURN, "")
	if ret_str != "":
		ret_str = Utils.type_path_add_ins(ret_str)
	else:
		_has_static_types = false
	_return_type_raw = ret_str
	
	#print("SET FUNC DATA: ", result)

func has_static_types():
	_set_function_data()
	return _has_static_types



## Scan current func for local vars and func data.
func map_variables() -> void:
	if not _cache_dirty:
		return
	var found_for_local_vars = {}
	
	_set_function_data()
	end_line = func_lines[func_lines.size() - 1]
	var code_edit_parser = ParserRef.get_code_edit_parser(self)
	for i in range(declaration_line + 1, end_line):
		if not code_edit_parser.is_valid_code(i, -1):
			continue
		
		var line_text = code_edit_parser.get_line(i)
		var stripped = line_text.strip_edges()
		var indent = code_edit_parser.get_indent_code_edit(i)
		var line_dec = GDScriptParser.CodeEditParser.get_line_declaration(stripped)
		if line_dec.is_empty() and not stripped.begins_with("for "):
			continue
		if indent <= class_indent:
			break
		
		
		var member_type = Keys.MEMBER_TYPE_VAR
		var is_for = stripped.begins_with("for ")
		if is_for: # this should be regex
			member_type = Keys.MEMBER_TYPE_FOR
		else:
			stripped = code_edit_parser.get_line_context_text(i)
		
		var var_data
		if is_for:
			var_data = Utils.get_for_loop_info(stripped)
		else:
			var_data = Utils.get_var_or_const_info(stripped)
		if var_data != null:
			var var_name = var_data[0]
			var type_hint = var_data[1]
			var has_static_type = true
			if type_hint.is_empty():
				if is_for:
					has_static_type = false
				else:
					has_static_type = var_data[3] # implicit type check
				type_hint = var_data[2]
			
			var data:= {
				Keys.MEMBER_NAME: var_name,
				Keys.LINE_INDEX: i,
				Keys.MEMBER_TYPE: member_type,
				Keys.TYPE: type_hint,
				Keys.HAS_STATIC_TYPE: has_static_type,
			}
			local_vars[i] = data
			found_for_local_vars[_get_cache_string(var_name, type_hint)] = true
	
	for key in arguments.keys():
		var type_hint = arguments[key].get(Keys.TYPE)
		found_for_local_vars[_get_cache_string(key, type_hint)] = true
	
	for key in _cache.keys():
		if not found_for_local_vars.has(key):
			_cache.erase(key)

func get_local_var_member_data(member_name:String, line_idx:int):
	if local_vars.has(line_idx):
		return local_vars.get(line_idx)
	elif arguments.has(member_name):
		return arguments.get(member_name)

func get_local_var_type(line_idx:int, member_name:String) -> String:
	var type_rich = get_local_var_type_rich(line_idx, member_name)
	if type_rich:
		return type_rich.type
	return ""

func get_local_var_type_rich(line_idx:int, member_name:String):
	var is_arg = arguments.has(member_name)
	var std_local = local_vars.has(line_idx)
	if not std_local and not is_arg:
		return GDScriptParser.TypeLookup.get_empty_type_rich()
	
	var parser = Utils.ParserRef.get_parser(self)
	var dec_line:int
	var var_data:Dictionary
	if is_arg:
		var_data = arguments.get(member_name)
		dec_line = declaration_line
	else:
		var_data = local_vars.get(line_idx)
		dec_line = var_data.get(Keys.LINE_INDEX)
	
	var type_hint = var_data.get(Keys.TYPE, "")
	if type_hint == "":
		return GDScriptParser.TypeLookup.get_empty_type_rich()
	
	var cache_string = _get_cache_string(member_name, type_hint)
	for i in range(1): # single loop for early break
		if not GDScriptParser.CACHE_TYPES:
			break
		if not _cache.has(cache_string):
			break
		var cache_data = _cache[cache_string]
		if cache_data.get(Keys.CLASS_CACHE_DEC) != type_hint:
			break
		var cached_deps = cache_data.get(Keys.CLASS_CACHE_DEPENDENCIES)
		if not GDScriptParser.InferenceContext.validate_dependencies(cached_deps, parser.get_script_path()):
			break
		
		return cache_data.get(Keys.CLASS_CACHE_TYPE)
	
	var cached_data = _cache.get_or_add(cache_string, {})
	cached_data[Keys.CLASS_CACHE_DEC] = type_hint
	
	dec_line += 1 # +1 forces the var to be in scope
	var type_rich = parser.resolve_expression_to_type_rich(member_name, dec_line)
	
	cached_data[Keys.CLASS_CACHE_DEPENDENCIES] = GDScriptParser.InferenceContext.get_dependencies_from_member_stack(type_rich)
	cached_data[Keys.CLASS_CACHE_TYPE] = type_rich
	return type_rich

func is_local_var_static_typed(line_idx:int, member_name:String):
	var is_arg = arguments.has(member_name)
	var std_local = local_vars.has(line_idx)
	if not std_local and not is_arg:
		return false
	
	var var_data:Dictionary
	if is_arg:
		var_data = arguments.get(member_name)
	else:
		var_data = local_vars.get(line_idx)
	return var_data.get(Keys.HAS_STATIC_TYPE, false)


func get_in_scope_local_vars(line:int):
	if _local_vars_set:
		return in_scope_local_vars
	
	var code_edit_parser = ParserRef.get_code_edit_parser(self)
	var context_data = code_edit_parser.get_line_context_start_data(line, {
		Keys.CONTEXT_BLOCKS: [Utils.Keywords.FOR]
		})
	var in_scope_vars = context_data.get(Keys.CONTEXT_LOCAL_VARS, {})
	in_scope_vars.merge(arguments)
	return in_scope_vars

func get_function_data():
	var return_string = get_return_type()
	return {Keys.FUNC_ARGS: arguments.duplicate(), Keys.FUNC_RETURN:return_string}

func get_arguments():
	_set_function_data()
	return arguments

func get_return_type(inferred:=true): # this could be used to parse
	_set_function_data()
	if _return_type_raw == "":
		_return_type_raw = _infer_return_type()
	
	if not inferred:
		return _return_type_raw
	
	if _return_type == "" or not Utils.is_absolute_path(_return_type):
		var parser = Utils.ParserRef.get_parser(self)
		var return_line = maxi(declaration_line, _return_type_raw_line)
		_return_type = parser.get_type_lookup().resolve_expression_to_type_at_line_respect_inf_context(_return_type_raw, return_line)
	
	if _return_type == "":
		_return_type = "Variant"
	
	_return_type = Utils.type_path_add_ins(_return_type)
	return _return_type

func get_return_type_raw():
	_set_function_data()
	if _return_type_raw == "":
		_return_type_raw = _infer_return_type()
	return _return_type_raw

func get_return_type_rich():
	_set_function_data()
	if _return_type_raw == "":
		_return_type_raw = _infer_return_type()
	
	var parser = Utils.ParserRef.get_parser(self)
	var return_line = maxi(declaration_line, _return_type_raw_line)
	var type_rich = parser.resolve_expression_to_type_rich(_return_type_raw, return_line)
	if type_rich.type == "":
		type_rich.type = "Variant"
	return type_rich

# this may be slowww, possibly do it in the mapping step
# other option would be to set a limit for indent, check only func level
func _infer_return_type() -> String:
	var code_edit_parser = Utils.ParserRef.get_code_edit_parser(self)
	var func_indent = class_indent + code_edit_parser.indent_size
	# technically this should be Variant, but this will behave similar to a return of a Variant where a return is necessary even if null
	# if not return statement at all is found, -> void, else Variant
	var potential_return = "void" 
	end_line = func_lines[func_lines.size() - 1]
	#var i = min(end_line + 1, code_edit_parser.code_edit.get_line_count() - 1)
	var i = end_line + 1
	while i > declaration_line + 1:
		i -= 1
		var line_text = code_edit_parser.get_line(i, true)
		if not line_text.strip_edges().begins_with("return"):
			continue
		if not code_edit_parser.is_valid_code(i, line_text.find("return")):
			continue
		var indent = code_edit_parser.get_indent_code_edit(i)
		
		potential_return = code_edit_parser.get_line_context(i, 0, false, {Keys.CONTEXT_START: i}).get(Keys.CONTEXT_TEXT, "")
		if indent == func_indent:
			break
		else:
			var valid = false
			var nest_i = i
			while nest_i > declaration_line:
				nest_i -= 1
				var line = code_edit_parser.get_line(nest_i, true, true)
				if line == "":
					continue
				if not code_edit_parser.is_valid_code(nest_i, 0):
					continue
				var nest_indent = code_edit_parser.get_indent_code_edit(nest_i)
				if nest_indent >= indent:
					continue
				var func_idx = line.find("func")
				if func_idx == -1:
					valid = true
					break
				i = nest_i - 1
				break
			if valid:
				break
	
	
	_return_type_raw_line = i
	var raw_result = potential_return.strip_edges().trim_prefix("return").strip_edges()
	if raw_result == "":
		return "Variant"
	
	#var parser = Utils.ParserRef.get_parser(self)
	#
	#_return_type = parser.resolve_expression_to_type(raw_result, i)
	#print("FUNC INFERRING::", raw_result, " -> ", _return_type)
	#print("FUNC INFER::", _return_type)
	return raw_result


func _get_cache_string(member_name:String, type_hint:String):
	return member_name + "::" + type_hint
