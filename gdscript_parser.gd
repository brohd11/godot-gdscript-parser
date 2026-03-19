#! import-p Keys,

const UString = preload("res://addons/addon_lib/brohd/alib_runtime/utils/u_string.gd")
const UClassDetail = preload("res://addons/addon_lib/brohd/alib_editor/utils/src/u_class_detail.gd")
const UFile = preload("res://addons/addon_lib/brohd/alib_runtime/utils/u_file.gd")
const CacheHelper = preload("res://addons/addon_lib/brohd/alib_runtime/cache_helper/cache_helper.gd")

const GDScriptParser = preload("res://addons/addon_lib/brohd/alib_runtime/utils/resource/gdscript/parser/gdscript_parser.gd")
const ParserClass = preload("res://addons/addon_lib/brohd/alib_runtime/utils/resource/gdscript/parser/parser_class.gd")
const ParserFunc = preload("res://addons/addon_lib/brohd/alib_runtime/utils/resource/gdscript/parser/parser_func.gd")
const CaretContext = preload("res://addons/addon_lib/brohd/alib_runtime/utils/resource/gdscript/parser/caret_context.gd")
const CodeEditParser = preload("res://addons/addon_lib/brohd/alib_runtime/utils/resource/gdscript/parser/utils/code_edit_parser.gd")
const TypeLookup = preload("res://addons/addon_lib/brohd/alib_runtime/utils/resource/gdscript/parser/utils/type_lookup.gd")

const Utils = preload("res://addons/addon_lib/brohd/alib_runtime/utils/resource/gdscript/parser/utils/utils.gd")
const Keys = Utils.Keys


var code_edit_parser:CodeEditParser
var _caret_context:CaretContext
var _type_lookup:TypeLookup

var code_edit:CodeEdit


var _script_path:String
var _script_resource:GDScript

var _class_access:Dictionary = {}


func _init() -> void:
	code_edit_parser = CodeEditParser.new()
	code_edit_parser._parser = weakref(self)
	
	_type_lookup = TypeLookup.new()
	_type_lookup._parser = weakref(self)


func set_current_script(script:GDScript):
	if script != _script_resource:
		clear_cache()
	_script_resource = script
	if _script_resource == null:
		print("SCRIPT NULL::")
	_script_path = _script_resource.resource_path

func get_current_script():
	return _script_resource

func set_code_edit(new_code_edit:CodeEdit, free_existing:=false):
	if is_instance_valid(code_edit):
		if free_existing:
			_code_edit_dispose()
	code_edit = new_code_edit


func set_script_path(new_path:String):
	_script_path = new_path
	_script_resource = load(_script_path)
	set_source_code(_script_resource.source_code)

func get_script_path():
	return _script_path


func set_source_code(source:String): # need a version if the script editor is set externally, maybe just parse_source()
	_create_buffer_code_edit()
	code_edit.text = source

func clear_cache():
	_class_access.clear()
	code_edit_parser.string_map_cache.clear()

func parse():
	code_edit_parser.parse_text()
	
	#print_hierarchy()





func get_code_edit_parser():
	return code_edit_parser

func get_type_lookup():
	return _type_lookup

func get_string_map(string:String):
	return code_edit_parser.get_string_map(string)

func get_caret_context(parse_context:=true) -> CaretContext:
	if not is_instance_valid(_caret_context):
		_caret_context = CaretContext.new(self, parse_context)
	return _caret_context

func reset_caret_context():
	_caret_context = null


func has_class(identifier:String):
	return _class_access.has(identifier)

func get_class_object(identifier:String):
	return _class_access.get(identifier)

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

func get_function_data(identifier_name:String, line:int=-1) -> Dictionary:
	if line == -1:
		line = code_edit.get_caret_line()
	
	var result = _type_lookup.get_function_data_at_line(identifier_name, line)
	#print("GET FUNCTION DATA::", result)
	return result

func resolve_expression(identifier_name:String, line:int=-1) -> String:
	if line == -1:
		line = code_edit.get_caret_line()
	
	var result = _type_lookup.resolve_expression_at_line(identifier_name, line)
	#print("GET IDENTIFIER::", result)
	return result

func get_identifier_type(identifier_name:String, line:int=-1) -> String:
	if line == -1:
		line = code_edit.get_caret_line()
	
	var result = _type_lookup.resolve_expression_at_line(identifier_name, line)
	#print("GET IDENTIFIER::", result)
	return result

func resolve_to_access_object(identifier:String, line:int=-1):
	if line == -1:
		line = code_edit.get_caret_line()
	return _type_lookup.resolve_expression_to_access_object_at_line(identifier, line)

func _get_class_obj(line:int=-1) -> ParserClass:
	if line == -1:
		line = code_edit.get_caret_line()
	return _class_access.get(get_class_at_line(line)) as ParserClass

func get_member_info(identifier:String, line:int=-1):
	if line == -1:
		line = code_edit.get_caret_line()
	var _class = get_class_at_line(line)
	if _class == null:
		return
	var member = _class.get_member(identifier)
	return member


func get_line_context(line:int, column:int=0, insert_caret:=false):
	return code_edit_parser.get_line_context(line, column, insert_caret).get(Keys.CONTEXT_TEXT)

func resolve_expression_in_script(expression:String, script_path:String, class_path:String):
	var target_parser = get_parser_and_class_obj(script_path, class_path)
	return target_parser.parser.resolve_expression(expression, target_parser.class_obj.line_indexes[0])

func resolve_to_access_object_in_script(expression:String, script_path:String, class_path:String):
	var target_parser = get_parser_and_class_obj(script_path, class_path)
	return target_parser.parser.resolve_to_access_object(expression, target_parser.class_obj.line_indexes[0])



func new_parser(script_path:String):
	var parser = new()
	var script = load(script_path)
	parser.set_current_script(script)
	parser.set_source_code(script.source_code)
	parser.parse()
	return parser

func get_parser_and_class_obj(script_path:String, class_path:String):
	if script_path == _script_path:
		var class_obj = _class_access.get(class_path) as ParserClass
		return {"parser": self, "class_obj":class_obj}
	else:
		var parser = new_parser(script_path)
		var class_obj = parser.get_class_object(class_path)
		return {"parser": parser, "class_obj":class_obj}

func _create_buffer_code_edit():
	if not is_instance_valid(code_edit):
		var code = CodeEdit.new()
		code.add_comment_delimiter("#", "", true)
		code.add_comment_delimiter("##", "", true)
		code.add_string_delimiter('"""', '"""')
		code.add_string_delimiter("'''", "'''")
		code.set_meta(Keys.PARSER_CODE_EDIT, true)
		set_code_edit(code)


func _code_edit_dispose():
	var meta = code_edit.get_meta(Keys.PARSER_CODE_EDIT, false)
	if meta:
		code_edit.queue_free()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		#_code_edit_dispose()
		var meta = code_edit.get_meta(Keys.PARSER_CODE_EDIT, false)
		if meta:
			code_edit.queue_free()


func print_hierarchy():
	for key in _class_access.keys():
		var name = key
		var indent = 0
		if name == "":
			name = "Script"
		else:
			indent = name.count(".") + 1
			name = UString.get_member_access_back(name)
		var base_indent_str = ""
		for i in indent:
			base_indent_str += "\t"
		print(base_indent_str + name)
		var member_indent_str = "\t" + base_indent_str
		
		var _class = _class_access.get(key) as ParserClass
		#print(base_indent_str + "Constants:")
		#for c in _class.constants.keys():
			#print(member_indent_str + c)
		#print("")
		#
		#print(base_indent_str + "Members:")
		#for m in _class.members.keys():
			#print(member_indent_str + m)
		#print("")
		
		print(base_indent_str + "Functions:")
		for f in _class.functions.keys():
			print(member_indent_str + f)
		print("")




static func test():
	var old_gd = "res://addons/code_completions/src/class/gdscript_parser.gd"
	var this = "res://addons/addon_lib/brohd/alib_runtime/utils/resource/gdscript/parser/gdscript_parser.gd"
	var ins = new()
	var script = load(old_gd)
	ins.set_source_code(script.source_code)
	#ins.code_edit.queue_free()
	print(ins.get_member_info("EditorSet"))
	print(ins.get_class_at_line(1000))
