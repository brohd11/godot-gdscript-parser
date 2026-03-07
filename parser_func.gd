
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

var dirty_flag:=true


var func_lines:PackedInt32Array
var declaration_line:int
var end_line:int
var class_indent:int = 0



var name:String

var member_data:={}

var return_type = "" # done
var arguments = {} # done

var local_vars:= {}

var in_scope_local_vars:= {}

func queue_refresh():
	pass


func set_in_scope_local_vars(new_vars:Dictionary):
	end_line = func_lines[func_lines.size() - 1]
	_set_function_data()
	in_scope_local_vars = new_vars
	in_scope_local_vars.merge(arguments.duplicate())
	

func parse():
	end_line = func_lines[func_lines.size() - 1]
	_set_function_data()
	map_variables()


func _set_function_data():
	var code_edit_parser = ParserRef.get_code_edit_parser(self)
	var func_data = code_edit_parser.get_func_data_at_line(declaration_line)
	arguments.clear()
	var arg_data = func_data.get(Keys.FUNC_ARGS, {})
	for arg in arg_data.keys():
		arguments[arg] = {Keys.TYPE: arg_data[arg], Keys.MEMBER_TYPE: Keys.MEMBER_TYPE_FUNC_ARG}
	return_type = func_data.get(Keys.FUNC_RETURN, "")
	#print("SET FUNC DATA: ", func_data)





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
		var var_data = Utils.get_var_name_and_type_hint_in_line(stripped)
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
		#var var_data = Utils.get_var_name_and_type_hint_in_line(stripped)
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
	return in_scope_local_vars
	#print("GET IN SCOPE %%%")
	#print("ALL: ", local_vars.keys())
	#print("FUNC ARGS: ", arguments)
	
	var code_edit_parser = ParserRef.get_code_edit_parser(self)
	var func_indent = class_indent + code_edit_parser.indent_size
	var current_branch_start_line = code_edit_parser.get_func_branch_start(line, class_indent)
	var current_line_indent = code_edit_parser.get_indent_code_edit(line)
	
	#prints(current_line_indent, class_indent, func_indent)
	
	var in_scope_vars = {}
	in_scope_vars.merge(arguments)
	
	var var_idxes = local_vars.keys()
	var_idxes.sort()
	for i in var_idxes:
		if i > line:
			break
		var indent = code_edit_parser.get_indent_code_edit(i)
		if i < current_branch_start_line and indent > func_indent:
			continue
		if indent > current_line_indent:
			continue
		in_scope_vars[local_vars[i][Keys.MEMBER_NAME]] = local_vars[i]
	
	
	
	return in_scope_vars

func get_return_type(): # this could be used to parse
	_set_function_data()
	return return_type
