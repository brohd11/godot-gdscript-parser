
const GDScriptParser = preload("res://addons/addon_lib/brohd/alib_runtime/utils/resource/gdscript/parser/gdscript_parser.gd")
const Utils = GDScriptParser.Utils
const UString = GDScriptParser.UString
const Keys = Utils.Keys


var _parser:WeakRef
var _class_obj:WeakRef



var name:String

var member_data:={}

var return_type = ""
var arguments = {}

var local_vars = {}


func parse():
	map_variables(member_data[Keys.LINE_INDEX], "")
	print(arguments.keys())
	pass



## Scan current func for local vars and func data.
func map_variables(line:int, current_func_name:String):
	var script_editor = _get_parser().code_edit
	#var c_class = current_class
	#var c_func_name = current_func_name # current_func
	
	#if not script_data.has(c_class):
		#script_data[c_class] = {_Keys.CLASS_BODY:{}}
	
	#script_data[c_class][_Keys.CLASS_BODY][c_func_name] = {_Keys.DECLARATION:line, _Keys.FUNC_ARGS:{}}
	#if c_func_name != _Keys.CLASS_BODY:
		#script_data[c_class][c_func_name] = {}
	
	var temp_func_vars = {}
	var line_count = script_editor.get_line_count()
	var func_found = false
	var current_line = line
	while current_line < line_count:
		var line_text = script_editor.get_line(current_line)
		var stripped = line_text.strip_edges()
		#var indent = script_editor.get_indent_level(current_line)
		var var_data = Utils.get_var_name_and_type_hint_in_line(stripped)
		if var_data != null:
			var var_name = var_data[0]
			var_name = Utils.map_check_dupe_local_var_name(var_name, temp_func_vars)
			var type_hint = var_data[1]
			if type_hint.find(".new(") > -1:
				type_hint = type_hint.substr(0, type_hint.rfind(".new("))
			var data:= {
				Keys.LINE_INDEX: current_line,
				#Keys.SNAPSHOT: stripped,
				Keys.MEMBER_TYPE: Keys.MEMBER_TYPE_VAR,
				Keys.TYPE: type_hint,
				#Keys.INDENT: indent,
			}
			local_vars[var_name] = data
			#script_data[c_class][c_func_name][var_name] = data
			temp_func_vars[var_name] = true
			current_line += 1
			continue
		
		var _class = Utils.get_class_name_in_line(stripped)
		if _class != "":
			break
		var func_name = Utils.get_func_name_in_line(stripped)
		if func_name != "":
			if not func_found:
				func_found = true
				stripped = Utils.get_func_declaration_editor(current_line, script_editor)
				var func_arg_data =  Utils.get_func_data_from_declaration(stripped)
				var func_args = func_arg_data.get(Keys.FUNC_ARGS, {})
				return_type = func_arg_data.get(Keys.FUNC_RETURN, "")
				for arg in func_args:
					var data = {
						Keys.TYPE: func_args.get(arg),
						Keys.MEMBER_TYPE: Keys.MEMBER_TYPE_FUNC_ARG,
					}
					arguments[arg] = data
				
					#script_data[c_class][c_func_name][arg] = data
				#
				#script_data[c_class][_Keys.CLASS_BODY][c_func_name][_Keys.DECLARATION] = current_line
				#script_data[c_class][_Keys.CLASS_BODY][c_func_name][_Keys.SNAPSHOT] = stripped
				#script_data[c_class][_Keys.CLASS_BODY][c_func_name][_Keys.VAR_TYPE] = _Keys.VAR_TYPE_FUNC
				#script_data[c_class][_Keys.CLASS_BODY][c_func_name][_Keys.INDENT] = indent
				
				current_line += 1
				continue
			else:
				break
		
		current_line += 1


func get_in_scope_body_and_local_vars(line:int): #^ possibly pass a varname? Could return it in dict with access name
	var parser = _get_parser()
	var class_obj = _get_class()
	var body_vars = class_obj.get_members()
	
	
	var vars = {}
	
	var in_scope_vars = {}
	var code_edit = parser.code_edit
	var current_line = line
	var current_line_indent = code_edit.get_indent_level(current_line)
	var current_access_indent = _get_current_access_indent() + code_edit.get_tab_size()
	var current_branch_start = _get_current_branch_start()
	for var_name in local_vars.keys():
		var data = local_vars.get(var_name)
		if data is not Dictionary:
			continue
		var var_type = data.get(Keys.MEMBER_TYPE)
		if var_type == Keys.MEMBER_TYPE_FUNC_ARG:
			in_scope_vars[var_name] = data
			continue
		var declaration = data.get(Keys.DECLARATION)
		if declaration == null:
			continue
		var indent = data.get(Keys.INDENT)
		if indent > current_line_indent and declaration < current_branch_start:
			continue
		if declaration <= current_line:
			in_scope_vars[var_name] = data
	
	vars[Keys.LOCAL_VARS] = in_scope_vars
	#completion_cache[Keys.IN_SCOPE_VARS] = vars
	return vars

## Check if local var is in scope at current line.
func _check_local_var_scope(var_name:String, local_vars:Dictionary):
	var code_edit = _get_parser().code_edit
	var current_line = code_edit.get_caret_line()
	var current_indent = code_edit.get_indent_level(current_line)
	var current_access_indent = _get_current_access_indent() + code_edit.get_tab_size() #^ + 4 to account for func body
	var current_branch_start = _get_current_branch_start()
	
	var access_name = _get_local_var_access_name(var_name, local_vars)
	var start_idx = 0
	if access_name.find("%") > -1:
		start_idx = access_name.get_slice("%", 1).to_int()
	
	for i in range(start_idx, -1, -1):
		var access = var_name
		if i > 0:
			access = access + "%" + str(i)
		if local_vars.has(access):
			var data = local_vars.get(access)
			var declaration = data.get(Keys.DECLARATION)
			if declaration == null:
				continue
			if declaration <= current_line:
				var indent = data.get(Keys.INDENT)
				if indent > current_access_indent and declaration < current_branch_start:
					continue
				if current_indent >= indent:
					return true
	return false



## Get where the current branch forks from the func body.
func _get_current_branch_start():
	var parser = _get_parser()
	var code_edit = parser.code_edit
	var current_line = code_edit.get_caret_line()
	var current_indent = code_edit.get_indent_level(current_line)
	var current_access_indent = _get_current_access_indent() + code_edit.get_tab_size()
	
	if current_indent == current_access_indent:
		return current_line
	
	var i = current_line
	while i >= 0:
		var line_text = code_edit.get_line(i)
		var stripped = line_text.strip_edges()
		if stripped == "":
			i -= 1
			continue
		stripped = stripped.get_slice("#", 0)
		if stripped == "":
			i -= 1
			continue
		var indent = code_edit.get_indent_level(i)
		if indent > current_indent:
			break
		current_indent = indent
		if current_indent == current_access_indent:
			break
		i -= 1
	return i

## Get current class base indent.
func _get_current_access_indent():
	var parser = _get_parser()
	var code_edit = parser.code_edit
	var class_obj = _get_class()
	if class_obj.access_path == "":
		return 0
	if class_obj.access_path.find(".") == 0:
		return code_edit.get_tab_size()
	else:
		return (class_obj.access_path.count(".") + 1) * code_edit.get_tab_size()

## Check if other vars have same name in local vars. Determine which is the current.
func _get_local_var_access_name(var_name:String, local_vars:Dictionary):
	var parser = _get_parser()
	var code_edit = parser.code_edit
	var var_access_name = var_name
	if local_vars.has(var_access_name + "%1"):
		var current_line = code_edit.get_caret_line()
		var count = -1
		while current_line >= 0:
			var line_text = code_edit.get_line(current_line)
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






func _get_parser() -> GDScriptParser:
	return _parser.get_ref()
func _get_class() -> GDScriptParser.ParserClass:
	return _class_obj.get_ref()
