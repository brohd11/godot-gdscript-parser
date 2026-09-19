## Regex-based parsing of single GDScript declaration lines (var/const/func/signal/enum/class).
## Line-local and lexical only - no scope or type resolution, which is the parser's job.

const URFile = GDScriptParser.URFile
const URString = GDScriptParser.URString

const UFile = URFile
const UString = URString


const _QUOTES = ["'", '"']


static var _class_regex:RegEx
static var _var_const_regex:RegEx
static var _for_loop_regex:RegEx
static var _preload_regex:RegEx
static var _enum_regex:RegEx
static var _func_regex:RegEx
static var _arg_regex:RegEx
static var _signal_regex:RegEx

## Check if a path is an absolute path, but not a string wrapped in quotes
static func is_absolute_path(string:String) -> bool:
	if not string.is_absolute_path():
		return false # quick exit, definitely not raw path
	
	if string.begins_with("res://") or string.begins_with("user://"):
		return true
	if string.begins_with("/") or string.begins_with("\\"):
		return true
	# check Windows drive letter ("C:/", "d:\")
	if string.length() >= 3 and string[1] == ":" and (string[2] == "/" or string[2] == "\\"):
		# Use unicode_at() for the fastest possible letter check (avoids string allocation)
		var c := string.unicode_at(0)
		if (c >= 65 and c <= 90) or (c >= 97 and c <= 122): # A-Z or a-z
			return true
	
	return false # passed is_absolute_path() but didn't match the strict starts, false positive ie 'preload'
	
	# OLD VERSION
	#if string.length() < 2:
		#if string.is_empty():
			#return false
		#return string.is_absolute_path()
	#
	#if string[0] in _QUOTES or string[1] in _QUOTES:
		#return false
	#
	#return string.is_absolute_path()

static func get_line_declaration(stripped_line:String) -> StringName:
	for dec:StringName in Keywords.DECLARATIONS:
		if stripped_line.begins_with(dec):
			return dec
	return &""


static func get_func_name_in_line(stripped_line_text:String) -> String:
	if not (stripped_line_text.begins_with("func ") or stripped_line_text.begins_with("static func ")):
		return ""
	else:
		return stripped_line_text.get_slice("func ", 1).get_slice("(", 0).strip_edges()

static func get_class_name_in_line(stripped_line_text:String) -> String:
	if not stripped_line_text.begins_with("class "): # "" <- parser
		return ""
	var _class:String = stripped_line_text.get_slice("class ", 1).get_slice(":", 0) # "" <- parser
	if _class.find("extends ") > -1: #  "" <- parser
		_class = _class.get_slice("extends ", 0) #  "" <- parser
	return _class.strip_edges()



static func get_class_info(stripped_line: String) -> Variant:
	if not is_instance_valid(_class_regex):
		_class_regex = RegEx.new()
		#_class_regex.compile("^class\\s+([a-zA-Z_]\\w*)(?:\\s+extends\\s+([a-zA-Z0-9_.\'\":/]+))?")
		_class_regex.compile("^class\\s+([a-zA-Z_]\\w*)(?:\\s+extends\\s+((?:\"[^\"]+\"|'[^']+'|[a-zA-Z_]\\w*)(?:\\.[a-zA-Z_]\\w*)*))?")
	var _match:RegExMatch = _class_regex.search(stripped_line)
	if not _match:
		return null
		
	var _class_name:String = _match.get_string(1)
	var extends_name:String = _match.get_string(2) # Will be empty if no 'extends'
	return [_class_name, extends_name]


static func get_var_or_const_info(stripped_line:String, convert_preload:=true) -> Variant:
	if not is_instance_valid(_var_const_regex):
		_var_const_regex = RegEx.new()
		_var_const_regex.compile("^(?:static\\s+)?(?:var|const)\\s+([a-zA-Z_]\\w*)(?:\\s*:\\s*(?!=)([^=]+?))?(?:\\s*(?::?=)\\s*(.*))?$")
	if not is_instance_valid(_preload_regex):
		_preload_regex = RegEx.new()
		_preload_regex.compile("preload\\(\\s*[\"']([^\"']+)[\"']\\s*\\)(.*)")
	
	if stripped_line.ends_with(":"): # this would be for setter and getter
		stripped_line = stripped_line.trim_suffix(":")
	
	var _match:RegExMatch = _var_const_regex.search(stripped_line)
	if not _match:
		return null# [] # Not a valid var/const declaration
	
	var name:String = _match.get_string(1).strip_edges()
	var type_hint:String = _match.get_string(2).strip_edges()
	var assignment:String = _match.get_string(3).strip_edges()

	# --- HANDLE THE PRELOAD REQUEST ---
	var is_load:bool = false
	if assignment.begins_with("load") and convert_preload:
		is_load = true
		assignment = "pre" + assignment
	
	if assignment.begins_with("preload") and convert_preload:
		var p_match:RegExMatch = _preload_regex.search(assignment)
		if p_match:
			var path:String = p_match.get_string(1)
			if path.begins_with("uid:"):
				path = UFile.uid_to_path(path)
			var tail:String = p_match.get_string(2).strip_edges()
			# This turns preload("my_path").SomeClass -> "my_path.SomeClass"
			assignment = path + tail
		
		elif is_load:
			assignment = assignment.trim_prefix("pre")
	
	var implicit_type_hint:bool = type_hint.is_empty() and UString.rfind_index_safe(stripped_line, ":", _match.get_start(3)) > -1
	
	
	##TEST
	#if type_hint == "Signal":
		#type_hint = assignment
	##TEST
	
	return [name, type_hint, assignment, implicit_type_hint]

static func get_for_loop_info(stripped_line:String) -> Variant:
	if not is_instance_valid(_for_loop_regex):
		_for_loop_regex = RegEx.new()
		_for_loop_regex.compile(r"\bfor\s+([A-Za-z_][A-Za-z0-9_]*)(?:\s*:\s*([A-Za-z_][A-Za-z0-9_]*(\s*\.\s*[A-Za-z_][A-Za-z0-9_]*)*(?:\s*\[[^\]]+\])?))?\s+in\s+(.+)")
	
	var _match:RegExMatch = _for_loop_regex.search(stripped_line)
	if not _match:
		return null
	
	var nm:String = _match.get_string(1)
	var hint:String = _match.get_string(2)
	var collection:String = _match.get_string(4).strip_edges().trim_suffix(":")
	
	return [nm, hint, collection]

static func get_enum_info(stripped_line: String) -> Array:
	if not is_instance_valid(_enum_regex):
		_enum_regex = RegEx.new()
		_enum_regex.compile("^enum\\s+([a-zA-Z_]\\w*)?\\s*\\{([^}]*)\\}")
	r"^enum\s+([a-zA-Z_]\w*)?\s*\{([^}]*)\}"
	var _match:RegExMatch = _enum_regex.search(stripped_line)
	if not _match:
		return []

	var enum_name:String = _match.get_string(1).strip_edges() # Will be "" if unnamed enum
	var body_text:String = _match.get_string(2).strip_edges()

	var enum_data:Dictionary = {}
	var current_value:int = 0
	
	if not body_text.is_empty():
		# Split by comma (handles single-line and multi-line if they were combined)
		var members:PackedStringArray = body_text.split(",")
		
		for m:String in members:
			var clean_m:String = m.strip_edges()
			
			# Skip empty strings caused by trailing commas (e.g., {A, B,})
			if clean_m.is_empty():
				continue
				
			# Handle explicit assignments (e.g., ITEM = 5)
			if "=" in clean_m:
				var parts:PackedStringArray = clean_m.split("=")
				var m_name:String = parts[0].strip_edges()
				var m_val_str:String = parts[1].strip_edges()
				
				# If it's a standard number, update our current value counter
				if m_val_str.is_valid_int():
					current_value = m_val_str.to_int()
					enum_data[m_name] = current_value
				else:
					# Fallback for complex expressions (e.g. ITEM = 1 << 2)
					# Just store the string expression, but keep the counter moving
					enum_data[m_name] = m_val_str 
				
				current_value += 1
			else:
				# Standard auto-incrementing member
				enum_data[clean_m] = current_value
				current_value += 1
	
	return [enum_name, enum_data]

## Entries of a nameless enum as [name, line, column, assignment], shaped like tree-sitter's output:
## assignment is the explicit value text, else "0" for the first entry or "PREV + 1".
## `lines` start at the enum's `{` line, comments stripped, columns intact.
static func get_nameless_enum_entries(lines:PackedStringArray, first_line:int) -> Array:
	var entries:Array = []
	var previous:String = ""
	var started:bool = false
	var depth:int = 0
	var quote:String = ""
	var text:String = ""
	var pos:Vector2i = Vector2i(-1, -1) # (line offset, column) where the current entry starts
	for li:int in lines.size():
		var line_text:String = lines[li]
		if not text.is_empty():
			text += " "
		for i:int in line_text.length():
			var c:String = line_text[i]
			if not started:
				started = c == "{"
				continue
			if quote != "":
				text += c
				if c == quote and line_text[i - 1] != "\\":
					quote = ""
				continue
			if depth == 0 and (c == "," or c == "}"):
				previous = _add_enum_entry(entries, text, pos, first_line, previous)
				text = ""
				pos = Vector2i(-1, -1)
				if c == "}":
					return entries
				continue
			if c == '"' or c == "'":
				quote = c
			elif c == "(" or c == "[" or c == "{":
				depth += 1
			elif c == ")" or c == "]" or c == "}":
				depth -= 1
			if pos.x == -1 and c != " " and c != "\t":
				pos = Vector2i(li, i)
			text += c
	_add_enum_entry(entries, text, pos, first_line, previous) # unterminated (mid-edit)
	return entries

static func _add_enum_entry(entries:Array, text:String, pos:Vector2i, first_line:int, previous:String) -> String:
	text = text.strip_edges()
	if text.is_empty():
		return previous
	var entry_name:String = text
	var value:String = ""
	var eq:int = text.find("=")
	if eq != -1:
		entry_name = text.substr(0, eq).strip_edges()
		value = text.substr(eq + 1).strip_edges()
	if not entry_name.is_valid_ascii_identifier():
		return previous
	if value.is_empty():
		value = "0" if previous.is_empty() else previous + " + 1"
	entries.append([entry_name, first_line + pos.x, pos.y, value])
	return entry_name


static func get_func_info(stripped_text: String) -> Dictionary:
	_initialize_arg_regex()
	if not is_instance_valid(_func_regex):
		_func_regex = RegEx.new()
		_func_regex.compile("^(?:static\\s+)?func\\s+([a-zA-Z_]\\w*)\\s*\\((.*)\\)(?:\\s*->\\s*([^:]+))?")
	
	var func_data:Dictionary = { Keys.FUNC_ARGS: {}, "rest_arg": "" }
	
	var _match:RegExMatch = _func_regex.search(stripped_text)
	if not _match:
		return {} # Not a valid function signature
	
	var func_name:String = _match.get_string(1)
	var args_string:String = _match.get_string(2).strip_edges()
	var return_type:String = _match.get_string(3).strip_edges()
	
	func_data[Keys.FUNC_NAME] = func_name
	if not return_type.is_empty():
		func_data[Keys.FUNC_RETURN] = return_type
	
	if not args_string.is_empty():
		var split_args:Array[String] = safe_split_args(args_string, true)
		
		for arg_str:String in split_args:
			var rest:bool = arg_str.begins_with("...")
			arg_str = arg_str.trim_prefix("...").strip_edges() if rest else arg_str
			var arg_match:RegExMatch = _arg_regex.search(arg_str)
			if arg_match:
				var arg_name:String = arg_match.get_string(1).strip_edges()
				var type_hint:String = arg_match.get_string(2).strip_edges()
				if rest:
					func_data.rest_arg = arg_name
					if type_hint.is_empty():
						type_hint = "Array"
				var default_val:String = arg_match.get_string(3).strip_edges()
				
				var implicit_type_hint:bool = type_hint.is_empty() and UString.rfind_index_safe(arg_str, ":", _match.get_start(3)) > -1
				
				# If no type hint was provided, use the default value as the fallback
				#if type_hint.is_empty():
					#type_hint = default_val
				#func_data[Keys.FUNC_ARGS][arg_name] = type_hint
				
				func_data[Keys.FUNC_ARGS][arg_name] = [arg_name, type_hint, default_val, implicit_type_hint]

	return func_data


static func get_signal_info(stripped_text: String) -> Dictionary:
	_initialize_arg_regex()
	if not is_instance_valid(_signal_regex):
		_signal_regex = RegEx.new()
		_signal_regex.compile("^signal\\s+([a-zA-Z_]\\w*)(?:\\s*\\((.*)\\))?")
	
	
	var signal_data:Dictionary = { Keys.SIGNAL_ARGS: {} }
	
	var _match:RegExMatch = _signal_regex.search(stripped_text)
	if not _match:
		return {} # Not a valid signal declaration

	var signal_name:String = _match.get_string(1)
	signal_data[Keys.SIGNAL_NAME] = signal_name
	
	var args_string:String = _match.get_string(2).strip_edges()

	# --- HANDLE ARGUMENTS ---
	if not args_string.is_empty():
		var split_args:Array[String] = safe_split_args(args_string)
		for arg_str:String in split_args:
			var arg_match:RegExMatch = _arg_regex.search(arg_str)
			if arg_match:
				var arg_name:String = arg_match.get_string(1).strip_edges()
				var type_hint:String = arg_match.get_string(2).strip_edges()
				
				# We ignore Group 3 (default values) because signals can't have them
				signal_data[Keys.SIGNAL_ARGS][arg_name] = type_hint

	return signal_data


static func safe_split_args(args_str: String, preserve_rest:bool = false) -> Array[String]:
	var args: Array[String] = []
	var current_arg:String = ""
	var bracket_depth:int = 0
	var in_string:bool = false
	var string_char:String = ""

	for i:int in range(args_str.length()):
		var c:String = args_str[i]

		if in_string:
			current_arg += c
			# Safely exit string, ignoring escaped quotes like \"
			if c == string_char and args_str[i-1] != "\\":
				in_string = false
		else:
			if c == '"' or c == "'":
				in_string = true
				string_char = c
				current_arg += c
			elif c in ["(", "[", "{"]:
				bracket_depth += 1
				current_arg += c
			elif c in [")", "]", "}"]:
				bracket_depth -= 1
				current_arg += c
			elif c == "," and bracket_depth == 0:
				# a real comma, save the arg and reset.
				args.append(current_arg.strip_edges())
				current_arg = ""
			else:
				current_arg += c

	if not current_arg.strip_edges().is_empty():
		current_arg = current_arg.strip_edges()
		#TEST
		if not preserve_rest and current_arg.begins_with("..."):
			current_arg = current_arg.trim_prefix("...").strip_edges()
		#TEST
		args.append(current_arg)
	
	return args



static func _initialize_arg_regex() -> void:
	if not is_instance_valid(_arg_regex):
		_arg_regex = RegEx.new()
		_arg_regex.compile("^([a-zA-Z_]\\w*)(?:\\s*:\\s*(?!=)([^=]+?))?(?:\\s*(?::?=)\\s*(.*))?$")


class Keys:
	const FUNC_NAME = &"func_name"
	const FUNC_ARGS = &"func_args"
	const FUNC_RETURN = &"func_return"

	const SIGNAL_NAME = &"signal_name"
	const SIGNAL_ARGS = &"signal_args"

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
	
	const BITWISE_OPERATORS = ["<<", ">>", "~", "^", "|", "&"]
	const BOOL_OPERATORS = ["==", "!=", "<", "<=", ">", ">=", " and ", " not ", " or ", "&&", "!", "||"]
	const NON_BOOL_OPERATORS = ["+", "-", "*", "/", "%"]
