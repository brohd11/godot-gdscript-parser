
const GlobalChecker = preload("res://addons/addon_lib/brohd/alib_runtime/misc/global_checker.gd")
const VariantChecker = preload("res://addons/addon_lib/brohd/alib_runtime/misc/variant_checker.gd")


const GDScriptParser = preload("res://addons/addon_lib/brohd/alib_runtime/utils/resource/gdscript/parser/gdscript_parser.gd")
const Utils = GDScriptParser.Utils
const Keys = Utils.Keys
const UString = GDScriptParser.UString
const UFile = GDScriptParser.UFile
const UClassDetail = GDScriptParser.UClassDetail

const PLUGIN_EXPORTED = false
const PRINT_DEBUG = false # not PLUGIN_EXPORTED


var _parser:WeakRef
var _class:WeakRef

func _get_parser() -> GDScriptParser:
	return _parser.get_ref()

func _get_class() -> GDScriptParser.ParserClass:
	return _class.get_ref()


##^r I think this will be a child of the class object, each class can parse it's own things

## THESE NEED TP BE CLEANED UP

func _get_current_script():
	return _get_parser()._script_resource

func get_class_script():
	
	pass

func get_string_map(text:String):
	return UString.get_string_map(text)

## Get script member info, ignores Godot Native class inheritance properties.
func get_script_member_info_by_path(script:GDScript, member_path:String, member_hints:=UClassDetail._MEMBER_ARGS, check_global:=true):
	return UClassDetail.get_member_info_by_path(script, member_path, member_hints, false, false, false, check_global)

func _get_code_edit():
	
	pass

func _get_in_scope_body_and_local_vars():
	
	pass

##

#region Var Lookup
## Get var type of member string. Break into parts then process if needed.
## ie. my_class.some_var.my_func() will have [method _get_var_type] ran on the first part, "my_class".
## The rest will be added to the string and checked that it has property info.
func get_var_type(var_name:String, _func=null, _class=null):
	var parser = _get_parser()
	#if _class == null:
		#_class = current_class
	#if _func == null:
		#_func = current_func
	
	var_name = var_name.trim_prefix("self.")
	var dot_idx = var_name.find(".")
	if dot_idx == -1: #^ simple case
		var var_type = _get_var_type(var_name, _func, _class)
		return var_type
	else: #^ infer the first, then add members, but get return of any method calls between
		var current_script = _get_current_script()
		var string_map = get_string_map(var_name)
		var member_parts = UString.split_member_access(var_name, string_map)
		var final_type_hint = ""
		for i in range(member_parts.size()):
			var part = member_parts[i]
			if i == 0:
				var var_type = _get_var_type(part, _func, _class)
				if var_type.begins_with("res://"):
					var tail = UString.trim_member_access_front(var_name, string_map)
					return var_type + "." + tail
				if var_type != "self":
					final_type_hint = var_type
				continue
			
			if part.find("(") > -1:
				part = part.get_slice("(", 0)
			else:
				var check = final_type_hint + "." + part
				var member_info = get_script_member_info_by_path(current_script, check)
				if member_info != null:
					final_type_hint = check
					continue
				else:
					#if part == "new": #^ assumes this is the new method, dealt with in get func call data
						#final_type_hint = check
					break
			
			var working_func_call = final_type_hint + "." + part
			if PRINT_DEBUG:
				print("WORK ", working_func_call)
			var member_info = get_script_member_info_by_path(current_script, working_func_call)
			if member_info == null:
				if PRINT_DEBUG:
					printerr("COULD NOT FIND MEMBER INFO: ", working_func_call)
				break
			
			var type = property_info_to_type(member_info) #^r can I clean this up a bit?
			if type == "": #^ is this ok? For if an enum is end of string, or other non property member
				if PRINT_DEBUG:
					printerr("type is blank")
				break
			elif type.begins_with("res://"):
				final_type_hint = type
				break #^ this break hasnt been an issue yet.. but could be
			else:
				if type.find(".") == -1:
					var global_path = UClassDetail.get_global_class_path(type)
					if global_path != "":
						final_type_hint = type
				else: #^ handle inner classes
					var first = UString.get_member_access_front(type)
					var global_path = UClassDetail.get_global_class_path(first)
					if global_path != "":
						final_type_hint = type
		
		return final_type_hint
	return var_name #^ should this be empty?

## Get raw type, then infer if possible.
func _get_var_type(var_name:String, _func, _class):
	var vars_dict = _get_body_and_local_vars(_class, _func)
	var local_var_in_scope #= _check_local_var_scope(var_name, vars_dict.local)
	if not local_var_in_scope:
		var source_check = _check_script_source_member_valid(var_name, _class)
		if source_check != null: # early exit
			var prop_string = _property_info_to_type(source_check)
			if prop_string == "":
				return var_name
			return prop_string
	
	var type_hint = _get_raw_type(var_name, _func, _class)
	if PRINT_DEBUG:
		print("RAW ", type_hint)
	if type_hint == "":
		return "" #^ return empty string so a local var will not trigger a body var in lookup
	type_hint = _get_type_hint(type_hint, _class, _func)
	if PRINT_DEBUG:
		print("TYPE ", type_hint)
	if type_hint == "":
		return var_name
	return type_hint


## Get raw type of var. This could be the raw decalaration as text or from property info.
##  ie. "var x = y", returns "y"
func _get_raw_type(var_name:String, _func:String, _class:String):
	var in_body_valid = _check_var_in_body_valid(var_name, _class)
	var vars_dict = _get_body_and_local_vars(_class, _func)
	var body_vars = vars_dict.body
	var local_vars = vars_dict.local
	var in_body_vars = in_body_valid > 0
	#^ Vars are valid at this point.
	if PRINT_DEBUG:
		print("GET RAW TYPE ", var_name)
	if var_name.find("(") > -1: #^ this seems to only trigger with functions that are not in the source code yet
		var_name = var_name.substr(0, var_name.find("("))
		var func_return = _get_func_return_type(var_name, body_vars)
		return func_return
	
	var var_access_name = _get_local_var_access_name(var_name, local_vars)
	var in_scope_vars = {}# _get_in_scope_body_and_local_vars(_class, _func) # this is in function?
	local_vars = in_scope_vars.get(Keys.LOCAL_VARS)
	var in_local_vars = local_vars.has(var_access_name)
	if in_local_vars:
		var data = local_vars.get(var_access_name)
		var dec_line = data.get(Keys.DECLARATION)
		var var_type = data.get(Keys.MEMBER_TYPE)
		if var_type == Keys.MEMBER_TYPE_FUNC_ARG: #^ this means local var from func args
			return data.get(Keys.TYPE)
		var script_editor = _get_code_edit()
		if dec_line <= script_editor.get_caret_line(): # if not, it may be body var
			var member_data = get_member_declaration(var_name, data)
			if member_data == null:
				if PRINT_DEBUG:
					printerr("Could not get: ", var_name)
				return ""
			return member_data.get(Keys.TYPE, "")
	
	if in_body_vars:
		var data = body_vars.get(var_name)
		var member_data = get_member_declaration(var_name, data)
		if member_data == null:
			if PRINT_DEBUG:
				printerr("Could not get: ", var_name)
			return var_name
		return member_data.get(Keys.TYPE, "")
	
	if not (in_local_vars or in_body_vars):
		if _is_class_name_valid(var_name):
			return var_name
		return _get_inherited_member_type(var_name)
	return ""

## Convert raw type hint to actual type. ie. "var x = y", attempts to convert y -> Type
func _get_type_hint(type_hint:String, _class:String, _func:String):
	var in_body_valid = _check_var_in_body_valid(type_hint, _class)
	var var_dict = _get_body_and_local_vars(_class, _func)
	var access_name = _get_local_var_access_name(type_hint, var_dict.local)
	var in_scope_vars = _get_in_scope_body_and_local_vars()#(_class, _func)
	var body_vars = in_scope_vars.body
	var local_vars = in_scope_vars.local # local not used, can remove?
	var in_body_vars = in_body_valid > 0
	var in_local_vars = local_vars.has(access_name)
	#^ Vars are valid at this point.
	if PRINT_DEBUG:
		print("GET TYPE HINT ", type_hint)
	if type_hint.find(" as ") > -1:
		type_hint = type_hint.get_slice(" as ", 1).strip_edges()
	
	if type_hint.begins_with("new("):
		if _class == "":
			return "self"
		else:
			return _class
	if VariantChecker.check_type(type_hint):
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
	
	if type_hint.find(".new(") > -1:
		type_hint = type_hint.substr(0, type_hint.rfind(".new("))
		return type_hint
	
	if _is_class_name_valid(type_hint):
		return type_hint
	
	var dot_idx = type_hint.find(".")
	if dot_idx > -1:
		return get_var_type(type_hint, _func, _class)
	
	if type_hint.ends_with(")"):
		var raw_func_call = type_hint.substr(0, type_hint.find("("))
		return _get_func_return_type(raw_func_call, body_vars)
	
	#^ original _is_class_name_valid location
	#^ end easy checks
	
	if in_local_vars:
		var map_data = local_vars.get(access_name)
		var type = map_data.get(Keys.TYPE) #^ get simple var type, call get_var_type?
		if type != null:
			type = get_var_type(type)
			return type
		return ""
	
	var constant_map = get_script_constants()#current_class)
	if constant_map.has(type_hint):
		# TEST
		var data = constant_map.get(type_hint) #^ This would be already fully resolved, but don't want to return path
		var type = data.get(Keys.TYPE, "")
		if type.is_absolute_path():
			return type_hint
		# TEST #^ Will the below ever be triggered? Seems to be working fine with tests
		var resolved = resolve_full_const_type(type_hint)
		printerr("FULL RESOLVE")
		return resolved
	
	var current_script = _get_current_script()
	if _class != "":
		current_script = get_script_member_info_by_path(current_script,"")# current_class)
		if current_script is not GDScript:
			return type_hint
	
	var member_info = get_script_member_info_by_path(current_script, type_hint)#, ["property", "const"])
	if member_info != null:
		var type = property_info_to_type(member_info)
		if type == "":
			return type_hint
		return type
	
	return type_hint


## Get property info of inherited var, return type as string.
func _get_inherited_member_type(var_name:String):
	var script = get_class_script()
	if not is_instance_valid(script):
		if PRINT_DEBUG:
			printerr("GET INHERITED INNER CLASS: ", script)
			return
	
	var inherited_members = _get_class()._get_inherited_members()
	var member_info = inherited_members.get(var_name)
	if member_info == null:
		return var_name
	var type = property_info_to_type(member_info)
	if type == "":
		return var_name
	return type

## Get func return from script editor text.
func _get_func_return_type(raw_func_call:String, body_vars):
	var global_check = GlobalChecker.get_global_return_type(raw_func_call)
	if global_check != null:
		return global_check
	
	if not body_vars.has(raw_func_call):
		var inherited = _get_inherited_member_type(raw_func_call)
		return inherited
	
	var func_data = body_vars.get(raw_func_call)
	var check_data = get_member_declaration(raw_func_call, func_data)
	if check_data == null: #^ old one returned func name here when calling from raw type
		return ""
	return check_data.get(Keys.FUNC_RETURN, "")

## Check if other vars have same name in local vars. Determine which is the current.
func _get_local_var_access_name(var_name:String, local_vars:Dictionary):
	var script_editor = _get_code_edit()
	var var_access_name = var_name
	if local_vars.has(var_access_name + "%1"):
		var current_line = script_editor.get_caret_line()
		var count = -1
		while current_line >= 0:
			var line_text = script_editor.get_line(current_line)
			var stripped = line_text.strip_edges()
			var var_nm_check = UString.get_var_name_and_type_hint_in_line(stripped)
			if var_nm_check != null:
				var found_name = var_nm_check[0]
				if found_name != "" and found_name == var_name:
					count += 1
					current_line -= 1
					continue
			if UString.get_func_name_in_line(stripped) != "":
				break
			current_line -= 1
		
		if count > 0:
			var_access_name = var_name + "%" + str(count)
	
	return var_access_name

## Get body and local vars of class and func. All local vars are included, not just in-scope.
## [method get_in_scope_body_and_local_vars] for in scope only.
func get_body_and_local_vars(_class:String, _func:String):
	return _get_body_and_local_vars(_class, _func)

func _get_body_and_local_vars(_class:String, _func:String):
	#if not script_data.has(_class):
		#_map_script_members()
	
	var class_vars# = script_data.get(_class, {})
	var body_vars = class_vars.get(Keys.CLASS_BODY)
	var local_vars:Dictionary
	if _func != Keys.CLASS_BODY:
		var func_vars = class_vars.get(_func, {})
		local_vars = func_vars
	else:
		local_vars = {}
	return {"body":body_vars, "local":local_vars}







## 0 = Not in body. 1 = In body and valid. 2 = In body, but not valid.
func _check_var_in_body_valid(var_name, _class):
	var body_vars# = script_data[_class][Keys.CLASS_BODY]
	var in_body_vars = body_vars.has(var_name) # only local vars will have modified name
	if var_name.find("(") > -1:
		var_name = var_name.substr(0, var_name.find("("))
		in_body_vars = body_vars.has(var_name)
	if in_body_vars:
		var data = body_vars.get(var_name)
		#var indent = data.get(Keys.INDENT)
		#if indent == null: #^ this was to make sure func args were not passed, but should be fixed
			#var current_line_text = _get_current_line_text() 
			#if current_line_text.begins_with("func ") or current_line_text.begins_with("static func"):
				#return 0
		var valid_declaration = check_member_declaration_valid(var_name, data)
		if not valid_declaration:
			if PRINT_DEBUG:
				printerr("TRIGGERING REBUILD")
			
			return 2
		return 1
	return 0




## Check member declaration is the same in source code and script editor.
func check_member_declaration_valid(member_name:String, map_data):
	var snapshot = map_data.get(Keys.SNAPSHOT, "")
	var var_type = map_data.get(Keys.MEMBER_TYPE)
	var indent = map_data.get(Keys.INDENT)
	#var stripped = _get_member_declaration_from_text(member_name, _current_code_edit_text, indent, var_type, &"editor")
	var stripped = _get_member_declaration_from_text(member_name, "", indent, var_type, &"editor")
	if snapshot != stripped:
		return false
	return true

## Check that var declaration in script is equal to script editor text. If it is, return property info
## and early exit the parsing.
func _check_script_source_member_valid(first_var:String, _class:String):
	if first_var == "":
		return null
	var access_name = first_var
	if first_var.find("(") > -1:
		access_name = first_var.substr(0, first_var.find("("))
	
	var script_checks = {}# completion_cache.get_or_add(Keys.SCRIPT_SOURCE_CHECK, {})
	var _class_dict = script_checks.get_or_add(_class, {})
	if _class_dict.has(first_var):
		return _class_dict[access_name]
	
	var in_body_valid = _check_var_in_body_valid(first_var, _class)
	var in_body_vars = in_body_valid > 0
	if not in_body_vars:
		#completion_cache[Keys.SCRIPT_SOURCE_CHECK][_class][access_name] = null
		return null
	
	var vars_dict = _get_body_and_local_vars(_class, Keys.CLASS_BODY)
	var body_vars = vars_dict.body
	var local_vars = vars_dict.local
	var data = body_vars.get(access_name)
	if data == null:
		if PRINT_DEBUG:
			printerr("IN BODY VAR BUT DATA NULL: ", access_name)
		#completion_cache[Keys.SCRIPT_SOURCE_CHECK][_class][access_name] = null
		return null
	
	var current_script = _get_current_script()
	var snapshot = data.get(Keys.SNAPSHOT)
	var var_type = data.get(Keys.MEMBER_TYPE)
	var indent = data.get(Keys.INDENT)
	
	var script_text #= _get_current_script_as_text()
	#^ alternate use the file's contents. This is because the source code get's updated on script change 
	#^ but doesn't actually seem to have updated vars when calling script functions
	#var source_snapshot = _get_member_declaration_from_text(access_name, current_script.source_code, indent, var_type)
	var source_snapshot = _get_member_declaration_from_text(access_name, script_text, indent, var_type)
	
	if snapshot == source_snapshot:
		if _class != "":
			current_script = get_script_member_info_by_path(current_script, _class, ["const"], false)
		var property_info = get_script_member_info_by_path(current_script, access_name)
		
		if property_info is Dictionary: # if class name is not in line, it is likely a non global class inheriting
			var prop_class = property_info.get("class_name", "") # set to null to trigger scan
			if ClassDB.class_exists(prop_class):
				if snapshot.find(prop_class) == -1:
					property_info = null
		
		#completion_cache[Keys.SCRIPT_SOURCE_CHECK][_class][access_name] = property_info
		return property_info
	
	#completion_cache[Keys.SCRIPT_SOURCE_CHECK][_class][access_name] = null
	return null

## Get member declaration and parse for relevant data.
func get_member_declaration(member_name:String, map_data:Dictionary):
	var var_type = map_data.get(Keys.MEMBER_TYPE)
	var indent = map_data.get(Keys.INDENT)
	if indent == null:
		return null
	
	#var declarations = completion_cache.get_or_add(Keys.SCRIPT_DECLARATIONS_DATA, {})
	var declarations = {}
	var member_name_dict = declarations.get_or_add(member_name, {})
	if member_name_dict.has(indent):
		return member_name_dict[indent]
	#var stripped = _get_member_declaration_from_text(member_name, _current_code_edit_text, indent, var_type, &"editor", true)
	var stripped = _get_member_declaration_from_text(member_name, "", indent, var_type, &"editor", true)
	var data
	if var_type == Keys.MEMBER_TYPE_VAR:
		var var_data = UString.get_var_name_and_type_hint_in_line(stripped)
		if var_data != null:
			var type_hint = var_data[1]
			data = {
				#Keys.DECLARATION: current_line,
				Keys.SNAPSHOT: stripped,
				Keys.TYPE: type_hint,
			}
	elif var_type == Keys.MEMBER_TYPE_CONST:
		var const_data = UString.get_const_name_and_type_in_line(stripped)
		if const_data != null:
			var type_hint = const_data[1]
			data = {
				#Keys.DECLARATION: current_line,
				Keys.SNAPSHOT: stripped,
				Keys.TYPE: type_hint,
			}
	elif var_type == Keys.MEMBER_TYPE_FUNC:
		var func_name = UString.get_func_name_in_line(stripped)
		if func_name != "":
			var func_args = Utils.get_func_data_from_declaration(stripped)
			data = {
				#Keys.DECLARATION: current_line,
				Keys.SNAPSHOT: stripped,
				Keys.FUNC_ARGS: func_args.get(Keys.FUNC_ARGS, {}),
				Keys.FUNC_RETURN: func_args.get(Keys.FUNC_RETURN, ""),
			}
	elif var_type == Keys.MEMBER_TYPE_ENUM:
		if stripped.begins_with("enum "):
			var enum_name = stripped.get_slice("enum ", 1).get_slice("{", 0).strip_edges()
			var enum_members = Utils.get_enum_members_in_line(stripped)
			data = {
				Keys.SNAPSHOT: stripped,
				Keys.ENUM_MEMBERS: enum_members,
				Keys.TYPE: enum_name,
			}
	
	#completion_cache[Keys.SCRIPT_DECLARATIONS_DATA][member_name][indent] = data
	return data


## Get the member's declaration from either source code or script editor.
func _get_member_declaration_from_text(var_name:String, text:String, indent:int, member_hint:=Keys.MEMBER_TYPE_VAR, text_source:=&"source", reverse:=false):
	#var declarations = completion_cache.get_or_add(Keys.SCRIPT_DECLARATIONS_TEXT, {})
	var declarations = {}
	var source_dict = declarations.get_or_add(text_source, {})
	var member_name_dict = source_dict.get_or_add(var_name, {})
	if member_name_dict.has(indent):
		return member_name_dict[indent]
	
	var code_edit = _get_parser().code_edit
	
	var prefix:String
	var search_string:String
	if member_hint == Keys.MEMBER_TYPE_VAR:
		prefix = "var "
	elif member_hint == Keys.MEMBER_TYPE_STATIC_VAR:
		prefix = "static var "
	elif member_hint == Keys.MEMBER_TYPE_CONST:
		prefix = "const "
	elif member_hint == Keys.MEMBER_TYPE_FUNC:
		prefix = "func "
	elif member_hint == Keys.MEMBER_TYPE_STATIC_FUNC:
		prefix = "static func "
	elif member_hint == Keys.MEMBER_TYPE_ENUM:
		prefix = "enum "
	
	if prefix == null:
		return ""
	search_string = prefix + var_name
	
	var indent_space = ""
	for i in range(code_edit.get_tab_size()):
		indent_space += " "
	
	var var_declaration_idx:int = -1
	if reverse:
		if text_source == &"source":
			if PRINT_DEBUG:
				printerr("Can't run reverse member declaration search on source code. Need caret char from code edit method.")
			return ""
		var caret_idx = "" # _current_code_edit_text_caret
		var_declaration_idx = UString.rfind_index_safe(text, search_string, caret_idx)
		if var_declaration_idx == -1:
			var_declaration_idx = text.find(search_string, caret_idx)
	else:
		var_declaration_idx = text.find(search_string)
	if var_declaration_idx == -1:
		return ""
	
	var source_code_len = text.length()
	while var_declaration_idx > -1:
		var search_len = var_name.length() + 1
		if var_declaration_idx + prefix.length() + search_len > source_code_len:
			break
		var candidate_check = text.substr(var_declaration_idx + prefix.length(), search_len)
		if candidate_check.is_valid_ascii_identifier():
			if not reverse:
				var_declaration_idx = text.find(search_string, var_declaration_idx + search_len)
			else:
				var_declaration_idx = UString.rfind_index_safe(text, search_string, var_declaration_idx - 1)
		else:
			var new_line_idx = UString.rfind_index_safe(text, "\n", var_declaration_idx) + 1
			var white_space:String = text.substr(new_line_idx, var_declaration_idx - new_line_idx)
			white_space = white_space.replace("\t", indent_space)
			var indent_count = white_space.count(" ")
			if indent_count != indent:
				if not reverse:
					var_declaration_idx = text.find(search_string, var_declaration_idx + search_len)
				else:
					var_declaration_idx = UString.rfind_index_safe(text, search_string, var_declaration_idx - 1)
			else:
				break
	
	var new_line_idx = UString.rfind_index_safe(text, "\n", var_declaration_idx)
	if new_line_idx == -1:
		new_line_idx = 0
	
	var var_declaration:String
	if member_hint == Keys.MEMBER_TYPE_FUNC:
		var source_at_var = text.substr(new_line_idx + 1) # 1 to go on the other side of the \n
		#var_declaration = _get_func_declaration_string(source_at_var)
	elif member_hint == Keys.MEMBER_TYPE_ENUM:
		var source_at_var = text.substr(new_line_idx + 1) # 1 to go on the other side of the \n
		#var_declaration = _get_enum_string(source_at_var)
	else:
		var_declaration = text.substr(new_line_idx, text.find("\n", new_line_idx + 1) - new_line_idx + 1)
		if var_declaration.find(";") > -1:
			var_declaration = var_declaration.get_slice(";", 0)
	var no_com = var_declaration.get_slice("#", 0) #^ may need string map?
	var stripped = no_com.strip_edges()
	#completion_cache[Keys.SCRIPT_DECLARATIONS_TEXT][text_source][var_name][indent] = stripped
	return stripped


#endregion






## Get a class_name from property info and convert to a type if possible.
## If method data, uses return data.
func property_info_to_type(property_info) -> String:
	var type = _property_info_to_type(property_info)
	return type

func _property_info_to_type(property_info) -> String:
	var preload_map = get_preload_map()
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
			var const_name = preload_map.get(class_path)
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
		var member_path = UClassDetail.script_get_member_by_value(_get_current_script(), property_info)
		if member_path != null:
			return member_path
		
		var path = property_info.resource_path
		var const_name = preload_map.get(path)
		if const_name:
			return const_name
	
	if PRINT_DEBUG:
		printerr("UNHANDLED PROPERTY INFO OR UNFOUND: ", property_info)
	return ""


## Check that class name is Godot Native or member of the class. A valid user global class will also return true.
func _is_class_name_valid(_class_name, check_global:=true):
	if _class_name.find(".") > -1:
		_class_name = _class_name.substr(0, _class_name.find("."))
	if ClassDB.class_exists(_class_name):
		return true
	var base = _get_current_script().get_instance_base_type()
	if (ClassDB.class_has_enum(base, _class_name) or ClassDB.class_has_integer_constant(base, _class_name) or 
	ClassDB.class_has_method(base, _class_name) or ClassDB.class_has_signal(base, _class_name)):
		return true
	if check_global:
		if UClassDetail.get_global_class_path(_class_name) != "":
			return true
	return false



## Return dictionary of preload in current script [path, name]
func get_preload_map():
	#var cached = completion_cache.get(Keys.SCRIPT_FULL_PRELOAD_MAP)
	#if cached != null:
		#return cached
	
	var script = _get_current_script()
	var inh_preloads = _get_inherited_preload_map(script) #^ doesnt account for inner classes
	
	var constants = get_script_constants()
	for nm in constants.keys():
		var const_data = constants.get(nm)
		var type = const_data.get(Keys.TYPE, "") as String
		if type == nm: #^ mainly for enums
			continue
		var resolved = _resolve_full_type(nm, constants)
		if resolved.begins_with("res://"):
			inh_preloads[resolved] = nm
		elif _is_class_name_valid(resolved):
			inh_preloads[resolved] = nm
	
	#for keys in inh_preloads.keys():
		#print(inh_preloads[keys], " -> ", keys)
	
	#completion_cache[_Keys.SCRIPT_FULL_PRELOAD_MAP] = inh_preloads
	return inh_preloads

func resolve_full_const_type(var_name):
	var constants = get_script_constants()
	if not constants.has(var_name):
		return null
	var type = _resolve_full_type(var_name, constants)
	return type

func _resolve_full_type(var_name:String, constants_dict:Dictionary) -> String:
	var suffix = ""
	var current_alias = var_name
	var visited_aliases = {}
	while constants_dict.has(current_alias):
		if visited_aliases.has(current_alias): # If we have seen this alias before, we're in a loop.
			if PRINT_DEBUG:
				printerr("Cycle detected in constant resolution! Alias '", current_alias, "' is part of a loop.")
			return "[CYCLE_ERROR:" + current_alias + "]" + suffix
		visited_aliases[current_alias] = true
		
		var data = constants_dict[current_alias]
		var full_definition: String = data.get(Keys.TYPE)
		var dot_pos = full_definition.find(".")
		if dot_pos > -1:
			var next_alias = full_definition.substr(0, dot_pos)
			var new_suffix = full_definition.substr(dot_pos)
			suffix = new_suffix + suffix
			current_alias = next_alias
		else:
			if current_alias == full_definition:
				return current_alias + suffix
			current_alias = full_definition
	
	return current_alias + suffix

## Get preloads and convert to path as key dictionary.
func _get_inherited_preload_map(script:GDScript):
	#var preload_section = data_cache.get_or_add(_Keys.SCRIPT_PRELOAD_MAP, {})
	#var cached_data = CacheHelper.get_cached_data(script.resource_path, preload_section)
	#if cached_data != null:
		#return cached_data
	
	script = script.get_base_script()
	if script == null:
		return {}
	
	var map := {}
	var preloads = UClassDetail.script_get_preloads(script)
	for nm in preloads.keys():
		var pl_script = preloads[nm]
		map[pl_script.resource_path] = nm
	var inh_paths = UClassDetail.script_get_inherited_script_paths(script)
	#CacheHelper.store_data(script.resource_path, map, preload_section, inh_paths)
	return map


## Get constants for script. Acounts for inner classes.
func get_script_constants():
	var class_obj = _get_class()
	var constants = class_obj.constants.duplicate()
	constants.merge(class_obj.inner_classes.duplicate())
	return constants



#region Script Inherited Members






#endregion
