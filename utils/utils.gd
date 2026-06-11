#! import_p Keys,
const SELF = preload("res://addons/addon_lib/brohd/alib_runtime/utils/gdscript/parser/utils/utils.gd")

const GDScriptParser = preload("uid://c4465kdwgj042") #! resolve ALibRuntime.Utils.UGDScript.Parser
const Keys = GDScriptParser.Keys
const CodeEditParser = GDScriptParser.CodeEditParser
const AccessObject = GDScriptParser.TypeLookup.AccessObject

const UFile = GDScriptParser.UFile
const UString = GDScriptParser.UString
const UClassDetail = GDScriptParser.UClassDetail

const ENUM_SUFFIX = Keys.ENUM_PATH_SUFFIX

const VALID_STATIC_MEMBER_TYPES = [Keys.MEMBER_TYPE_CLASS, Keys.MEMBER_TYPE_CONST, Keys.MEMBER_TYPE_ENUM, Keys.MEMBER_TYPE_STATIC_FUNC, Keys.MEMBER_TYPE_STATIC_VAR]

const _PACKED_SCENE_EXTS = ["tscn", "glb", "fbx", "gltf"]
const _TEXTURE_EXTS = ["svg", "png", "jpg", "jpeg", "exr", "dds"]

static var _string_path_regex:RegEx

static func is_gdscript_path(file_path:String) -> bool:
	return file_path.ends_with(".gd") or file_path.contains(".gd.") or file_path.contains(".gd::")


#^r maybe a better way to handle this, either using FileSystem or extension
static func file_path_to_type(file_path:String) -> String:
	if file_path.ends_with(Keys.INS_DELIM):
		return file_path
	if file_path.contains(Keys.TYPE_DELIM) or file_path.contains(Keys.MEMBER_DELIM):
		return file_path
	if is_gdscript_path(file_path):
		return file_path
	var ext:String = file_path.get_extension().to_lower()
	if not FileAccess.file_exists(file_path):
		return ""
	if ext in _PACKED_SCENE_EXTS:
		return &"PackedScene"
	elif ext in _TEXTURE_EXTS:
		return &"Texture2D"
	if FileAccess.file_exists(file_path):
		var resource:Resource = load(file_path)
		return resource.get_class()
	return ""

static func join_delim(part_1:String, part_2:String, delim:StringName) -> String:
	if part_1 != "" and part_2 != "":
		return part_1 + delim + part_2
	elif part_1 != "":
		return part_1
	elif part_2 != "":
		return part_2
	else:
		return ""

static func valid_instance_type(string:String) -> bool:
	if string.contains(Keys.TYPE_DELIM):
		string = type_path_get_type(string)
		if string.is_empty(): # if empty this means it is Signal, Callable, or Enum, not valid to store in a var anyway
			return false
	elif string.ends_with(Keys.INS_DELIM):
		string = string.trim_suffix(Keys.INS_DELIM)
	if string.begins_with("D"):
		if string.begins_with("Dictionary") and string.contains("["):
			return false
	elif string.begins_with("A"):
		if string.begins_with("Array") and string.contains("["):
			return false
	elif string.begins_with("p"):
		if string.begins_with("preload") and string.trim_prefix("preload").strip_edges().begins_with("("):
			return false
	
	if GDScriptParser.BuiltInChecker.is_variant_type(string):
		return false
	elif GDScriptParser.BuiltInChecker.is_builtin_class(string):
		return true
	elif is_absolute_path(string):
		return true
	elif string.contains("."):
		var front:String = UString.get_member_access_front(string)
		if ClassDB.class_exists(front):
			var back:String = UString.get_member_access_back(string)
			if ClassDB.class_has_enum(front, back):
				return false
		return true
		
	else:
		return true
	return false


static func type_path_add_ins(string:String) -> String:
	if not valid_instance_type(string):
		return string
	if not string.ends_with(Keys.INS_DELIM):
		string += Keys.INS_DELIM
	return string

#! keys class_path:String member_name:String line:int
static func type_path_get_local_var(string:String) -> Variant:
	string = string.get_slice(Keys.MEMBER_STACK_DELIM, 0)
	if not string.contains("local("):
		return
	var non_member_part:String = type_path_get_non_member(string)
	var member_data_str:String = string.get_slice("local(", 1).get_slice(")", 0)
	var member_name:String = member_data_str.get_slice("-", 0)
	var line_number:String = member_data_str.get_slice("-", 1)
	return {
		"class_path": non_member_part,
		"line": int(line_number),
		"member_name": member_name,
	}


static func get_or_add_current_type_path(current:String, class_object:GDScriptParser.ParserClass) -> String:
	if current != "":
		return current
	return class_object.get_script_class_path()



static func type_path_get_script_data(string:String) -> Array[String]:
	if string.contains(Keys.MEMBER_DELIM):
		string = string.get_slice(Keys.MEMBER_DELIM, 0)
	elif string.contains(Keys.TYPE_DELIM):
		string = string.get_slice(Keys.TYPE_DELIM, 0)
	elif string.contains(Keys.INS_DELIM):
		string = string.get_slice(Keys.INS_DELIM, 0)
	var script_data = UString.get_script_path_and_suffix(string)
	
	return script_data

static func type_path_get_non_member(string:String) -> String:
	if not string.contains(Keys.MEMBER_DELIM):
		return ""
	return string.get_slice(Keys.MEMBER_DELIM, 0)

static func type_path_get_member(string:String, include_type:=false) -> String:
	if not string.contains(Keys.MEMBER_DELIM):
		return ""
	if include_type or not string.contains(Keys.TYPE_DELIM):
		return string.get_slice(Keys.MEMBER_DELIM, 1) #.strip_edges()
	return string.get_slice(Keys.MEMBER_DELIM, 1).get_slice(Keys.TYPE_DELIM, 0)

static func type_path_add_member(string:String, member:String) -> String:
	if string.is_empty():
		return member
	return string + Keys.MEMBER_DELIM + member

static func type_path_get_type(string:String, allow_all:bool=false) -> String:
	if not string.contains(Keys.TYPE_DELIM):
		return ""
	var type = string.get_slice(Keys.TYPE_DELIM, 1).trim_suffix(Keys.INS_DELIM)
	if allow_all:
		return type
	if type == "Callable" or type == "Signal" or type == "Enum":
		return ""
	return type

static func type_path_add_type(string:String, type:String) -> String:
	return string + Keys.TYPE_DELIM + type
	
	

static func member_is_const_class_enum(member_type:String) -> bool:
	return member_type == Keys.MEMBER_TYPE_CLASS or member_type == Keys.MEMBER_TYPE_CONST or member_type == Keys.MEMBER_TYPE_ENUM

static func member_is_valid_static(member_type:String) -> bool:
	return member_type in VALID_STATIC_MEMBER_TYPES

static func is_absolute_path(string:String) -> bool:
	return UString.GDScriptParse.is_absolute_path(string)

static func get_func_name_in_line(stripped_line_text:String) -> String:
	return UString.GDScriptParse.get_func_name_in_line(stripped_line_text)

static func get_class_name_in_line(stripped_line_text:String) -> String:
	return UString.GDScriptParse.get_class_name_in_line(stripped_line_text)

static func get_class_info(stripped_line: String) -> Variant:
	return UString.GDScriptParse.get_class_info(stripped_line)

static func get_var_or_const_info(stripped_line:String) -> Variant:
	return UString.GDScriptParse.get_var_or_const_info(stripped_line)

static func get_for_loop_info(stripped_line:String) -> Variant:
	return UString.GDScriptParse.get_for_loop_info(stripped_line)

static func get_enum_info(stripped_line: String) -> Array:
	return UString.GDScriptParse.get_enum_info(stripped_line)

static func get_func_info(stripped_text: String) -> Dictionary:
	return UString.GDScriptParse.get_func_info(stripped_text)

static func get_signal_info(stripped_text: String) -> Dictionary:
	return UString.GDScriptParse.get_signal_info(stripped_text)

static func get_type_from_var_info(var_data:Array) -> String:
	#if var_data[2] == "":
		#return type_path_add_ins(var_data[1])
	#return var_data[2]
	var type:String = var_data[1]
	var assign:String = var_data[2]
	if type != "":
		if not GDScriptParser.BuiltInChecker.is_variant_type(type):
			type = type_path_add_ins(type)
		if assign != "":
			type = assign + Keys.MEMBER_ASSIGN_DELIM + type
	else:
		type = assign
	return type

static func get_type_from_for_info(var_data:Array) -> String:
	#if var_data[2] == "":
		#return type_path_add_ins(var_data[1])
	#return var_data[2]
	var type:String = var_data[1]
	var collection:String = var_data[2]
	if type == "":
		type = collection
	else:
		if not GDScriptParser.BuiltInChecker.is_variant_type(type):
			type = type_path_add_ins(type)
		type = collection + Keys.MEMBER_ASSIGN_DELIM + type
	return type


static func get_string_inside_brackets(string:String, must_be_string:=true) -> String:
	var open_b:int = string.find("(") + 1
	var bracket_string:String = string.substr(open_b, string.rfind(")") - open_b)
	if not must_be_string:
		return bracket_string
	if UString.is_string_or_string_name(bracket_string):
		return UString.unquote(bracket_string)
	return ""


static func line_has_any_declaration(stripped_line:String) -> bool:
	for dec:StringName in Keywords.DECLARATIONS:
		if stripped_line.begins_with(dec):
			return true
	return false

static func add_var_to_dict(stripped_line:String, line:int, dict:Dictionary, member_type:=Keys.MEMBER_TYPE_VAR, int_key:=false) -> Variant:
	var var_data:Variant = null
	if member_type == Keys.MEMBER_TYPE_VAR:
		var_data = get_var_or_const_info(stripped_line)
	elif member_type == Keys.MEMBER_TYPE_FOR:
		var_data = get_for_loop_info(stripped_line)
	else:
		print_deb(T.LOCAL_VAR, "UNHANDLED MEMBER TYPE::Utils.add_var_to_dict - ", stripped_line, "::", member_type)
		return []
	if var_data != null:
		var var_name:String = var_data[0]
		var type:String
		if member_type == Keys.MEMBER_TYPE_VAR:
			type = get_type_from_var_info(var_data)
		elif member_type == Keys.MEMBER_TYPE_FOR:
			type = get_type_from_for_info(var_data)
		
		var key:Variant = line if int_key else var_name
		#if dict.has(key):
			#print_deb(T.LOCAL_VAR, "LOCAL VARS HAS KEY ALREADY::", key, "::",var_name, "::",line)
		dict[key] = {
			Keys.MEMBER_NAME: var_name,
			Keys.LINE_INDEX: line,
			Keys.MEMBER_TYPE: member_type,
			Keys.TYPE: type,
			}
	return var_data

static func get_class_access_path_from_member_data(dict:Dictionary) -> String:
	return UString.dot_join(dict.get(Keys.SCRIPT_PATH, ""), dict.get(Keys.ACCESS_PATH, ""))

static func token_is_string(text:String) -> bool: # should this account for StringName and NodePath?
	if text.begins_with("r"):
		text = text.trim_prefix("r")
	if (text.begins_with('"') and text.ends_with('"')) or (text.begins_with("'") and text.ends_with("'")):
		return true
	return false

static func get_full_path_from_string(text:String) -> String:
	if not is_instance_valid(_string_path_regex):
		_string_path_regex = RegEx.new()
		_string_path_regex.compile("\\s*[\"\']([^\"\']+)[\"\']\\s*(.*)")
	
	if token_is_string(text):
		var p_match:RegExMatch = _string_path_regex.search(text)
		if p_match:
			var path:String = p_match.get_string(1)
			var tail:String = p_match.get_string(2).strip_edges()
			# This turns "my_path".SomeClass -> "my_path.SomeClass"
			return path + tail
	return ""

static func ensure_absolute_path(path:String, main_script_path:String) -> String:
	if path.is_absolute_path():
		return path
	var new_path:String = main_script_path.get_base_dir().path_join(path).simplify_path()
	var script_data:Array[String] = UString.get_script_path_and_suffix(new_path)
	if FileAccess.file_exists(script_data[0]): # script path only
		return new_path
	return path


static func run_expression(expression:String, script:GDScript) -> String:
	if not is_instance_valid(script):
		return ""
	var expr:Expression = Expression.new()
	var err:Error = expr.parse(expression)
	var result:Variant = null
	if err == OK: # first bool is to show errors, these should probably be turned off
		result = expr.execute([], script, true, true)
	if result == null:
		result = ""
	return str(result)

class Keywords: # this also exists in UString.GDScriptParse, move it?
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



class ParserRef:
	static func set_refs(object:Object, parser:GDScriptParser, class_obj:GDScriptParser.ParserClass=null) -> void:
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
	
	static func _get_ref(object:Object, string_name:StringName) -> Variant:
		var ref:Variant = object.get(string_name)
		if ref:
			return ref.get_ref()
		return




const PrintDebug = preload("uid://d1ki8cxxh7lvb") #! resolve ALibEditor.PrintDebug

#! arg_location section:T
static func print_deb(section:String, ...msg:Array):
	if section in _PRINT:
		msg.push_front(section)
		PrintDebug.print(msg)

const _PRINT = [
	T.ACCESS_PATH,
	T.LOCAL_VAR
	]


class T:
	const ACCESS_PATH = "ENUM ACCESS PATH"
	const LOCAL_VAR = "LOCAL_VAR"
