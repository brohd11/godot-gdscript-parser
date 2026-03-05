
#! import-p Keys,

const UString = preload("res://addons/addon_lib/brohd/alib_runtime/utils/u_string.gd")
const UClassDetail = preload("res://addons/addon_lib/brohd/alib_editor/utils/src/u_class_detail.gd")
const UFile = preload("res://addons/addon_lib/brohd/alib_runtime/utils/u_file.gd")
const CacheHelper = preload("res://addons/addon_lib/brohd/alib_runtime/cache_helper/cache_helper.gd")

const GDScriptParser = preload("res://addons/addon_lib/brohd/alib_runtime/utils/resource/gdscript/parser/gdscript_parser.gd")
const ParserClass = preload("res://addons/addon_lib/brohd/alib_runtime/utils/resource/gdscript/parser/parser_class.gd")
const ParserFunc = preload("res://addons/addon_lib/brohd/alib_runtime/utils/resource/gdscript/parser/parser_func.gd")
const CaretContext = preload("res://addons/addon_lib/brohd/alib_runtime/utils/resource/gdscript/parser/caret_context.gd")

const Utils = preload("res://addons/addon_lib/brohd/alib_runtime/utils/resource/gdscript/parser/utils/utils.gd")
const Keys = Utils.Keys

const Parse = Utils.Parse

var code_edit:CodeEdit

var _script_path:String
var _script_resource:GDScript

var _class_access:Dictionary = {}

var _caret_context:CaretContext

#var source_lines:PackedStringArray




func set_current_script(script:GDScript):
	_script_resource = script

func set_code_edit(new_code_edit:CodeEdit, free_existing:=false):
	if is_instance_valid(code_edit):
		if free_existing:
			_code_edit_dispose()
	code_edit = new_code_edit


func set_script_path(new_path:String):
	_script_path = new_path
	_script_resource = load(_script_path)
	set_source_code(_script_resource.source_code)

func set_source_code(source:String): # need a version if the script editor is set externally, maybe just parse_source()
	if not is_instance_valid(code_edit):
		var code = CodeEdit.new()
		code.set_meta(Keys.PARSER_CODE_EDIT, true)
		set_code_edit(code)
	
	code_edit.text = source
	#Parse.source(self)
	parse()

func parse():
	Parse.source(self)


func get_identifier_type(identifer_name:String) -> String:
	return ""

func get_caret_context(parse_context:=true) -> CaretContext:
	if not is_instance_valid(_caret_context):
		_caret_context = CaretContext.new(self, parse_context)
	return _caret_context

func reset_caret_context():
	_caret_context = null

func get_member_info(access_path:String):
	var member_name = access_path
	if access_path.contains("."):
		var string_map = UString.get_string_map(access_path, UString.StringMap.Mode.STRING)
		member_name = UString.get_member_access_back(access_path, string_map)
		access_path = UString.trim_member_access_back(access_path, string_map)
	else:
		access_path = ""
	
	var _class = _class_access.get(access_path) as ParserClass
	if _class == null:
		return
	var member = _class.get_member(member_name)
	return member

func get_class_at_line(line:int):
	for access_path in _class_access.keys():
		var _class = _class_access[access_path] as ParserClass
		if line in _class.line_indexes:
			return access_path
	print("LINE NOT FOUND ", line)
	return ""

func get_function_at_line(line:int):
	var access_path = get_class_at_line(line)
	var class_obj = _class_access[access_path] as ParserClass
	return class_obj.get_function_at_line(line)


func _code_edit_dispose():
	var meta = code_edit.get_meta(Keys.PARSER_CODE_EDIT, false)
	if meta:
		code_edit.queue_free()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_code_edit_dispose()







static func test():
	var old_gd = "res://addons/code_completions/src/class/gdscript_parser.gd"
	var this = "res://addons/addon_lib/brohd/alib_runtime/utils/resource/gdscript/parser/gdscript_parser.gd"
	var ins = new()
	var script = load(old_gd)
	ins.set_source_code(script.source_code)
	#ins.code_edit.queue_free()
	print(ins.get_member_info("EditorSet"))
	print(ins.get_class_at_line(1000))
