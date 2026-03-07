#! import-p Keys,

const GDScriptParser = preload("res://addons/addon_lib/brohd/alib_runtime/utils/resource/gdscript/parser/gdscript_parser.gd")
const ParserClass = GDScriptParser.ParserClass
const Utils = GDScriptParser.Utils
const Keys = Utils.Keys
const UString = GDScriptParser.UString
const UClassDetail = GDScriptParser.UClassDetail

var _parser:WeakRef
var code_edit:CodeEdit

var indent_size:int

func _get_parser() -> GDScriptParser:
	return _parser.get_ref()



var string_map_cache:={}
static var assignment_regex:RegEx
static var type_assignment_regex:RegEx
static var context_regex: RegEx

var _map_regex:RegEx


func parse_text():
	_map_regex = RegEx.new()
	_map_regex.compile("^(static\\s+var|static\\s+func|var|func|enum|const|signal|class)\\s+([a-zA-Z_]\\w*)")
	var t = ALibRuntime.Utils.UProfile.TimeFunction.new("S")
	var parser = _get_parser()
	code_edit = parser.code_edit
	var existing_class_access = parser._class_access
	var main_script = parser._script_resource
	var main_script_path = main_script.resource_path
	
	indent_size = code_edit.get_tab_size()
	
	var class_access_map = {}
	var member_map = {}
	var constant_map = {}
	var inner_class_map = {}
	
	class_access_map[""] = []
	var access_path = ""
	var current_indentation_level = 0
	var extended_lines = []
	
	var in_function = false
	var current_func_dict:={}
	
	var i = 0
	var code_edit_line_count = code_edit.get_line_count() - 1
	for _i in range(code_edit_line_count):
		#var line = code_edit.get_line(i)
		#var line = get_line(i, true)
		
		var stripped:String = get_line(i, true).strip_edges()
		#if line.find("#") > -1:
			#stripped = remove_comment(i, line)
		#else:
			#stripped = line.strip_edges()
		
		if stripped == "":
			class_access_map[access_path].append(i)
			if in_function:
				current_func_dict[Keys.FUNC_LINES].append(i)
			i += 1
			continue
		
		var next_i = i
		while stripped.ends_with("\\"):
			next_i += 1
			if not next_i < code_edit_line_count:
				break
			stripped = stripped.trim_suffix("\\")
			extended_lines.append(next_i)
			var next_line = code_edit.get_line(next_i)
			if next_line.find("#") > -1:
				stripped += remove_comment(next_i, next_line).strip_edges(true, false)
			else:
				stripped += next_line.strip_edges(true, false)
			#stripped = stripped.strip_edges()
		
		
		var indentation_level = get_indent_code_edit(i)
		if indentation_level < current_indentation_level:
			if stripped != "":
				var iterations = (current_indentation_level - indentation_level) / indent_size
				for z in range(iterations):
					var dot = access_path.rfind(".")
					if dot == -1:
						access_path = ""
						break
					else:
						access_path = access_path.substr(0, access_path.rfind("."))
				
				#prints("DROP LEVEL:", indentation_level, current_indentation_level,old_access_path, " -> ", access_path)
				current_indentation_level = indentation_level
		
		
		var inner_name = Utils.get_class_name_in_line(stripped)
		if inner_name != "":
			var new_access_path = Utils.map_get_access_path(access_path, inner_name)
			var member_data = {
				Keys.MEMBER_NAME:inner_name,
				Keys.MEMBER_TYPE:Keys.MEMBER_TYPE_CLASS,
				Keys.TYPE:Utils.map_get_access_path(main_script_path, new_access_path),
				Keys.LINE_INDEX:i
			}
			inner_class_map.get_or_add(access_path, {})[inner_name] = member_data
			
			in_function = false
			current_indentation_level += indent_size
			access_path = new_access_path
			class_access_map[access_path] = []
		
		if current_indentation_level == indentation_level:
			
			var member_data = Utils.get_member_data(stripped, i)
			if not member_data.is_empty():
				var member_name = member_data[Keys.MEMBER_NAME]
				var member_type = member_data[Keys.MEMBER_TYPE]
				if member_type == Keys.MEMBER_TYPE_CONST or member_type == Keys.MEMBER_TYPE_ENUM:
					in_function = false
					constant_map.get_or_add(access_path, {})[member_name] = member_data
				elif member_type == Keys.MEMBER_TYPE_FUNC or member_type == Keys.MEMBER_TYPE_STATIC_FUNC:
					current_func_dict = member_data
					in_function = true
					member_data[Keys.FUNC_LINES] = PackedInt32Array()
					member_map.get_or_add(access_path, {})[member_name] = member_data
				else:
					in_function = false
					member_map.get_or_add(access_path, {})[member_name] = member_data
			
			
			var result = _map_regex.search(stripped)
			if result:
				var keyword = result.get_string(1)
				var member_name = result.get_string(2)
				var data = {
					Keys.MEMBER_TYPE: keyword,
					Keys.MEMBER_NAME: member_name,
					Keys.LINE_INDEX: i
				}
				if keyword.ends_with("func"):
					current_func_dict = data
					in_function = true
					data[Keys.FUNC_LINES] = PackedInt32Array()
					member_map.get_or_add(access_path, {})[member_name] = data
				elif keyword.begins_with("c"):
					in_function = false
					constant_map.get_or_add(access_path, {})[member_name] = data
				else:
					in_function = false
					member_map.get_or_add(access_path, {})[member_name] = data
				
				if not member_data:
					print("MIS MATCH ", member_name)
				elif member_name != member_data[Keys.MEMBER_NAME]:
					prints("MIS MATCH '%s' - '%s'"% [member_data[Keys.MEMBER_NAME], member_name])
			
		
		
		class_access_map[access_path].append(i)
		if in_function:
			current_func_dict[Keys.FUNC_LINES].append(i)
		if not extended_lines.is_empty():
			for index in extended_lines:
				class_access_map[access_path].append(index)
				if in_function:
					current_func_dict[Keys.FUNC_LINES].append(i)
				i += 1
			extended_lines.clear()
		
		i += 1
	
	
	#print(inner_class_map)
	var temp_class_access = {}
	var _class_paths = class_access_map.keys()
	for path:String in _class_paths:
		var _class_obj:ParserClass
		if existing_class_access.has(path):
			_class_obj = existing_class_access[path]
		if not is_instance_valid(_class_obj):
			_class_obj = ParserClass.new()
			Utils.ParserRef.set_refs(_class_obj, parser)
			_class_obj.access_path = path
			_class_obj.indent_level = get_indent_access_path(access_path)
		
		_class_obj.queue_refresh()
		
		var valid_constants:Dictionary = constant_map.get("", {}).duplicate()
		var valid_classes:Dictionary = inner_class_map.get("", {}).duplicate()
		if path != "":
			var working_path = path
			for x in range(path.count(".") + 1):
				valid_constants.merge(constant_map.get(working_path, {}))
				valid_classes.merge(inner_class_map.get(working_path, {}))
				working_path = working_path.substr(0, working_path.rfind("."))
		
		
		_class_obj.main_script_path = main_script_path
		if path == "":
			_class_obj.script_resource = parser._script_resource
			#_class_obj.script_access_path = main_script_path
		else:
			#_class_obj.script_access_path = valid_classes[path].get(Keys.TYPE)
			var script = UClassDetail.get_member_info_by_path(main_script, access_path)
			if script != null:
				_class_obj.script_resource = script
		
		var class_lines = class_access_map[path]
		#for line_idx in class_lines:
			#_class_mask[line_idx] = path
		
		_class_obj.set_lines(class_lines)
		#print("___ %s ___" % path)
		
		
		
		_class_obj.set_members(member_map.get(path, {}))
		_class_obj.set_constants(valid_constants)
		_class_obj.set_inner_classes(valid_classes)
		
		temp_class_access[path] = _class_obj
	
	parser._class_access = temp_class_access
	t.stop()
	#print("CLASSES ",temp_class_access.keys())
	return temp_class_access






static func _parse_source2(source:String):
	var t = ALibRuntime.Utils.UProfile.TimeFunction.new("STRING")
	var count = 0
	var last_new_line_idx = 0
	var new_line_idx = source.find("\n")
	while new_line_idx != -1 and count < 2:
		count += 1
		var line = source.substr(last_new_line_idx, new_line_idx)
		print(line)
		last_new_line_idx = new_line_idx + 1
		new_line_idx = source.find("\n", last_new_line_idx)
	t.stop()





	

#region CaretContext


func get_line_context_start_data(target_line_index:int, params:Dictionary={}) -> Dictionary:
	var map_blocks_array = params.get(&"map_blocks", []) as Array
	var has_blocks = not map_blocks_array.is_empty()
	var map_local_vars = params.get(&"map_local_vars", true) as bool
	
	var blocks:= []
	var local_vars:= {}
	
	var original_indent = get_indent_code_edit(target_line_index)
	var current_indent = original_indent
	
	var has_semi_col:=false
	var context_start_line = target_line_index + 1
	while context_start_line > 0:
		context_start_line -= 1
		if _line_has_semi_colon(context_start_line):
			has_semi_col = true
			break
		var stripped = code_edit.get_line(context_start_line).strip_edges()
		if stripped == "" or stripped.begins_with("#"):
			continue
		if code_edit.is_in_string(context_start_line, 0) != -1:
			continue
		
		var line_indent = get_indent_code_edit(context_start_line)
		if line_indent <= current_indent:
				if has_blocks and line_indent < current_indent:
					for control_flow in map_blocks_array:
						if stripped.begins_with(control_flow):
							if control_flow == Keywords.FOR:
								var var_dec = "var " + stripped.get_slice("for ", 1).get_slice(" in ", 0).strip_edges()
								var var_data = Utils.add_var_to_dict(var_dec, context_start_line, local_vars)
								blocks.append({"type":"for", "var":{"name": var_data[0], "type": var_data[1]}})
							else:
								blocks.append({"type":control_flow.strip_edges(), "expr": _get_control_flow_expression(context_start_line, control_flow)})
							current_indent = line_indent
				
				if map_local_vars:
					var var_data = Utils.add_var_to_dict(stripped, context_start_line, local_vars)
					if var_data != null:
						continue
				else:
					if not Utils.line_has_any_declaration(stripped):
						continue
					if not stripped.begins_with("func "):
						break
				if Utils.get_func_name_in_line(stripped) != "":
					break
	
	return {
		&"has_semi_col": has_semi_col,
		&"start_index": context_start_line,
		&"blocks": blocks,
		&"local_vars":local_vars
	}


func get_line_context_start_simple(target_line_index:int) -> Dictionary:
	var has_semi_col:=false
	var context_start_line = target_line_index + 1
	while context_start_line > 0:
		context_start_line -= 1
		if _line_has_semi_colon(context_start_line):
			has_semi_col = true
			break
		var stripped = code_edit.get_line(context_start_line).strip_edges()
		if stripped == "" or stripped.begins_with("#"):
			continue
		if not Utils.line_has_any_declaration(stripped) or code_edit.is_in_string(context_start_line, 0) != -1:
			continue
		if not stripped.begins_with("func "):
			break
		if Utils.get_func_name_in_line(stripped) != "":
			print("HAS FUNC")
			break
	
	return {
		&"has_semi_col": has_semi_col,
		&"start_index": context_start_line,
	}

func _line_has_semi_colon(line:int):
	var line_text = code_edit.get_line(line) # musn't be stripped on left for is_valid_code with semi
	var semi_i = line_text.rfind(";")
	while semi_i != -1:
		if not is_valid_code(line, semi_i):
			semi_i = line_text.rfind(";", semi_i - 1)
		else:
			return true
	return false



func get_line_context(target_line_index:int, _caret_column:=0, insert_caret:=false, start_data:={}) -> String:
	if not is_instance_valid(context_regex):
		context_regex = RegEx.new()
		context_regex.compile("[\"'(){}\\[\\]]")
	
	var t = ALibRuntime.Utils.UProfile.TimeFunction.new("Get Caret Context")
	if start_data.is_empty():
		start_data = get_line_context_start_simple(target_line_index)
	
	var has_semi_col:bool = start_data.get(&"has_semi_col", false)
	var context_start_line:int = start_data.get(&"start_index", target_line_index)
	var context_end_line:int = target_line_index + 1
	
	
	#var has_semi_col:=false
	#var context_start_line = target_line_index + 1
	#var context_end_line = target_line_index + 1
	#while context_start_line > 0:
		#context_start_line -= 1
		#var line = code_edit.get_line(context_start_line) # musn't be stripped for is_valid_code
		#if line == "":
			#continue
		#var semi_i = line.rfind(";")
		#while semi_i != -1:
			#if not is_valid_code(context_start_line, semi_i):
				#semi_i = line.rfind(";", semi_i - 1)
			#else:
				#has_semi_col = true
				#break
		#line = line.strip_edges()
		#if not Utils.line_has_any_declaration(line) or code_edit.is_in_string(context_start_line, 0) != -1:
			#continue
		#if not line.begins_with("func "):
			#break
		#if Utils.get_func_name_in_line(line) != "":
			#break
	
	var bracket_depth = 0
	var in_string = code_edit.is_in_string(context_start_line, 0) != -1
	var is_prev_continued = false
	for i in range(context_start_line, code_edit.get_line_count()):
		var line = code_edit.get_line(i)
		if bracket_depth == 0 and not in_string and not is_prev_continued: # if not in string
			context_start_line = i
			context_end_line = i
		
		var results = context_regex.search_all(line)
		for res in results:
			var pos = res.get_start()
			var c = res.get_string()
			var quote_char = c == "'" or c == '"'
			if quote_char:
				if in_string:
					pos += 1
				else:
					pos = max(pos - 1, 0)
			
			if is_valid_code(i, pos):
				if quote_char:
					in_string = not in_string
				elif c == "(" or c == "[" or c == "{":
					bracket_depth += 1
				else:
					bracket_depth = max(0, bracket_depth - 1)
		
		is_prev_continued = false # 2. CHECK FOR LINE CONTINUATIONS '\'
		var stripped = line.strip_edges()
		if stripped.ends_with("\\"):
			var bs_idx = line.rfind("\\")
			if is_valid_code(i, bs_idx):
				is_prev_continued = true
		
		if not is_prev_continued:
			if i >= target_line_index and bracket_depth == 0 and not in_string:
				#print("BREAKING %s -> %s " % [context_start_line, context_end_line], line)
				context_end_line = i
				break
	
	var caret_idx = 0
	var context_text = ""
	for i in range(context_start_line, context_end_line + 1):
		var line = get_line_no_comment(i)
		if i == target_line_index:
			if insert_caret:
				line = line.insert(_caret_column, Keys.CARET_UNI_CHAR)
				caret_idx = line.rfind(Keys.CARET_UNI_CHAR) + context_text.length()
			
		if code_edit.is_in_string(i) == -1:
			var not_first = i > context_start_line
			var line_text = line.strip_edges(not_first, true).trim_suffix("\\")
			if not_first:
				line_text = " " + line_text
			context_text += line_text
		else:
			context_text += "\n" + line
	
	if has_semi_col and insert_caret:
		var string_map = get_string_map(context_text)
		var semi_prev = UString.string_safe_rfind(context_text, ";", caret_idx, string_map) + 1
		var semi_next = UString.string_safe_find(context_text, ";", caret_idx, string_map)
		context_text = context_text.substr(semi_prev, semi_next)
	
	
	t.stop()
	return context_text


func parse_identifier_at_position(text_to_process:String, start_pos:int):
	var string_map = get_string_map(text_to_process)
	
	var current_pos = start_pos
	var name_start_pos = start_pos + 1
	var last_char = ""
	while current_pos >= 0:
		if string_map.string_mask[current_pos] == 1:
			current_pos -= 1
			continue
		
		var _char = text_to_process[current_pos]
		if _char == ")" or _char == "]" or _char == "}":
			current_pos = string_map.bracket_map.get(current_pos, current_pos)
		
		if not _char.is_valid_ascii_identifier() and _char != ".":
			var valid = false
			if _char == ")" and last_char == ".":
				valid = true
			if _char in UString.NUMBERS:
				valid = true
			
			if not valid:
				break
		
		last_char = _char
		name_start_pos = current_pos
		current_pos -= 1
	
	return text_to_process.substr(name_start_pos, start_pos - name_start_pos + 1)

func get_indent_access_path(access_path:String):
	if access_path == "":
		return 0
	if access_path.find(".") == 0:
		return indent_size
	else:
		return (access_path.count(".") + 1) * indent_size

func get_indent_code_edit(line:int):
	return code_edit.get_indent_level(line)
	
	#line = line.
	#var count = 0
	#var i = 0
	#while i < line.length():
		#if line[i] == "\t":
			#count += 1
		#else:
			#break
		#i += 1
	#return count

func get_indent_size():
	return code_edit.get_tab_size()

func is_valid_code(line:int, col:int):
	return code_edit.is_in_string(line, col) == -1 and code_edit.is_in_comment(line, col) == -1


func get_string_map(text:String):
	if string_map_cache.has(text):
		return string_map_cache[text]
	var string_map = UString.get_string_map(text, UString.StringMap.Mode.FULL)
	string_map_cache[text] = string_map
	return string_map



func get_line(line:int, strip_comment:=false):
	var line_text = code_edit.get_line(line)
	if not strip_comment:
		return line_text
	else:
		var com_idx = line_text.find("#")
		while com_idx != -1:
			if code_edit.is_in_string(line, com_idx) != -1:
				com_idx = line_text.find("#", com_idx + 1)
			else:
				break
		return line_text.substr(0, com_idx).strip_edges(false, true)

func get_extended_line(line_index:int):
	var full_line = ""
	var in_extension:= false
	var start_i = line_index - 1
	while start_i >= 0:
		var line = get_line(start_i, true)
		if not line.ends_with("\\"):
			break
		start_i -= 1
	start_i += 1 # offsets back to last line no extension
	
	while start_i < code_edit.get_line_count() - 1:
		var line = get_line(start_i, true)
		in_extension = line.ends_with("\\")
		full_line += " " + line.trim_suffix("\\") + " "
		start_i += 1
		if not in_extension:
			break
		
	return full_line

func get_line_no_comment(line:int):
	var line_text = code_edit.get_line(line)
	var com_idx = line_text.find("#")
	while com_idx != -1:
		if code_edit.is_in_string(line, com_idx) != -1:
			com_idx = line_text.find("#", com_idx + 1)
		else:
			break
	return line_text.substr(0, com_idx).strip_edges(false)

func get_type_from_line(line:int):
	var context = get_line_context(line)
	return get_type_from_line_text(context.strip_edges())

## returns an array with [member_name, member_type], except functions, which return a dict {func_args, func_return}, keys are in Keys class
func get_type_from_line_text(stripped_line_text:String):
	for dec in Keywords.DECLARATIONS:
		if stripped_line_text.begins_with(dec):
			if dec == &"var " or dec == &"static var ":
				return Utils.get_var_name_and_type_hint_in_line(stripped_line_text)
			elif dec == &"enum ":
				return [Utils.get_enum_name_from_line(stripped_line_text), Utils.get_enum_members_in_line(stripped_line_text)]
			elif dec == &"const ":
				return Utils.get_const_name_and_type_in_line(stripped_line_text)
			elif dec == &"func " or dec == &"static func ":
				return Utils.get_func_data_from_declaration(stripped_line_text)
			elif dec == &"class ":
				return Utils.get_class_name_and_extends_in_line(stripped_line_text)
			elif dec == &"signal ":
				print("TODO: get_type_from_line_text - IMPLEMENT SIGNAL DATA")



static func get_line_declaration(stripped_line:String) -> StringName:
	for dec in Keywords.DECLARATIONS:
		if stripped_line.begins_with(dec):
			return dec
	return ""

static func get_control_flow(stripped_line:String) -> StringName:
	for cf in Keywords.CONTROL_FLOW_KEYWORDS:
		if stripped_line.begins_with(cf):
			return cf
	return ""

func _get_control_flow_expression(line:int, control_flow_word:String):
	var extended_line = get_extended_line(line)
	return extended_line.get_slice(control_flow_word, 1).get_slice(":", 0).strip_edges()


func remove_comment(line:int, line_text:String):
	var com_idx = line_text.find("#")
	while com_idx != -1:
		if code_edit.is_in_string(line, com_idx) != -1:
			com_idx = line_text.find("#", com_idx + 1)
		else:
			break
	return line_text.substr(0, com_idx)

func get_text_for_auto_complete(line:int, column:int):
	# if the caret or has been moved, reconstruct the string
	if column != code_edit.get_caret_column() or line != code_edit.get_caret_line():
		var lines = code_edit.text.split("\n")
		var current_line = lines[line] as String
		current_line = current_line.insert(column, Keys.CARET_UNI_CHAR)
		lines[line] = current_line
		return "\n".join(lines)
	else:
		return code_edit.get_text_for_code_completion()

#endregion


#region Function

## Get where the current branch forks from the func body.
func get_func_branch_start(line:int, target_indent_level:int, add_class_indent:=true):
	var current_access_indent = target_indent_level
	if add_class_indent:
		current_access_indent += indent_size
	
	var current_indent = get_indent_code_edit(line)
	if current_indent == current_access_indent:
		return line
	
	var i = line
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


func get_func_data_at_line(line:int): # this used to take stripped text, will I need this for source code?
	var stripped_text = get_line_context(line).strip_edges()
	print(stripped_text)
	if not (stripped_text.begins_with("func ") or stripped_text.begins_with("static func ")):
		return {}
	var func_data = {Keys.FUNC_ARGS:{}}
	var open_paren = stripped_text.find("(")
	var close_paren = stripped_text.rfind(")")
	if stripped_text.count("(") > 1:
		var string_map = get_string_map(stripped_text)
		open_paren = stripped_text.find("(")
		close_paren = string_map.bracket_map.get(open_paren)
		if close_paren == null:
			return {}
	
	open_paren += 1
	var args = stripped_text.substr(open_paren, close_paren - open_paren)
	if args.find(",") > -1:
		args = args.split(",", false)
	else:
		args = [args]
	for arg in args:
		if arg == "":
			continue
		var dummy_string = "var " + arg.strip_edges()
		var var_data = UString.get_var_name_and_type_hint_in_line(dummy_string)
		var var_nm = var_data[0]
		var type_hint = var_data[1]
		func_data[Keys.FUNC_ARGS][var_nm] = type_hint
	
	var return_idx = stripped_text.find("->")
	if return_idx > -1:
		var return_type = stripped_text.get_slice("->", 1)
		return_type = return_type.get_slice(":", 0).strip_edges()
		func_data[Keys.FUNC_RETURN] = return_type
	return func_data



#endregion


class Keywords:
	const DECLARATIONS = [VAR, STATIC_VAR, FUNC, STATIC_FUNC, CONST, SIGNAL, ENUM, CLASS]
	
	const VAR = &"var "
	const STATIC_VAR = &"static var " 
	const FUNC = &"func "
	const STATIC_FUNC = &"static func "
	const CONST = &"const "
	const SIGNAL = &"signal "
	const ENUM = &"enum "
	const CLASS = &"class "
	
	const CONTROL_FLOW_KEYWORDS = [FOR, MATCH, IF, ELIF, ELSE, WHILE]
	
	const FOR = &"for "
	const MATCH = &"match" # no space to allow for backslashes. Do I bother?
	const IF = &"if "
	const ELIF = &"elif "
	const ELSE = &"else:"
	const WHILE = &"while "
