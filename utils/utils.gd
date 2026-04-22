

const GDScriptParser = preload("uid://c4465kdwgj042") #! resolve ALibRuntime.Utils.UGDScript.Parser
const Keys = GDScriptParser.Keys
const CodeEditParser = GDScriptParser.CodeEditParser
const AccessObject = GDScriptParser.TypeLookup.AccessObject

const UFile = GDScriptParser.UFile
const UString = GDScriptParser.UString
const UClassDetail = GDScriptParser.UClassDetail


const ENUM_SUFFIX = Keys.ENUM_PATH_SUFFIX

const _PACKED_SCENE_EXTS = ["tscn", "glb", "fbx", "gltf"]
const _TEXTURE_EXTS = ["svg", "png", "jpg", "jpeg", "exr", "dds"]

static var _string_path_regex:RegEx

static func is_gdscript_path(file_path:String):
	return file_path.ends_with(".gd") or file_path.contains(".gd.")


#^r maybe a better way to handle this, either using FileSystem or extension
static func file_path_to_type(file_path:String):
	if is_gdscript_path(file_path):
		return file_path
	var ext = file_path.get_extension().to_lower()
	if not FileAccess.file_exists(file_path):
		return ""
	if ext in _PACKED_SCENE_EXTS:
		return &"PackedScene"
	elif ext in _TEXTURE_EXTS:
		return &"Texture2D"
	var resource = load(file_path) as Resource
	return resource.get_class()



static func member_is_const_class_enum(member_type:String):
	return member_type == Keys.MEMBER_TYPE_CLASS or member_type == Keys.MEMBER_TYPE_CONST or member_type == Keys.MEMBER_TYPE_ENUM


static func is_absolute_path(string:String):
	return UString.GDScriptParse.is_absolute_path(string)

static func get_func_name_in_line(stripped_line_text:String) -> String:
	return UString.GDScriptParse.get_func_name_in_line(stripped_line_text)

static func get_class_name_in_line(stripped_line_text:String) -> String:
	return UString.GDScriptParse.get_class_name_in_line(stripped_line_text)

static func get_class_info(stripped_line: String):
	return UString.GDScriptParse.get_class_info(stripped_line)

static func get_var_or_const_info(stripped_line:String):# -> Array:
	return UString.GDScriptParse.get_var_or_const_info(stripped_line)

static func get_enum_info(stripped_line: String) -> Array:
	return UString.GDScriptParse.get_enum_info(stripped_line)

static func get_func_info(stripped_text: String) -> Dictionary:
	return UString.GDScriptParse.get_func_info(stripped_text)

static func get_signal_info(stripped_text: String) -> Dictionary:
	return UString.GDScriptParse.get_signal_info(stripped_text)



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



static func token_is_string(text:String): # should this account for StringName and NodePath?
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
