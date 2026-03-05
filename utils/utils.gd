const UString = preload("res://addons/addon_lib/brohd/alib_runtime/utils/u_string.gd")

const Keys = preload("res://addons/addon_lib/brohd/alib_runtime/utils/resource/gdscript/parser/utils/keys.gd")
const Parse = preload("res://addons/addon_lib/brohd/alib_runtime/utils/resource/gdscript/parser/utils/parse.gd")

static func map_get_access_path(access_path:String, member_name:String):
	if access_path == "":
		access_path = member_name
	else:
		access_path = access_path + "." + member_name
	return access_path

## Check if var name is present and increment if needed.
static func map_check_dupe_local_var_name(var_name:String, dict:Dictionary):
	if dict.has(var_name):
		var count = 1
		var name_check = var_name
		while dict.has(name_check):
			name_check = var_name + "%" + str(count)
			count += 1
		var_name = name_check
	return var_name

static func get_indentation(line:String):
	var count = 0
	var i = 0
	while i < line.length():
		if line[i] == "\t":
			count += 1
		else:
			break
		i += 1
	return count

static func get_extended_line(code_edit:CodeEdit, line_index:int):
	var full_line = code_edit.get_line(line_index)
	var start_i = line_index - 1
	while start_i >= 0:
		var line = code_edit.get_line(start_i)
		if not line.ends_with("\\"):
			break
		line = UString.strip_comment(line)
		full_line = line + full_line
		start_i -= 1
	
	start_i = line_index + 1
	while start_i < code_edit.get_line_count() - 1:
		var line = code_edit.get_line(start_i)
		if not line.ends_with("\\"):
			break
		line = UString.strip_comment(line)
		full_line += line
		start_i += 1
	return full_line

static func get_full_line_context(code_edit:CodeEdit, line_index:int):
	#var in_delim = code_edit.
	
	
	pass


## Get func declaration string from file as lines, accounts for multiline.
static func get_func_declaration_lines(current_line:int, lines:PackedStringArray):
	var line_count = lines.size()
	var func_text = lines[current_line]
	func_text = UString.remove_comment(func_text).strip_edges()
	var open_count = func_text.count("(")
	var close_count = func_text.count(")")
	if open_count == close_count:
		return func_text.strip_edges()
	
	var i = current_line + 1
	while (open_count - close_count != 0) and i < line_count:
		var next_line = lines[i]
		next_line = UString.remove_comment(next_line).strip_edges()
		open_count += next_line.count("(")
		close_count += next_line.count(")")
		func_text += next_line
		i += 1
	
	var colon_i = func_text.rfind(":") + 1
	func_text = func_text.substr(0, colon_i)
	return func_text.strip_edges()

## Get func declaration string from file as text, accounts for multiline.
static func get_func_declaration_source(source_code:String):
	var new_line_i = source_code.find("\n")
	var func_text = source_code.substr(0, new_line_i)
	func_text = UString.remove_comment(func_text).strip_edges()
	var open_count = func_text.count("(")
	var close_count = func_text.count(")")
	if open_count == close_count:
		return func_text
	
	while (open_count - close_count != 0) and new_line_i > -1:
		var next_new_line_i = source_code.find("\n", new_line_i + 1)
		# handle error?
		var next_line = source_code.substr(new_line_i, next_new_line_i - new_line_i)
		next_line = UString.remove_comment(next_line).strip_edges()
		open_count += next_line.count("(")
		close_count += next_line.count(")")
		func_text += next_line
		new_line_i = next_new_line_i
	
	var colon_i = func_text.rfind(":") + 1
	func_text = func_text.substr(0, colon_i)
	return func_text.strip_edges()

static func get_func_declaration_editor(current_line:int, script_editor:CodeEdit):
	var line_count = script_editor.get_line_count()
	var func_text = script_editor.get_line(current_line)
	func_text = UString.remove_comment(func_text).strip_edges()
	var open_count = func_text.count("(")
	var close_count = func_text.count(")")
	if open_count == close_count:
		return func_text.strip_edges()
	
	var i = current_line + 1
	while (open_count - close_count != 0) and i < line_count:
		var next_line = script_editor.get_line(i)
		next_line = UString.remove_comment(next_line).strip_edges()
		open_count += next_line.count("(")
		close_count += next_line.count(")")
		func_text += next_line
		i += 1
	
	var colon_i = func_text.rfind(":") + 1
	func_text = func_text.substr(0, colon_i)
	return func_text.strip_edges()


static func get_func_data_from_declaration(stripped_text:String):
	var func_data = {Keys.FUNC_ARGS:{}}
	var open_paren = stripped_text.find("(")
	var close_paren = stripped_text.rfind(")")
	if stripped_text.count("(") > 1:
		#var string_map = UString.get_string_map(stripped_text)
		var string_map = UString.get_string_map(stripped_text)
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


## Get enum declaration from file as lines, accounts for multiline.
static func get_enum_lines(current_line:int, lines:PackedStringArray):
	var line_count = lines.size()
	var enum_text = lines[current_line]
	enum_text = UString.remove_comment(enum_text).strip_edges()
	var open_count = enum_text.count("{")
	var close_count = enum_text.count("}")
	if open_count == close_count:
		return enum_text.strip_edges()
	
	var found_close = false
	var i = current_line + 1
	while not found_close and i < line_count:
		var next_line = lines[i]
		next_line = UString.remove_comment(next_line).strip_edges()
		var close_idx = next_line.find("}")
		if close_idx > -1:
			found_close = true
			next_line = next_line.substr(0, close_idx + 1)
		enum_text += next_line
		i += 1
	return enum_text.strip_edges()

## Get enum declaration from file as text, accounts for multiline.
static func get_enum_source(source_code:String):
	var new_line_i = source_code.find("\n")
	var enum_text = source_code.substr(0, new_line_i)
	enum_text = UString.remove_comment(enum_text).strip_edges()
	var open_count = enum_text.count("{")
	var close_count = enum_text.count("}")
	if open_count == close_count:
		return enum_text.strip_edges()
	
	var found_close = false
	while not found_close and new_line_i > -1:
		var next_new_line_i = source_code.find("\n", new_line_i + 1)
		var next_line = source_code.substr(new_line_i, next_new_line_i - new_line_i)
		next_line = UString.remove_comment(next_line).strip_edges()
		var close_idx = next_line.find("}")
		if close_idx > -1:
			found_close = true
			next_line = next_line.substr(0, close_idx + 1)
		enum_text += next_line
		new_line_i = next_new_line_i
	return enum_text.strip_edges()

## Get members of an enum in it's declaration text.
static func get_enum_members_in_line(stripped_text:String) -> Dictionary:
	var members = stripped_text.get_slice("{", 1)
	members = members.get_slice("}", 0).strip_edges()
	var members_array
	if members.find(",") > -1:
		members_array = members.split(",", false)
	else:
		members_array = [members]
	
	var enum_data = {}
	for i in range(members_array.size()):
		var m = members_array[i]
		m = m.strip_edges()
		enum_data[m] = i
	return enum_data




static func remove_comment(text:String, string_safe:=false, string_map=null):
	if not string_safe:
		return text.get_slice("#", 0)
	else:
		if string_map == null:
			string_map = UString.get_string_map(text)
		var comment_index = UString.string_safe_find(text, "#", 0, string_map)
		if comment_index > -1:
			text = text.substr(0, comment_index)
	return text

static func get_func_name_in_line(stripped_line_text:String) -> String:
	if not (stripped_line_text.begins_with("func ") or stripped_line_text.begins_with("static func ")):
		return ""
	var func_name = stripped_line_text.get_slice("func ", 1).get_slice("(", 0)
	return func_name

static func get_class_name_in_line(stripped_line_text:String) -> String:
	if not stripped_line_text.begins_with("class "): # "" <- parser
		return ""
	var _class = stripped_line_text.get_slice("class ", 1).get_slice(":", 0) # "" <- parser
	if _class.find("extends ") > -1: #  "" <- parser
		_class = _class.get_slice("extends ", 0) #  "" <- parser
	return _class.strip_edges()

static func get_var_name_and_type_hint_in_line(stripped_line_text:String): # for local vars
	var var_idx = stripped_line_text.find("var ")
	if not(var_idx == 0 or var_idx == 7): # start with or static
		return null
	
	var var_dec = stripped_line_text.substr(var_idx + 4)
	return _get_name_and_type_from_line(var_dec)

static func get_const_name_and_type_in_line(stripped_line_text:String):
	var const_idx = stripped_line_text.find("const ")
	if const_idx != 0:
		return null
	var preload_path = ""
	if stripped_line_text.find('preload("') > -1:
		preload_path = stripped_line_text.get_slice("preload(", 1) #""
		preload_path = preload_path.get_slice(")", 0)
		preload_path = preload_path.trim_prefix("'").trim_suffix("'").trim_prefix('"').trim_suffix('"')
		var const_name = stripped_line_text.get_slice("preload(", 0)
		const_name = const_name.substr(const_idx + 6)
		const_name = const_name.replace("=","").replace(":", "").strip_edges()
		return [const_name, preload_path]
	
	var const_dec = stripped_line_text.substr(const_idx + 6)
	var data = _get_name_and_type_from_line(const_dec)
	return data

static func get_enum_name_from_line(stripped_line_text:String):
	var enum_idx = stripped_line_text.find("enum ")
	if enum_idx == -1:
		return ""
	var enum_text = stripped_line_text.get_slice("enum ", 1)
	enum_text = enum_text.get_slice("{", 0)
	return enum_text


static func _get_name_and_type_from_line(declaration:String):
	var colon_idx = declaration.find(":")
	var has_colon = colon_idx > -1
	var eq_idx = declaration.find("=")
	var has_eq = eq_idx > -1
	
	var var_nm:String
	var type_hint:String = ""
	if has_colon and has_eq:
		var col_sub_idx = colon_idx + 1
		var_nm = declaration.substr(0, col_sub_idx - 1).strip_edges()
		type_hint = declaration.substr(col_sub_idx, eq_idx - col_sub_idx).strip_edges()
		if type_hint == "":
			type_hint = declaration.get_slice("=", 1).strip_edges()
	elif has_colon:
		var_nm = declaration.get_slice(":", 0).strip_edges()
		type_hint = declaration.get_slice(":", 1).strip_edges()
	elif has_eq:
		var_nm = declaration.get_slice("=", 0).strip_edges()
		type_hint = declaration.get_slice("=", 1).strip_edges()
	else:
		var_nm = declaration.strip_edges()
	
	return [var_nm, type_hint]

const DECLARATIONS = ["class ", "var ", "static ", "func ", "enum ", "const "]

static func line_has_any_declaration(stripped_line:String):
	for dec in DECLARATIONS:
		if stripped_line.begins_with(dec):
			return true
	return false

static func get_member_data(stripped_line:String, line_index:int):
	var data = {}
	var func_name = get_func_name_in_line(stripped_line)
	if func_name != "":
		#stripped_line = _get_func_declaration_editor(i)
		var member_type = Keys.MEMBER_TYPE_FUNC
		if stripped_line.begins_with("static"):
			member_type = Keys.MEMBER_TYPE_STATIC_FUNC
		data[Keys.MEMBER_TYPE] = member_type
		data[Keys.MEMBER_NAME] = func_name
			#Keys.SNAPSHOT: stripped_line,
			#Keys.INDENT: indent,
	
	var var_check = get_var_name_and_type_hint_in_line(stripped_line)
	if var_check != null:
		var member_type = Keys.MEMBER_TYPE_VAR
		if stripped_line.begins_with("static"):
			member_type = Keys.MEMBER_TYPE_STATIC_VAR
		data[Keys.MEMBER_TYPE] = member_type
		data[Keys.MEMBER_NAME] = var_check[0]
		data[Keys.TYPE] = var_check[1]
			##Keys.SNAPSHOT: stripped_line,
			##Keys.INDENT: indent,
	
	var const_check = get_const_name_and_type_in_line(stripped_line)
	if const_check != null:
		data[Keys.MEMBER_TYPE] = Keys.MEMBER_TYPE_CONST
		data[Keys.MEMBER_NAME] = const_check[0]
		data[Keys.TYPE] = const_check[1]
			
			##Keys.SNAPSHOT: stripped_line,
			##Keys.INDENT: indent,
	
	var enum_name = get_enum_name_from_line(stripped_line)
	if enum_name != "":
		data[Keys.MEMBER_TYPE] = Keys.MEMBER_TYPE_ENUM
		data[Keys.MEMBER_NAME] = enum_name
		data[Keys.TYPE] = enum_name
		#var enum_text = Utils.get_enum_lines(i)
			##Keys.SNAPSHOT: enum_text,
			##Keys.INDENT: indent,
	
	if not data.is_empty():
		data[Keys.LINE_INDEX] = line_index
	return data
