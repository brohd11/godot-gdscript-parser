const UString = preload("res://addons/addon_lib/brohd/alib_runtime/utils/u_string.gd")

const GDScriptParser = preload("res://addons/addon_lib/brohd/alib_runtime/utils/resource/gdscript/parser/gdscript_parser.gd")
const Keys = preload("res://addons/addon_lib/brohd/alib_runtime/utils/resource/gdscript/parser/utils/keys.gd")
const CodeEditParser = preload("res://addons/addon_lib/brohd/alib_runtime/utils/resource/gdscript/parser/utils/code_edit_parser.gd")
const BuiltInChecker = preload("res://addons/addon_lib/brohd/alib_runtime/utils/resource/gdscript/parser/utils/builtin/builtin_checker.gd")
const AccessObject = GDScriptParser.TypeLookup.AccessObject

const UFile = GDScriptParser.UFile
const UClassDetail = GDScriptParser.UClassDetail





const ENUM_SUFFIX = Keys.ENUM_PATH_SUFFIX

static var _class_regex:RegEx
static var _var_const_regex:RegEx
static var _preload_regex:RegEx
static var _enum_regex:RegEx
static var _func_regex:RegEx
static var _arg_regex:RegEx
static var _signal_regex:RegEx
static var _string_path_regex:RegEx

static func is_gdscript_path(file_path:String):
	return file_path.ends_with(".gd") or file_path.contains(".gd.")

static func file_path_to_type(file_path:String):
	if is_gdscript_path(file_path):
		return file_path
	var ext = file_path.get_extension()
	var type = ""
	if not FileAccess.file_exists(file_path):
		return ""
	var resource = load(file_path) as Resource
	return resource.get_class()
	match ext:
		"tscn": type = &"PackedScene"
		"svg": type = &"Texture2D"
		"png": type = &"Texture2D"
		_: type = file_path
	
	return type

static func is_absolute_path(string:String):
	if string.begins_with("'") or string.begins_with('"'):
		return false
	return string.is_absolute_path()

static func member_is_const_class_enum(member_type:String):
	return member_type == Keys.MEMBER_TYPE_CLASS or member_type == Keys.MEMBER_TYPE_CONST or member_type == Keys.MEMBER_TYPE_ENUM


static func get_func_name_in_line(stripped_line_text:String) -> String:
	if not (stripped_line_text.begins_with("func ") or stripped_line_text.begins_with("static func ")):
		return ""
	var func_name = stripped_line_text.get_slice("func ", 1).get_slice("(", 0)
	return func_name.strip_edges()

static func get_class_name_in_line(stripped_line_text:String) -> String:
	if not stripped_line_text.begins_with("class "): # "" <- parser
		return ""
	var _class = stripped_line_text.get_slice("class ", 1).get_slice(":", 0) # "" <- parser
	if _class.find("extends ") > -1: #  "" <- parser
		_class = _class.get_slice("extends ", 0) #  "" <- parser
	return _class.strip_edges()



static func get_class_info(stripped_line: String):
	if not is_instance_valid(_class_regex):
		_class_regex = RegEx.new()
		#_class_regex.compile("^class\\s+([a-zA-Z_]\\w*)(?:\\s+extends\\s+([a-zA-Z0-9_.\'\":/]+))?")
		_class_regex.compile("^class\\s+([a-zA-Z_]\\w*)(?:\\s+extends\\s+((?:\"[^\"]+\"|'[^']+'|[a-zA-Z_]\\w*)(?:\\.[a-zA-Z_]\\w*)*))?")
	var _match = _class_regex.search(stripped_line)
	if not _match:
		return null
		
	var _class_name = _match.get_string(1)
	var extends_name = _match.get_string(2) # Will be empty if no 'extends'
	return [_class_name, extends_name]


static func get_var_or_const_info(stripped_line:String):# -> Array:
	if not is_instance_valid(_var_const_regex):
		_var_const_regex = RegEx.new()
		_var_const_regex.compile("^(?:static\\s+)?(?:var|const)\\s+([a-zA-Z_]\\w*)(?:\\s*:\\s*(?!=)([^=]+?))?(?:\\s*(?::?=)\\s*(.*))?$")
	if not is_instance_valid(_preload_regex):
		_preload_regex = RegEx.new()
		_preload_regex.compile("preload\\(\\s*[\"']([^\"']+)[\"']\\s*\\)(.*)")
	
	var _match = _var_const_regex.search(stripped_line)
	if not _match:
		return null# [] # Not a valid var/const declaration
	
	var name = _match.get_string(1).strip_edges()
	var type_hint = _match.get_string(2).strip_edges()
	var assignment = _match.get_string(3).strip_edges()

	# --- HANDLE THE PRELOAD REQUEST ---
	if assignment.begins_with("preload"):
		var p_match = _preload_regex.search(assignment)
		if p_match:
			var path = p_match.get_string(1)
			if path.begins_with("uid:"):
				path = UFile.uid_to_path(path)
			var tail = p_match.get_string(2).strip_edges()
			# This turns preload("my_path").SomeClass -> "my_path.SomeClass"
			assignment = path + tail 
			
	if type_hint == "":
		type_hint = assignment

	return [name, type_hint]


static func get_enum_info(stripped_line: String) -> Array:
	if not is_instance_valid(_enum_regex):
		_enum_regex = RegEx.new()
		_enum_regex.compile("^enum\\s+([a-zA-Z_]\\w*)?\\s*\\{([^}]*)\\}")
	r"^enum\s+([a-zA-Z_]\w*)?\s*\{([^}]*)\}"
	var _match = _enum_regex.search(stripped_line)
	if not _match:
		return []

	var enum_name = _match.get_string(1).strip_edges() # Will be "" if unnamed enum
	var body_text = _match.get_string(2).strip_edges()

	var enum_data = {}
	var current_value = 0
	
	if not body_text.is_empty():
		# Split by comma (handles single-line and multi-line if they were combined)
		var members = body_text.split(",")
		
		for m in members:
			var clean_m = m.strip_edges()
			
			# Skip empty strings caused by trailing commas (e.g., {A, B,})
			if clean_m.is_empty():
				continue
				
			# Handle explicit assignments (e.g., ITEM = 5)
			if "=" in clean_m:
				var parts = clean_m.split("=")
				var m_name = parts[0].strip_edges()
				var m_val_str = parts[1].strip_edges()
				
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


static func get_func_info(stripped_text: String) -> Dictionary:
	_initialize_arg_regex()
	if not is_instance_valid(_func_regex):
		_func_regex = RegEx.new()
		_func_regex.compile("^(?:static\\s+)?func\\s+([a-zA-Z_]\\w*)\\s*\\((.*)\\)(?:\\s*->\\s*([^:]+))?")
	
	var func_data = { Keys.FUNC_ARGS: {} }
	
	var _match = _func_regex.search(stripped_text)
	if not _match:
		return {} # Not a valid function signature
	
	var func_name = _match.get_string(1)
	var args_string = _match.get_string(2).strip_edges()
	var return_type = _match.get_string(3).strip_edges()
	
	func_data[Keys.FUNC_NAME] = func_name
	if not return_type.is_empty():
		func_data[Keys.FUNC_RETURN] = return_type
	
	if not args_string.is_empty():
		var split_args = safe_split_args(args_string)
		
		for arg_str in split_args:
			var arg_match = _arg_regex.search(arg_str)
			if arg_match:
				var arg_name = arg_match.get_string(1).strip_edges()
				var type_hint = arg_match.get_string(2).strip_edges()
				var default_val = arg_match.get_string(3).strip_edges()
				
				# If no type hint was provided, use the default value as the fallback
				# (Just like you did with your variable logic!)
				if type_hint.is_empty():
					type_hint = default_val
					
				func_data[Keys.FUNC_ARGS][arg_name] = type_hint

	return func_data


static func get_signal_info(stripped_text: String) -> Dictionary:
	_initialize_arg_regex()
	if not is_instance_valid(_signal_regex):
		_signal_regex = RegEx.new()
		_signal_regex.compile("^signal\\s+([a-zA-Z_]\\w*)(?:\\s*\\((.*)\\))?")
	
	
	var signal_data = { Keys.SIGNAL_ARGS: {} }
	
	var _match = _signal_regex.search(stripped_text)
	if not _match:
		return {} # Not a valid signal declaration

	var signal_name = _match.get_string(1)
	signal_data[Keys.SIGNAL_NAME] = signal_name
	
	var args_string = _match.get_string(2).strip_edges()

	# --- HANDLE ARGUMENTS ---
	if not args_string.is_empty():
		# Re-use our bulletproof splitter!
		var split_args = safe_split_args(args_string)
		
		for arg_str in split_args:
			# Re-use our function argument regex!
			var arg_match = _arg_regex.search(arg_str)
			if arg_match:
				var arg_name = arg_match.get_string(1).strip_edges()
				var type_hint = arg_match.get_string(2).strip_edges()
				
				# We ignore Group 3 (default values) because signals can't have them
				signal_data[Keys.SIGNAL_ARGS][arg_name] = type_hint

	return signal_data


static func safe_split_args(args_str: String) -> Array[String]:
	var args: Array[String] = []
	var current_arg := ""
	var bracket_depth := 0
	var in_string := false
	var string_char := ""

	for i in range(args_str.length()):
		var c = args_str[i]

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
				# We found a REAL comma! Save the arg and reset.
				args.append(current_arg.strip_edges())
				current_arg = ""
			else:
				current_arg += c

	if not current_arg.strip_edges().is_empty():
		args.append(current_arg.strip_edges())

	return args


static func line_has_any_declaration(stripped_line:String):
	for dec in Keywords.DECLARATIONS:
		if stripped_line.begins_with(dec):
			return true
	return false

static func add_var_to_dict(stripped_line:String, line:int, dict:Dictionary, int_key:=false):
	var var_data = get_var_or_const_info(stripped_line)
	if var_data != null:
		var var_name = var_data[0]
		var type = var_data[1]
		if type.find(".new(") > -1:
			type = type.get_slice(".new(", 0)
		var key = line if int_key else var_name
		dict[key] = {
			Keys.MEMBER_NAME: var_name,
			Keys.LINE_INDEX: line,
			Keys.MEMBER_TYPE: Keys.MEMBER_TYPE_VAR,
			Keys.TYPE: type,
			}
	return var_data


static func _initialize_arg_regex():
	if not is_instance_valid(_arg_regex):
		_arg_regex = RegEx.new()
		_arg_regex.compile("^([a-zA-Z_]\\w*)(?:\\s*:\\s*(?!=)([^=]+?))?(?:\\s*(?::?=)\\s*(.*))?$")

static func token_is_string(text:String):
	if text.begins_with('"') or text.begins_with("'"):
		return true
	return false

static func get_full_path_from_string(text:String):
	if not is_instance_valid(_string_path_regex):
		_string_path_regex = RegEx.new()
		_string_path_regex.compile("\\s*[\"\']([^\"\']+)[\"\']\\s*(.*)")
	
	if token_is_string(text):
		var p_match = _string_path_regex.search(text)
		if p_match:
			var path = p_match.get_string(1)
			var tail = p_match.get_string(2).strip_edges()
			# This turns "my_path".SomeClass -> "my_path.SomeClass"
			return path + tail
	return ""

static func ensure_absolute_path(path:String, main_script_path:String):
	if path.is_absolute_path():
		return path
	var new_path = main_script_path.get_base_dir().path_join(path).simplify_path()
	var script_data = UString.get_script_path_and_suffix(new_path)
	if FileAccess.file_exists(script_data[0]): # script path only
		return new_path
	return path

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
	
	const BOOL_OPERATORS = ["==", "!=", "<", "<=", ">", ">=", " and ", " not ", " or ", "&&", "!", "||"]
	const NON_BOOL_OPERATORS = ["+", "-", "*", "/", "%"]



class ParserRef:
	static func set_refs(object:Object, parser:GDScriptParser, class_obj:GDScriptParser.ParserClass=null):
		object.set(&"_parser", weakref(parser))
		object.set(&"_code_edit_parser", weakref(parser.code_edit_parser))
		if is_instance_valid(class_obj):
			object.set(&"_class_obj", weakref(class_obj))
	
	static func get_parser(object:Object) -> GDScriptParser:
		return _get_ref(object, &"_parser")
	
	static func get_code_edit_parser(object:Object) -> CodeEditParser:
		return _get_ref(object, &"_code_edit_parser")
	
	static func get_class_obj(object:Object) -> GDScriptParser.ParserClass:
		return _get_ref(object, &"_class_obj")
	
	static func _get_ref(object, string_name:StringName):
		var ref = object.get(string_name)
		if ref:
			return ref.get_ref()
		return



#! arg_location section:T
static func print_deb(section:String, ...msg:Array):
	if section in _PRINT:
		msg.push_front(section)
		ALibEditor.PrintDebug.print(msg)

const _PRINT = [
	T.ACCESS_PATH, 
	]


class T:
	const ACCESS_PATH = "ENUM ACCESS PATH"
