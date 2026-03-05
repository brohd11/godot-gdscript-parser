const GDScriptParser = preload("res://addons/addon_lib/brohd/alib_runtime/utils/resource/gdscript/parser/gdscript_parser.gd")
const ParserClass = GDScriptParser.ParserClass
const Utils = GDScriptParser.Utils
const Keys = Utils.Keys
const UString = GDScriptParser.UString
const UClassDetail = GDScriptParser.UClassDetail

static func source(parser:GDScriptParser):
	var t = ALibRuntime.Utils.UProfile.TimeFunction.new("S")
	#_class_access.clear()
	var _code_edit = parser.code_edit
	var existing_class_access = parser._class_access
	var main_script = parser._script_resource
	
	var class_access_map = {}
	var member_map = {}
	var constant_map = {}
	var inner_class_map = {}
	
	class_access_map[""] = []
	var access_path = ""
	var current_indentation_level = 0
	var extended_lines = []
	
	
	var i = 0
	var code_edit_line_count = _code_edit.get_line_count() - 1
	for _i in range(code_edit_line_count):
		var line = _code_edit.get_line(i)
		
		#var stripped = UString.strip_comment(line).strip_edges()
		var stripped:String
		if line.find("#") > -1:
			stripped = remove_comment(i, line, _code_edit)
		else:
			stripped = line.strip_edges()
		
		if stripped == "":
			class_access_map[access_path].append(i)
			i += 1
			continue
		
		var next_i = i
		while stripped.ends_with("\\"):
			next_i += 1
			if not next_i < code_edit_line_count:
				break
			stripped = stripped.trim_suffix("\\")
			extended_lines.append(next_i)
			var next_line = _code_edit.get_line(next_i)
			if next_line.find("#") > -1:
				stripped += remove_comment(next_i, next_line, _code_edit).strip_edges(true, false)
			else:
				stripped += next_line.strip_edges(true, false)
			#stripped = stripped.strip_edges()
		
		
		#var indentation_level = line.count("\t")
		var indentation_level = Utils.get_indentation(line)
		if indentation_level < current_indentation_level:
			if stripped != "":
				var iterations = (current_indentation_level - indentation_level)
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
			var member_data = {
				Keys.MEMBER_NAME:inner_name,
				Keys.MEMBER_TYPE:Keys.MEMBER_TYPE_CLASS
			}
			inner_class_map.get_or_add(access_path, {})[inner_name] = member_data
			
			current_indentation_level += 1
			access_path = Utils.map_get_access_path(access_path, inner_name)
			class_access_map[access_path] = []
			
		
		if current_indentation_level == indentation_level:
			var member_data = Utils.get_member_data(stripped, i)
			if not member_data.is_empty():
				var member_type = member_data[Keys.MEMBER_TYPE]
				if member_type == Keys.MEMBER_TYPE_CONST or member_type == Keys.MEMBER_TYPE_ENUM:
					constant_map.get_or_add(access_path, {})[member_data[Keys.MEMBER_NAME]] = member_data
				else:
					member_map.get_or_add(access_path, {})[member_data[Keys.MEMBER_NAME]] = member_data
		
		class_access_map[access_path].append(i)
		if not extended_lines.is_empty():
			for index in extended_lines:
				class_access_map[access_path].append(index)
				i += 1
			extended_lines.clear()
		
		i += 1
	var temp_class_access = {}
	var _class_paths = class_access_map.keys()
	for path:String in _class_paths:
		var _class_obj:ParserClass
		if existing_class_access.has(path):
			_class_obj = existing_class_access[path]
		else:
			_class_obj = ParserClass.new()
			_class_obj.parser = weakref(parser)
			_class_obj.access_path = path
			
			var script = UClassDetail.get_member_info_by_path(main_script, access_path)
			if script != null:
				_class_obj.script_resource = script
			
		var class_lines = class_access_map[path]
		#for line_idx in class_lines:
			#_class_mask[line_idx] = path
		
		_class_obj.set_lines(class_lines)
		#print("___ %s ___" % path)
		
		var valid_constants:Dictionary = constant_map.get("", {}).duplicate()
		var valid_classes:Dictionary = inner_class_map.get("", {}).duplicate()
		if path != "":
			var working_path = path
			for x in range(path.count(".") + 1):
				valid_constants.merge(constant_map.get(working_path, {}))
				valid_classes.merge(inner_class_map.get(working_path, {}))
				working_path = working_path.substr(0, working_path.rfind("."))
		
		_class_obj.set_members(member_map.get(path, {}))
		_class_obj.set_constants(valid_constants)
		_class_obj.set_inner_classes(valid_classes)
		
		temp_class_access[path] = _class_obj
	
	parser._class_access = temp_class_access
	t.stop()
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



static func remove_comment(line:int, line_text:String, code_edit:CodeEdit):
	var com_idx = line_text.find("#")
	while com_idx != -1:
		if code_edit.is_in_string(line, com_idx) != -1:
			com_idx = line_text.find("#", com_idx + 1)
		else:
			break
	return line_text.substr(0, com_idx)

static func get_line_no_comment(line:int, code_edit:CodeEdit):
	var line_text = code_edit.get_line(line)
	var com_idx = line_text.find("#")
	while com_idx != -1:
		if code_edit.is_in_string(line, com_idx) != -1:
			com_idx = line_text.find("#", com_idx + 1)
		else:
			break
	return line_text.substr(0, com_idx)
	

#region CaretContext



static func parse_identifier_at_position(text:String, start_pos:int, string_map:UString.StringMap):
	var current_pos = start_pos
	var name_start_pos = start_pos + 1
	var last_char = ""
	while current_pos >= 0:
		if string_map.string_mask[current_pos] == 1:
			current_pos -= 1
			continue
		
		var _char = text[current_pos]
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
		
		last_char = char
		name_start_pos = current_pos
		current_pos -= 1
	
	return text.substr(name_start_pos, start_pos - name_start_pos + 1)





#static func get_word_before_caret():
	#var string_map = get_string_map(_current_line_text)
	#var identifier = _parse_identifier_at_position(_current_line_text, _current_caret_col - 1, string_map)
	#completion_cache[CompletionCache.WORD_BEFORE_CARET] = identifier
	##print("WORD BEFORE CARET: ", identifier)
	#return identifier

#static func get_char_before_caret():
	#var i = _current_caret_col - 1
	#var char = ""
	#while i >= 0:
		#char = _current_line_text[i]
		#if char != " ":
			#break
		#i -= 1
	#
	##print("CHAR BEFORE CARET: ", char)
	#return char


static func is_index_in_comment(column:int=-1, line:int=-1, code_edit=null):
	#if code_edit == null:
		#code_edit = _get_code_edit() as CodeEdit
	if line == -1:
		line = code_edit.get_caret_line()
	if column == -1:
		column = code_edit.get_caret_column()
	return code_edit.is_in_comment(line, column) > -1

static func is_index_in_string(column:int=-1, line:int=-1, code_edit=null):
	#if code_edit == null:
		#code_edit = _get_code_edit() as CodeEdit
	if line == -1:
		line = code_edit.get_caret_line()
	if column == -1:
		column = code_edit.get_caret_column()
	return code_edit.is_in_string(line, column) > -1








#endregion
