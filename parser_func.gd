
const PLUGIN_EXPORTED = false

const GDScriptParser = preload("uid://c4465kdwgj042") #! resolve ALibRuntime.Utils.UGDScript.Parser
const CodeEditParser = GDScriptParser.CodeEditParser
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

var _cache:Dictionary = {} # not related to above member

var func_lines:PackedInt32Array
var declaration_line:int
var end_line:int
var class_indent:int = 0

var name:String
var member_data:Dictionary ={}

var empty_return_as_variant:bool =false # where to set this?
var _return_type_raw:String = ""
var _return_type_raw_line:int = -1
var _return_type:String = "" # done
var arguments:Dictionary = {} # done

var _has_static_return:bool=false

## All mapped local vars in function.
var local_vars:Dictionary = {}
var _local_vars_mapped:bool =false

## In scope local vars, set during type look up.
var in_scope_local_vars:Dictionary = {}
var _in_scope_local_vars_set:=false


func is_static() -> bool:
	return member_data.get(Keys.MEMBER_TYPE, "").begins_with("static")

func queue_refresh() -> void:
	_cache_dirty = true
	
	_in_scope_local_vars_set = false
	in_scope_local_vars.clear() # not sure how this will interact with parse
	
	# these are not related to type lookup local vars
	_local_vars_mapped = false
	local_vars.clear()

func set_in_scope_local_vars(new_vars:Dictionary) -> void:
	_in_scope_local_vars_set = true
	end_line = func_lines[func_lines.size() - 1]
	_set_function_data()
	in_scope_local_vars = new_vars
	in_scope_local_vars.merge(arguments.duplicate())

func parse() -> void:
	end_line = func_lines[func_lines.size() - 1]
	_set_function_data()
	map_variables()




func _set_function_data() -> void:
	if not _cache_dirty:
		return
	_return_type = "" # ensure this doesn't get stuck
	
	var column:int = member_data.get(Keys.COLUMN_INDEX, 0)
	var code_edit_parser:CodeEditParser = ParserRef.get_code_edit_parser(self)
	if not code_edit_parser.check_member_line(member_data.get(Keys.MEMBER_TYPE), name, declaration_line, column):
		GDScriptParser.print_deb_err(["FUNCTION DATA: NOT VALID"])
		return
	
	_has_static_return = true
	
	var func_data:Dictionary = code_edit_parser.get_type_from_line(declaration_line, column)
	
	arguments.clear()
	var result:Variant = func_data.get("result")
	_cache_dirty = false # at this point it has been read
	if result == null:
		_return_type_raw = ""
		return
	if not result is Dictionary:
		GDScriptParser.print_deb_err([result, "::", name])
		#_cache_dirty = true # should this reset? this shouldn't happen
		return
	
	var arg_data:Dictionary = result.get(Keys.FUNC_ARGS, {})
	for arg:String in arg_data.keys():
		var arg_data_array:Array = arg_data[arg]
		var arg_type:String = arg_data_array[1]
		var arg_assign:String = arg_data_array[2]
		var has_static_type:bool = true
		if arg_type.is_empty():
			has_static_type = arg_data_array[3] # implicit type check
			arg_type = arg_assign
		elif not GDScriptParser.BuiltInChecker.is_variant_type(arg_type):
			arg_type = arg_type + Keys.INS_DELIM
		else:
			pass
		arguments[arg] = {
			Keys.TYPE: arg_type,
			Keys.ASSIGNMENT: arg_assign,
			Keys.HAS_STATIC_TYPE: has_static_type,
			Keys.MEMBER_TYPE: Keys.MEMBER_TYPE_FUNC_ARG,
			Keys.LINE_INDEX: declaration_line
			}
	
	var ret_str:String = result.get(Keys.FUNC_RETURN, "")
	if ret_str != "":
		ret_str = Utils.type_path_add_ins(ret_str)
	else:
		_has_static_return = false
	_return_type_raw = ret_str
	
	#print("SET FUNC DATA: ", result)

func has_static_return() -> bool:
	_set_function_data()
	return _has_static_return



## Scan current func for local vars and func data.
func map_variables() -> void:
	#print("MAP:", name, ":", _local_vars_mapped)
	if _local_vars_mapped:
		return
	var found_for_local_vars:Dictionary = {}
	
	_set_function_data()
	end_line = func_lines[func_lines.size() - 1]
	var code_edit_parser:CodeEditParser = ParserRef.get_code_edit_parser(self)
	for i:int in range(declaration_line + 1, end_line + 1): # +1 to ensure last line is carried over
		if not code_edit_parser.is_valid_code(i, -1):
			continue
		
		var line_text:String = code_edit_parser.get_line(i)
		var stripped:String = line_text.strip_edges()
		var indent:int = code_edit_parser.get_indent_code_edit(i)
		var line_dec:StringName = GDScriptParser.CodeEditParser.get_line_declaration(stripped)
		if line_dec.is_empty() and not stripped.begins_with("for "):
			continue
		if indent <= class_indent:
			break
		
		var ctx_start_data = code_edit_parser.get_line_context_start_simple(i)
		var has_semi_cols:bool = ctx_start_data.get(Keys.CONTEXT_SEMI_COLON, false)
		
		
		if has_semi_cols:
			var data:Dictionary = code_edit_parser.get_semi_colon_strings(i)
			var cols = data.keys()
			var last_col = cols[cols.size() - 1]
			for column:int in cols:
				var text:String = data[column]
				if column == last_col:
					text = code_edit_parser.get_line_context_text(i, column)
				# column + 1 , accounts for the ';', works without, but mismatches with tree sitter
				_process_local_var(text.strip_edges(), i, column + 1, found_for_local_vars)
		else:
			var line_ctx:Dictionary = code_edit_parser.get_line_context(i)
			var context_text:String = line_ctx.get(Keys.CONTEXT_TEXT, "")
			var col:int = line_text.find(stripped)
			_process_local_var(context_text.strip_edges(), i, col, found_for_local_vars)
	
	for key:String in arguments.keys():
		var type_hint:String = arguments[key].get(Keys.TYPE)
		found_for_local_vars[_get_cache_string(key, type_hint)] = true
	
	for key:String in _cache.keys():
		if not found_for_local_vars.has(key):
			_cache.erase(key)
	
	_local_vars_mapped = true

func _process_local_var(stripped:String, line:int, col:int, found_vars:Dictionary) -> void:
	var member_type:StringName = Keys.MEMBER_TYPE_VAR
	var is_for:bool = stripped.begins_with("for ")
	if is_for: # this should be regex
		member_type = Keys.MEMBER_TYPE_FOR
	
	var var_data:Variant
	if is_for:
		var_data = Utils.get_for_loop_info(stripped)
	else:
		var_data = Utils.get_var_or_const_info(stripped)
	if var_data != null:
		var var_name:String = var_data[0]
		var type_hint:String = var_data[1]
		var has_static_type:bool = true
		if type_hint.is_empty():
			if is_for:
				has_static_type = false
			else:
				has_static_type = var_data[3] # implicit type check
		
		var data:Dictionary = {
			Keys.MEMBER_NAME: var_name,
			Keys.LINE_INDEX: line,
			Keys.MEMBER_TYPE: member_type,
			Keys.TYPE: type_hint,
			Keys.ASSIGNMENT: var_data[2],
			Keys.HAS_STATIC_TYPE: has_static_type,
		}
		var unique_name:String = "%s-%s-%s" % [var_name, line, col]
		local_vars[unique_name] = data
		found_vars[_get_cache_string(unique_name, type_hint)] = true
	

func get_local_var_member_data(member_name:String) -> Variant:
	if local_vars.has(member_name):
		return local_vars.get(member_name)
	elif arguments.has(member_name):
		return arguments.get(member_name)
	return

func get_local_var_type(member_name:String) -> String:
	var type_rich:Dictionary = get_local_var_type_rich(member_name)
	if type_rich:
		return type_rich.type
	return ""

func get_local_var_type_rich(member_name:String) -> Dictionary:
	var is_arg:bool = arguments.has(member_name)
	var std_local:bool = local_vars.has(member_name)
	if not std_local and not is_arg:
		return GDScriptParser.TypeLookup.get_empty_type_rich()
	
	var parser:GDScriptParser = Utils.ParserRef.get_parser(self)
	var dec_line:int
	var var_data:Dictionary
	if is_arg:
		var_data = arguments.get(member_name)
		dec_line = declaration_line
	else:
		var_data = local_vars.get(member_name)
		dec_line = var_data.get(Keys.LINE_INDEX)
	
	var type_hint:String = var_data.get(Keys.TYPE, "")
	if type_hint == "":
		type_hint = var_data.get(Keys.ASSIGNMENT, "")
	if type_hint == "":
		return GDScriptParser.TypeLookup.get_empty_type_rich()
	
	var cache_string:String = _get_cache_string(member_name, type_hint)
	for i:int in range(1): # single loop for early break
		#break # ALERT
		if not GDScriptParser.CACHE_TYPES:
			break
		if not _cache.has(cache_string):
			break
		var cache_data:Dictionary = _cache[cache_string]
		if cache_data.get(Keys.CLASS_CACHE_DEC) != type_hint:
			break
		if not cache_data.has(Keys.CLASS_CACHE_DEPENDENCIES):
			break
		var cached_deps:Variant = cache_data.get(Keys.CLASS_CACHE_DEPENDENCIES)
		if not GDScriptParser.InferenceContext.validate_dependencies(cached_deps, parser.get_script_path()):
			break
		return cache_data.get(Keys.CLASS_CACHE_TYPE)
	
	var cached_data:Dictionary = _cache.get_or_add(cache_string, {})
	cached_data[Keys.CLASS_CACHE_DEC] = type_hint
	
	if member_name.contains("-"):
		member_name = member_name.get_slice("-", 0)
	
	var probe_line := dec_line + 1   # +1 forces the var to be in scope
	var seeded := false
	if not func_lines.has(probe_line) and not _in_scope_local_vars_set:
		# Terminal var: probe_line escaped this func (EOF / next-decl no-blank).
		# Resolve on the var's OWN line (which IS in func_lines, so ClassData -> self),
		# pre-seeding an in-scope set that includes this var itself.
		var scope: Dictionary = get_in_scope_local_vars(dec_line)          # priors + args
		var line_text: String = ParserRef.get_code_edit_parser(self).get_line(dec_line)
		Utils.add_var_to_dict(line_text.strip_edges(), dec_line, 0, scope) # add the terminal var
		set_in_scope_local_vars(scope)
		seeded = true
		probe_line = dec_line
	
	var type_rich: Dictionary = parser.resolve_expression_to_type_rich(member_name, probe_line)
	if seeded:
		_in_scope_local_vars_set = false
		in_scope_local_vars.clear()
	
	if type_rich.type != "" and type_rich.origin != "":
		cached_data[Keys.CLASS_CACHE_DEPENDENCIES] = GDScriptParser.InferenceContext.get_dependencies_from_member_stack(type_rich)
		cached_data[Keys.CLASS_CACHE_TYPE] = type_rich
	return type_rich

func is_local_var_static_typed(member_name:String) -> bool:
	var is_arg:bool = arguments.has(member_name)
	var std_local:bool = local_vars.has(member_name)
	if not std_local and not is_arg:
		return false
	
	var var_data:Dictionary
	if is_arg:
		var_data = arguments.get(member_name)
	else:
		var_data = local_vars.get(member_name)
	return var_data.get(Keys.HAS_STATIC_TYPE, false)


func get_in_scope_local_vars(line:int) -> Dictionary:
	if _in_scope_local_vars_set:
		return in_scope_local_vars
	
	var code_edit_parser:CodeEditParser = ParserRef.get_code_edit_parser(self)
	var context_data:Dictionary = code_edit_parser.get_line_context_start_data(line, {
		Keys.CONTEXT_BLOCKS: [Utils.Keywords.FOR]
		})
	var in_scope_vars:Dictionary = context_data.get(Keys.CONTEXT_LOCAL_VARS, {})
	in_scope_vars.merge(arguments)
	return in_scope_vars

func get_function_data() -> Dictionary:
	var return_string:String = get_return_type()
	return {Keys.FUNC_ARGS: arguments.duplicate(), Keys.FUNC_RETURN:return_string}

func get_arguments_raw() -> Dictionary:
	var dict:Dictionary = {}
	if not _cache_dirty: # seems ok, but could this get out of sync?
		for a:String in arguments:
			dict[a] = true
		return dict
	
	var column:int = member_data.get(Keys.COLUMN_INDEX, 0)
	var code_edit_parser:CodeEditParser = ParserRef.get_code_edit_parser(self)
	if code_edit_parser.check_member_line(member_data.get(Keys.MEMBER_TYPE), name, declaration_line, column):
		var func_data:Dictionary = code_edit_parser.get_type_from_line(declaration_line, column)
		var result:Variant = func_data.get("result")
		if not result is Dictionary:
			GDScriptParser.print_deb_err(["GET ARG RAW", result, name])
			return {}
		if result:
			var func_args:Dictionary = result.get(Keys.FUNC_ARGS, {})
			for a:String in func_args:
				dict[a] = true
			return dict
	
	return {}
	

func get_arguments() -> Dictionary:
	_set_function_data()
	return arguments

func get_return_type(inferred:=true) -> String: # this could be used to parse
	_set_function_data()
	
	if _return_type_raw == "":
		_return_type_raw = _infer_return_type()
	
	if not inferred:
		return _return_type_raw
	
	if _return_type == "" or not Utils.is_absolute_path(_return_type):
		var parser:GDScriptParser = Utils.ParserRef.get_parser(self)
		var return_line:int = maxi(declaration_line, _return_type_raw_line)
		_return_type = parser.get_type_lookup().resolve_expression_to_type_at_line_respect_inf_context(_return_type_raw, return_line)
	
	if _return_type == "":
		_return_type = "Variant"
	
	_return_type = Utils.type_path_add_ins(_return_type)
	return _return_type

func get_return_type_raw() -> String:
	_set_function_data()
	if _return_type_raw == "":
		_return_type_raw = _infer_return_type()
	return _return_type_raw

func get_return_type_rich() -> Dictionary:
	_set_function_data()
	if _return_type_raw == "":
		_return_type_raw = _infer_return_type()
	
	var parser:GDScriptParser = Utils.ParserRef.get_parser(self)
	var return_line:int = maxi(declaration_line, _return_type_raw_line)
	var type_rich:Dictionary = parser.resolve_expression_to_type_rich(_return_type_raw, return_line)
	if type_rich.type == "":
		type_rich.type = "Variant"
	return type_rich

# this may be slowww, possibly do it in the mapping step
# other option would be to set a limit for indent, check only func level
func _infer_return_type() -> String:
	var code_edit_parser:CodeEditParser = Utils.ParserRef.get_code_edit_parser(self)
	var func_indent:int = class_indent + code_edit_parser.indent_size
	# technically this should be Variant, but this will behave similar to a return of a Variant where a return is necessary even if null
	# if not return statement at all is found, -> void, else Variant
	var potential_return:String = "void" 
	end_line = func_lines[func_lines.size() - 1]
	#var i = min(end_line + 1, code_edit_parser.code_edit.get_line_count() - 1)
	var i:int = end_line + 1
	while i > declaration_line + 1:
		i -= 1
		var line_text:String = code_edit_parser.get_line(i, true)
		if not line_text.strip_edges().begins_with("return"):
			continue
		if not code_edit_parser.is_valid_code(i, line_text.find("return")):
			continue
		var indent:int = code_edit_parser.get_indent_code_edit(i)
		
		potential_return = code_edit_parser.get_line_context(i, 0, false, {Keys.CONTEXT_START: i}).get(Keys.CONTEXT_TEXT, "")
		if indent == func_indent:
			break
		else:
			var valid:bool = false
			var nest_i:int = i
			while nest_i > declaration_line:
				nest_i -= 1
				var line:String = code_edit_parser.get_line(nest_i, true, true)
				if line == "":
					continue
				if not code_edit_parser.is_valid_code(nest_i, 0):
					continue
				var nest_indent:int = code_edit_parser.get_indent_code_edit(nest_i)
				if nest_indent >= indent:
					continue
				var func_idx:int = line.find("func")
				if func_idx == -1:
					valid = true
					break
				i = nest_i - 1
				break
			if valid:
				break
	
	
	_return_type_raw_line = i
	var raw_result:String = potential_return.strip_edges().trim_prefix("return").strip_edges()
	if raw_result == "":
		if empty_return_as_variant:
			return "Variant"
		return "void"
	
	#var parser = Utils.ParserRef.get_parser(self)
	#
	#_return_type = parser.resolve_expression_to_type(raw_result, i)
	#print("FUNC INFERRING::", raw_result, " -> ", _return_type)
	#print("FUNC INFER::", _return_type)
	return raw_result


func _get_cache_string(member_name:String, type_hint:String) -> String:
	return member_name + "::" + type_hint
