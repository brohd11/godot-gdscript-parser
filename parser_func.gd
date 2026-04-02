
const GDScriptParser = preload("res://addons/addon_lib/brohd/alib_runtime/utils/resource/gdscript/parser/gdscript_parser.gd")
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

var func_lines:PackedInt32Array
var declaration_line:int
var end_line:int
var class_indent:int = 0

var name:String
var member_data:={}

var _return_type_raw:= ""
var _return_type := "" # done
var arguments = {} # done

var local_vars:= {}

var in_scope_local_vars:= {}
var _local_vars_set:=false


func is_static():
	return member_data.get(Keys.MEMBER_TYPE, "").begins_with("static")

func queue_refresh():
	_cache_dirty = true
	_local_vars_set = false
	in_scope_local_vars.clear() # not sure how this will interact with parse

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
	#var parser = Utils.ParserRef.get_parser(self)
	var column = member_data.get(Keys.COLUMN_INDEX, 0)
	var code_edit_parser = ParserRef.get_code_edit_parser(self)
	if not code_edit_parser.check_member_line(member_data.get(Keys.MEMBER_TYPE), name, declaration_line, column):
		print("FUNCTION DATA: NOT VALID")
		return
	var func_data = code_edit_parser.get_type_from_line(declaration_line, column)
	
	#print("FUNCTION DATA: ",func_data)
	
	arguments.clear()
	var result = func_data.get("result")
	_cache_dirty = false # at this point it has been read
	if result == null:
		_return_type_raw = ""
		return
	
	var arg_data = result.get(Keys.FUNC_ARGS, {})
	for arg in arg_data.keys():
		arguments[arg] = {Keys.TYPE: arg_data[arg], Keys.MEMBER_TYPE: Keys.MEMBER_TYPE_FUNC_ARG}
	_return_type_raw = result.get(Keys.FUNC_RETURN, "")
	#print("SET FUNC DATA: ", result)





## Scan current func for local vars and func data.
func map_variables() -> void:
	var code_edit_parser = ParserRef.get_code_edit_parser(self)
	for i in range(declaration_line + 1, end_line):
		if not code_edit_parser.is_valid_code(i, -1):
			continue
		var line_text = code_edit_parser.get_line(i)
		var stripped = line_text.strip_edges()
		var indent = code_edit_parser.get_indent_code_edit(i)
		if Utils.line_has_any_declaration(stripped) and indent <= class_indent:
			break
		var var_data = Utils.get_var_or_const_info(stripped)
		if var_data != null:
			var var_name = var_data[0]
			#var_name = Utils.map_check_dupe_local_var_name(var_name, local_vars) # this is negated by using indexes
			var type_hint = var_data[1]
			if type_hint.find(".new(") > -1:
				type_hint = type_hint.substr(0, type_hint.rfind(".new("))
			var data:= {
				Keys.MEMBER_NAME: var_name,
				Keys.LINE_INDEX: i,
				Keys.MEMBER_TYPE: Keys.MEMBER_TYPE_VAR,
				Keys.TYPE: type_hint,
			}
			local_vars[i] = data















### Scan current func for local vars and func data.
#func map_variables() -> void:
	#var code_edit_parser = ParserRef.get_code_edit_parser(self)
	#for i in range(declaration_line + 1, end_line):
		#if not code_edit_parser.is_valid_code(i, -1):
			#continue
		#var line_text = code_edit_parser.get_line(i)
		#var stripped = line_text.strip_edges()
		#var indent = code_edit_parser.get_indent_code_edit(i)
		#if Utils.line_has_any_declaration(stripped) and indent <= class_indent:
			#break
		#var var_data = Utils.get_var_or_const_info(stripped)
		#if var_data != null:
			#var var_name = var_data[0]
			##var_name = Utils.map_check_dupe_local_var_name(var_name, local_vars) # this is negated by using indexes
			#var type_hint = var_data[1]
			#if type_hint.find(".new(") > -1:
				#type_hint = type_hint.substr(0, type_hint.rfind(".new("))
			#var data:= {
				#Keys.MEMBER_NAME: var_name,
				#Keys.LINE_INDEX: i,
				#Keys.MEMBER_TYPE: Keys.MEMBER_TYPE_VAR,
				#Keys.TYPE: type_hint,
			#}
			#local_vars[i] = data



func get_in_scope_local_vars(line:int):
	if _local_vars_set:
		return in_scope_local_vars
	
	var code_edit_parser = ParserRef.get_code_edit_parser(self)
	var context_data = code_edit_parser.get_line_context_start_data(line)
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
		#print("PARSER FUNC::RETURN RAW::", _return_type_raw)
		return _return_type_raw
	#print("PARSER FUNC::RETURN RAW TO INFER::", _return_type_raw)
	#if _return_type == "" or not _return_type.begins_with("res://"):
	if _return_type == "" or not Utils.is_absolute_path(_return_type):
		var parser = Utils.ParserRef.get_parser(self)
		_return_type = parser.resolve_expression(_return_type_raw, declaration_line)
		#print("RESOLVED FUNC RETURN::", _return_type)
	if _return_type == "":
		_return_type = "Variant"
	return _return_type


# this may be slowww, possibly do it in the mapping step
# other option would be to set a limit for indent, check only func level
func _infer_return_type() -> String:
	var code_edit_parser = Utils.ParserRef.get_code_edit_parser(self)
	var func_indent = class_indent + code_edit_parser.indent_size
	var potential_return = ""
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
	
	
	var raw_result = potential_return.strip_edges().trim_prefix("return").strip_edges()
	if raw_result == "":
		return "void"
	
	if raw_result.find("(") > -1:
		var func_call = raw_result.substr(0, raw_result.find("("))
		if func_call == name: # if the func call is a recursive call, we can't do anything here, since we are here because there is not explicit return
			return "Variant"
	
	var parser = Utils.ParserRef.get_parser(self)
	_return_type = parser.resolve_expression(raw_result, i)
	return raw_result
