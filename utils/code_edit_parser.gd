#! import-p Keys,

const GDScriptParser = preload("res://addons/addon_lib/brohd/alib_runtime/utils/resource/gdscript/parser/gdscript_parser.gd")
const ParserClass = GDScriptParser.ParserClass
const Utils = GDScriptParser.Utils
const Keys = Utils.Keys
const UString = GDScriptParser.UString
const UClassDetail = GDScriptParser.UClassDetail
const Keywords = Utils.Keywords

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
var _annotation_regex:RegEx

var _first_parse_complete:=false
var cache_dirty:=true

func _set_code_edit(new_code_edit:CodeEdit):
	if is_instance_valid(code_edit):
		if code_edit != new_code_edit:
			if code_edit.text_changed.is_connected(_on_text_changed):
				code_edit.text_changed.disconnect(_on_text_changed)
			cache_dirty = true
			_first_parse_complete = false
	
	code_edit = new_code_edit
	if not code_edit.text_changed.is_connected(_on_text_changed):
		code_edit.text_changed.connect(_on_text_changed)
	
	pass

func _on_text_changed():
	cache_dirty = true

var _pc:_ParserContext

class _ParserContext:
	var class_access_map = {&"":[]}
	var member_map := {}
	var constant_map := {}
	var inner_class_map := {}
	
	var access_path:StringName = &""
	var current_indentation_level:int = 0
	var extended_lines:= []
	var pending_annotations:= []
	
	var in_function:= false
	var current_func_dict:={}
	
	var class_name_data:= {}
	var main_script_path:=""

func ensure_first_parse():
	if _first_parse_complete:
		return
	parse_text()

func parse_text(force:=false):
	if not is_instance_valid(_map_regex):
		_map_regex = RegEx.new()
		_map_regex.compile("^(?:(static)\\s+)?(var|func|enum|const|signal|class_name|class)\\s+([a-zA-Z_]\\w*)")
	_initialize_regex_annotation()
	
	
	var parser = _get_parser()
	var t = ALibRuntime.Utils.UProfile.TimeFunction.new("S::" + parser.get_script_path())
	_set_code_edit(parser.code_edit)
	indent_size = code_edit.get_tab_size()
	
	var existing_class_access = parser._class_access # if existing class is empty, then it hasn't been parsed
	if existing_class_access.is_empty():
		cache_dirty = true
	
	if not cache_dirty and not force: # cache_dirty means text is changed. If it hasn't then everything should be valid
		#t.stop()
		#print("CODE EDIT PARSE EARLY EXIT::", parser.get_script_path().get_file())
		return
	
	var main_script = parser._script_resource
	var main_script_path = main_script.resource_path
	
	
	_pc = _ParserContext.new()
	_pc.main_script_path = StringName(main_script_path)
	
	var class_access_map = _pc.class_access_map
	var extended_lines = _pc.extended_lines
	
	var i = 0
	var code_edit_line_count = code_edit.get_line_count() - 1
	for _i in range(code_edit_line_count):
		if i > code_edit_line_count: # some how get line can return a blank line when calling out of range?
			break
		var stripped:String = get_line(i, true, true)
		if stripped == "":
			class_access_map[_pc.access_path].append(i)
			if _pc.in_function:
				_pc.current_func_dict[Keys.FUNC_LINES].append(i)
			#print("CURRENT TOP::", i, "::EXTENDED LINES::", extended_lines, _pc.current_func_dict.get(Keys.FUNC_LINES))
			i += 1
			continue
		
		var has_semi_col = stripped.find(";") > -1
		if has_semi_col:
			var data = get_semi_colon_strings(i)
			for column in data.keys():
				var text = data[column]
				_parse_line(text, i, column)
		else:
			_parse_line(stripped, i)
		
		class_access_map[_pc.access_path].append(i)
		if _pc.in_function:
			_pc.current_func_dict[Keys.FUNC_LINES].append(i)
		
		if not extended_lines.is_empty():
			for index in extended_lines:
				class_access_map[_pc.access_path].append(index)
				if _pc.in_function:
					_pc.current_func_dict[Keys.FUNC_LINES].append(index)
				i += 1
			extended_lines.clear()
		
		i += 1
	
	var temp_class_access = {}
	var _class_paths = class_access_map.keys()
	for path:String in _class_paths:
		var _class_obj:ParserClass
		if existing_class_access.has(path):
			_class_obj = existing_class_access[path]
			_class_obj.queue_refresh()
		if not is_instance_valid(_class_obj):
			_class_obj = ParserClass.new()
			Utils.ParserRef.set_refs(_class_obj, parser)
			_class_obj.access_path = path
			_class_obj.indent_level = get_indent_access_path(path)
		
		var members = _pc.member_map.get(path, {})
		_class_obj.set_extends(members.get("extends", "RefCounted"))
		members.erase("extends")
		
		var valid_constants:Dictionary = _pc.constant_map.get("", {}).duplicate()
		var valid_classes:Dictionary = _pc.inner_class_map.get("", {}).duplicate()
		if path != "":
			var working_path = ""
			var parts = UString.split_member_access(path)
			for x in range(parts.size()):
				var part = parts[x]
				working_path = UString.dot_join(working_path, part)
				valid_constants.merge(_pc.constant_map.get(working_path, {}), true)
				#valid_classes.merge(_pc.inner_class_map.get(working_path, {}), true)
				var classes = _pc.inner_class_map.get(working_path, {})
				for name in classes.keys():
					# for proper scoping, act like merge with no overwrite
					var class_data = classes[name]
					if not valid_classes.has(name):
						valid_classes[name] = class_data
						continue
					
					# but if the class is self, then it ovewrites, inner classes at the same level will
					# defer to the lower level if they are named the same ie. Nested.Nested and Nested.Another
					# Nested.Another will access Nested when typing Nested, not the nested class. Whereas if it has a unique name
					# it can be accessed directly. Nested.Nested will access itself when typing Nested,
					if class_data.get(Keys.ACCESS_PATH) == path: # so it overides here.
						valid_classes[name] = class_data
		
		
		_class_obj.main_script_path = _pc.main_script_path
		if path == "":
			_class_obj.set_script_resource(parser._script_resource)
			_class_obj.class_name_data = _pc.class_name_data
		else:
			#_class_obj.set_script_resource(UClassDetail.get_member_info_by_path(main_script, _pc.access_path))
			var inner_script = UClassDetail.get_member_info_by_path(main_script, path)
			#prints("INNERSCRIPT::", inner_script, "::PATH::", path)
			_class_obj.set_script_resource(inner_script)
		
		var class_lines = class_access_map[path]
		_class_obj.set_lines(class_lines)
		
		_class_obj.set_members(members)
		_class_obj.set_constants(valid_constants)
		_class_obj.set_inner_classes(valid_classes)
		
		temp_class_access[path] = _class_obj
	
	# remove classes that may have been removed
	for access_path in parser._class_access.keys():
		if not temp_class_access.has(access_path):
			parser._class_access.erase(access_path)
	
	# reassign the classes and new classes
	parser.set_class_objs(temp_class_access)
	
	#t.stop()
	#print("CLASSES ",temp_class_access.keys())
	cache_dirty = false
	_first_parse_complete = true
	_pc = null
	return temp_class_access


func _parse_line(stripped:String, line:int, column:int=0):
	var has_extension = stripped.ends_with("\\")
	if has_extension or stripped.begins_with("@"):
		if has_extension or _line_has_open_bracket(stripped): # complex case, get full context # old version just checked stripped.count('(') != stripped.count(')')
			var context_data = get_line_context(line, 0, false, {Keys.CONTEXT_START: line})
			var end_index = context_data.get(Keys.CONTEXT_END)
			for e_i in range(line + 1, end_index):
				_pc.extended_lines.append(e_i)
			stripped = context_data.get(Keys.CONTEXT_TEXT, "").strip_edges()
		
		while stripped.begins_with("@"):
			var _match = _annotation_regex.search(stripped)
			if _match:
				var matched_text = _match.get_string()
				_pc.pending_annotations.append(matched_text.strip_edges())
				stripped = stripped.substr(matched_text.length()) # Slice the annotation off the front of the line
			else:
				break # Failsafe
	
	var indentation_level = get_indent_code_edit(line)
	if indentation_level < _pc.current_indentation_level:
		if stripped != "":
			var iterations = (_pc.current_indentation_level - indentation_level) / indent_size
			for z in range(iterations):
				var dot = _pc.access_path.rfind(".")
				if dot == -1:
					_pc.access_path = StringName("")
					break
				else:
					_pc.access_path = StringName(_pc.access_path.substr(0, _pc.access_path.rfind(".")))
			
			#prints("DROP LEVEL:", indentation_level, current_indentation_level,old_access_path, " -> ", access_path)
			_pc.current_indentation_level = indentation_level
	
	if not (stripped.begins_with("class") or _pc.current_indentation_level == indentation_level):
		return
	
	var result = _map_regex.search(stripped)
	if result:
		var keyword = result.get_string(2)
		if result.get_string(1) != "":
			if result.get_string(1) != "static":
				printerr("REGEX MISTAKE SHOULD BE STATIC ", result.get_string(1))
			keyword = "static " + keyword
		var member_name = result.get_string(3)
		
		var data = {
			Keys.MEMBER_TYPE:keyword,
			Keys.MEMBER_NAME:member_name,
			Keys.LINE_INDEX:line,
			Keys.SCRIPT_PATH: _pc.main_script_path,
			Keys.ACCESS_PATH: _pc.access_path,
		}
		if not _pc.pending_annotations.is_empty():
			data[Keys.ANNOTATIONS] = _pc.pending_annotations.duplicate()
			_pc.pending_annotations.clear()
		
		_pc.in_function = false
		if keyword == "class":
			var new_access_path = UString.dot_join(_pc.access_path, member_name)
			#data[Keys.MEMBER_TYPE] = Keys.MEMBER_TYPE_CLASS
			data[Keys.TYPE] = UString.dot_join(_pc.main_script_path, new_access_path)
			
			_pc.inner_class_map.get_or_add(_pc.access_path, {})[member_name] = data
			
			var line_context = stripped
			if stripped.ends_with("\\"):
				line_context = get_line_context(line, 0, false, {Keys.CONTEXT_START:line}).get(Keys.CONTEXT_TEXT, stripped).strip_edges()
			if line_context.contains(" extends "):
				var extended = _get_extends_out_line(line_context)
				_pc.member_map.get_or_add(new_access_path, {})["extends"] = extended
			
			
			_pc.current_indentation_level += indent_size
			_pc.access_path = new_access_path
			_pc.class_access_map[_pc.access_path] = []
		else:#if _pc.current_indentation_level == indentation_level:
			data[Keys.COLUMN_INDEX] = column
			if keyword.ends_with("func"):
				_pc.current_func_dict = data
				_pc.in_function = true
				data[Keys.FUNC_LINES] = PackedInt32Array()
				_pc.member_map.get_or_add(_pc.access_path, {})[member_name] = data
			elif keyword == "class_name":
				if stripped.contains(" extends "):
					var extended = _get_extends_out_line(stripped)
					_pc.member_map.get_or_add(_pc.access_path, {})["extends"] = extended
				_pc.class_name_data = data
			elif keyword.begins_with("c") or keyword == "enum":
				_pc.constant_map.get_or_add(_pc.access_path, {})[member_name] = data
			else:
				_pc.member_map.get_or_add(_pc.access_path, {})[member_name] = data
	elif stripped.begins_with("extends "):
		var extended = _get_extends_out_line(stripped)
		_pc.member_map.get_or_add(_pc.access_path, {})["extends"] = extended


func _get_extends_out_line(line_text:String):
	var extends_string:String
	if line_text.begins_with("extends"):
		extends_string = line_text
	else:
		extends_string = line_text.substr(line_text.find(" extends ")).strip_edges()
	
	var class_info = Utils.get_class_info("class dummy " + extends_string + ":")
	var extended = class_info[1]
	if extended == "":
		extended = "RefCounted"
	elif Utils.token_is_string(extended):
		extended = Utils.get_full_path_from_string(extended)
		extended = Utils.ensure_absolute_path(extended, _pc.main_script_path)
	return extended


func _line_has_open_bracket(stripped:String):
	if stripped.count("(") != stripped.count(")"):
		return true
	if stripped.count("{") != stripped.count("}"):
		return true
	if stripped.count("[") != stripped.count("]"):
		return true
	return false


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
	var all_blocks_array = Keywords.CONTROL_FLOW_KEYWORDS
	var map_blocks_array = params.get(Keys.CONTEXT_BLOCKS, []) as Array
	var has_blocks = not map_blocks_array.is_empty()
	var map_local_vars = params.get(Keys.CONTEXT_LOCAL_VARS, true) as bool
	
	var respect_scope = has_blocks or map_local_vars
	
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
		
		if respect_scope:
			var line_indent = get_indent_code_edit(context_start_line)
			if line_indent <= current_indent:
				if line_indent < current_indent:
					for control_flow in Keywords.CONTROL_FLOW_KEYWORDS:
						if stripped.begins_with(control_flow):
							current_indent = line_indent
							if control_flow in map_blocks_array:
								if control_flow == Keywords.FOR:
									var var_dec = "var " + stripped.get_slice("for ", 1).get_slice(" in ", 0).strip_edges()
									var var_data = Utils.add_var_to_dict(var_dec, context_start_line, local_vars)
									blocks.append({"type":"for",
									"indent": line_indent,
									"var":{"name": var_data[0], "type": var_data[1]}})
								else:
									blocks.append({"type":control_flow.strip_edges(),
									"indent": line_indent,
									"expr": _get_control_flow_expression(context_start_line, control_flow)})
				
				if map_local_vars:
					var var_data = Utils.add_var_to_dict(stripped, context_start_line, local_vars)
					if var_data != null:
						#print("MAP LOCAL::", var_data, "::IND::CUR::", current_indent, "::LINE::", line_indent)
						continue
				else:
					if not Utils.line_has_any_declaration(stripped):
						continue
					if not stripped.begins_with("func "):
						break
				if Utils.get_func_name_in_line(stripped) != "":
					break
	
	return {
		Keys.CONTEXT_SEMI_COLON: has_semi_col,
		Keys.CONTEXT_START: context_start_line,
		Keys.CONTEXT_BLOCKS: blocks,
		Keys.CONTEXT_LOCAL_VARS:local_vars
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
			break
	
	return {
		Keys.CONTEXT_SEMI_COLON: has_semi_col,
		Keys.CONTEXT_START: context_start_line,
	}





func get_line_context(target_line_index:int, _caret_column:=0, insert_caret:=false, start_data:={}) -> Dictionary:
	if not is_instance_valid(context_regex):
		context_regex = RegEx.new()
		context_regex.compile("[\"'(){}\\[\\]]")
	
	#var t = ALibRuntime.Utils.UProfile.TimeFunction.new("Get Caret Context")
	if start_data.is_empty():
		start_data = get_line_context_start_simple(target_line_index)
	
	var has_semi_col:bool = start_data.get(Keys.CONTEXT_SEMI_COLON, false)
	var context_start_line:int = start_data.get(Keys.CONTEXT_START, target_line_index)
	var context_end_line:int = target_line_index + 1
	#prints("HAS SEMI COL", has_semi_col, _caret_column)
	
	var bracket_depth = 0
	var in_string = code_edit.is_in_string(context_start_line, 0) != -1
	var is_prev_continued = false
	for i in range(context_start_line, code_edit.get_line_count() - 1):
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
			else:
				caret_idx = _caret_column + context_text.length()
			
		if code_edit.is_in_string(i) == -1:
			var not_first = i > context_start_line
			var line_text = line.strip_edges(not_first, true).trim_suffix("\\")
			if not_first:
				line_text = " " + line_text
			context_text += line_text
		else:
			context_text += "\n" + line
	
	
	if has_semi_col:# and _caret_column > 0:
		var string_map = get_string_map(context_text)
		var semi_prev = UString.string_safe_rfind(context_text, ";", caret_idx, string_map) + 1
		var semi_next = UString.string_safe_find(context_text, ";", caret_idx, string_map)
		context_text = context_text.substr(semi_prev, semi_next - semi_prev)
	
	
	#t.stop()
	var return_data = {
		Keys.CONTEXT_TEXT: context_text,
		Keys.CONTEXT_START: context_start_line,
		Keys.CONTEXT_END: context_end_line,
	}
	
	return return_data


func _line_has_semi_colon(line:int):
	var line_text = code_edit.get_line(line) # musn't be stripped on left for is_valid_code with semi
	var semi_i = line_text.rfind(";")
	while semi_i != -1:
		if not is_valid_code(line, semi_i):
			semi_i = line_text.rfind(";", semi_i - 1)
		else:
			return true
	return false


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

func parse_expression_at_position(text_to_process: String, start_pos: int, string_map=null) -> String:
	if string_map == null:
		string_map = get_string_map(text_to_process)
	var current_pos = start_pos
	var name_start_pos = start_pos + 1
	
	# These flags act as a tiny "State Machine" to handle whitespace safely
	var expecting_operator = false 
	var last_was_ident = false
	
	while current_pos >= 0:
		# 1. Safely walk backward through strings
		if string_map.string_mask[current_pos] == 1:
			name_start_pos = current_pos
			current_pos -= 1
			last_was_ident = true # A string acts like an identifier block
			continue
		
		var _char = text_to_process[current_pos]
		
		# 2. Handle Whitespace boundaries safely
		if _char == " " or _char == "\t" or _char == "\n":
			if last_was_ident:
				# If we read a word, and hit a space, the ONLY valid thing 
				# to the left of this space is an operator (like a dot or bracket).
				expecting_operator = true
			current_pos -= 1
			continue
			
		# 3. Handle Brackets (Method calls AND Index access)
		if _char == ")" or _char == "]" or _char == "}":
			current_pos = string_map.bracket_map.get(current_pos, current_pos)
			last_was_ident = true
			expecting_operator = false
			name_start_pos = current_pos
			current_pos -= 1
			continue
			
		# 4. Handle Member Access (.)
		if _char == ".":
			expecting_operator = false
			last_was_ident = false
			name_start_pos = current_pos
			current_pos -= 1
			continue
			
		# 5. Handle Node Path Terminals ($ and %)
		if _char == "$" or _char == "%":
			# These characters exclusively mark the BEGINNING of an expression.
			name_start_pos = current_pos
			break # Stop scanning entirely
			
		# 6. Check for Valid Expression Characters
		# We include '/' specifically so NodePaths parse seamlessly
		var is_ident = (_char >= 'a' and _char <= 'z') or \
					   (_char >= 'A' and _char <= 'Z') or \
					   (_char >= '0' and _char <= '9') or \
					   _char == '_' or _char == '/'
					   
		if is_ident:
			if expecting_operator:
				# Example: "var my_func"
				# We read "my_func", hit a space, and now hit "r" (from var).
				# This is a word boundary! We must stop scanning here.
				break
				
			last_was_ident = true
			name_start_pos = current_pos
			current_pos -= 1
			continue
			
		# 7. If it's a comma, plus, minus, equals, etc... we reached the edge!
		break
		
	var final_expr = text_to_process.substr(name_start_pos, start_pos - name_start_pos + 1)
	return final_expr.strip_edges()



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



func get_line(line:int, strip_comment:=false, strip_left:=false):
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
		return line_text.substr(0, com_idx).strip_edges(strip_left, true)

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

func strip_annotations(stripped_text:String):
	_initialize_regex_annotation()
	while stripped_text.begins_with("@"):
		var _match = _annotation_regex.search(stripped_text)
		if _match:
			var matched_text = _match.get_string()
			stripped_text = stripped_text.substr(matched_text.length()) # Slice the annotation off the front of the line
		else:
			break # Failsafe
	return stripped_text

func check_member_line(member_type:String, member_name:String, line:int, column:int=0, rebuild:=true):
	var t = ALibRuntime.Utils.UProfile.TimeFunction.new("CHECK MEMBER" + str([member_type, " ", member_name]))
	var line_text = get_line(line).strip_edges(true, false)
	if column != 0:
		line_text = get_line(line).substr(column).strip_edges(true, false)
	if line_text.begins_with("@"):
		line_text = strip_annotations(line_text)
	if line_text.begins_with(member_type):
		var stripped = line_text.trim_prefix(member_type).strip_edges(true, false)
		#t.stop()
		return stripped.begins_with(member_name)
	#t.stop()
	if rebuild:
		parse_text()
	return false

func find_member_line(member_type:String, member_name:String, class_obj:ParserClass, class_indent:=-1):
	var t = ALibRuntime.Utils.UProfile.TimeFunction.new("FIND MEMBER")
	if class_indent == -1:
		class_indent = class_obj.indent_level + get_indent_size()
	print(class_indent)
	for i in range(code_edit.get_line_count()):
		var line = get_line(i).strip_edges(true, false)
		if line.contains(";"): # need to deal with this somehow?
			pass
		if not line.begins_with(member_type):
			continue
		var stripped = line.trim_prefix(member_type).strip_edges(true, false)
		if not stripped.begins_with(member_name):
			continue
		if code_edit.get_indent_level(i) == class_indent:
			#t.stop()
			return i
	#t.stop()
	return -1

func get_type_from_line(line:int, column:int=0):
	var context = get_line_context(line, column).get(Keys.CONTEXT_TEXT, "")
	#print("RAW CONTEXT ", context)
	return get_type_from_line_text(context.strip_edges())

## returns an array with [member_name, member_type], except functions, which return a dict {func_args, func_return}, keys are in Keys class
func get_type_from_line_text(stripped_line_text:String):
	var data = {}
	if stripped_line_text.begins_with("@"):
		stripped_line_text = strip_annotations(stripped_line_text)
	if stripped_line_text.begins_with(Keywords.FOR):
		stripped_line_text = "var " + stripped_line_text.get_slice("for ", 1).get_slice(" in ", 0).strip_edges()
		data["result"] = Utils.get_var_or_const_info(stripped_line_text)
		data["type"] = Keys.MEMBER_TYPE_VAR
		return data
	for dec:StringName in Keywords.DECLARATIONS:
		if stripped_line_text.begins_with(dec):
			if dec == &"var " or dec == &"static var ":
				data["result"] = Utils.get_var_or_const_info(stripped_line_text)
			elif dec == &"enum ":
				data["result"] = Utils.get_enum_info(stripped_line_text)
			elif dec == &"const ":
				data["result"] = Utils.get_var_or_const_info(stripped_line_text)
			elif dec == &"func " or dec == &"static func ":
				data["result"] = Utils.get_func_info(stripped_line_text)
			elif dec == &"class ":
				printerr("GET TYPE FROM LINE CLASS - IF THIS CALLS NEED TO MANAGE EXTENDING PATHS")
				data["result"] = Utils.get_class_info(stripped_line_text)
			elif dec == &"signal ":
				data["result"] = Utils.get_signal_info(stripped_line_text)
			if data.is_empty():
				return {}
			data["type"] = StringName(dec.strip_edges())
			return data
	return {}



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


func get_semi_colon_strings(line:int):
	var line_text = get_line(line, true)
	var semi_idx = line_text.find(";")
	var stmt_start_idx = 0  # Renamed for clarity: this tracks the start of the current statement
	var data = {}

	while semi_idx != -1:
		if is_valid_code(line, semi_idx):
			data[stmt_start_idx] = line_text.substr(stmt_start_idx, semi_idx - stmt_start_idx)
			stmt_start_idx = semi_idx + 1
		semi_idx = line_text.find(";", semi_idx + 1)
	
	if stmt_start_idx < line_text.length():
		var remainder = line_text.substr(stmt_start_idx)
		if not remainder.strip_edges().is_empty():
			data[stmt_start_idx] = remainder
	return data

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




#endregion


func _initialize_regex_annotation():
	if not is_instance_valid(_annotation_regex):
		_annotation_regex = RegEx.new()
		_annotation_regex.compile("^@[A-Za-z0-9_]+(?:\\([^)]*\\))?\\s*")
