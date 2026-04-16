
#! import-p Keys,

const UString = preload("res://addons/addon_lib/brohd/alib_runtime/utils/u_string.gd")
const UClassDetail = preload("res://addons/addon_lib/brohd/alib_editor/utils/src/u_class_detail.gd")
const UFile = preload("res://addons/addon_lib/brohd/alib_runtime/utils/u_file.gd")

const CacheHelper = preload("res://addons/addon_lib/brohd/alib_runtime/cache_helper/cache_helper.gd")

const GDScriptParser = preload("res://addons/addon_lib/brohd/alib_runtime/utils/gdscript/parser/gdscript_parser.gd")
const ParserClass = preload("res://addons/addon_lib/brohd/alib_runtime/utils/gdscript/parser/parser_class.gd")
const ParserFunc = preload("res://addons/addon_lib/brohd/alib_runtime/utils/gdscript/parser/parser_func.gd")
const CaretContext = preload("res://addons/addon_lib/brohd/alib_runtime/utils/gdscript/parser/caret_context.gd")
const CodeEditParser = preload("res://addons/addon_lib/brohd/alib_runtime/utils/gdscript/parser/utils/code_edit_parser.gd")
const TypeLookup = preload("res://addons/addon_lib/brohd/alib_runtime/utils/gdscript/parser/utils/type_lookup.gd")
const Access = preload("res://addons/addon_lib/brohd/alib_runtime/utils/gdscript/parser/utils/access.gd")
const BuiltInChecker = preload("res://addons/addon_lib/brohd/alib_runtime/utils/gdscript/parser/utils/builtin/builtin_checker.gd")

const InferenceContext = preload("res://addons/addon_lib/brohd/alib_runtime/utils/gdscript/parser/utils/type_lookup/inference_context.gd")

const Utils = preload("res://addons/addon_lib/brohd/alib_runtime/utils/gdscript/parser/utils/utils.gd")
const Keys = preload("res://addons/addon_lib/brohd/alib_runtime/utils/gdscript/parser/utils/keys.gd")


static var _static_parser_cache:= {}
var _parser_cache:= {}
var _get_cached_parser_callable:Callable
var _max_cache_size = 10

var code_edit_parser:CodeEditParser
var _caret_context:CaretContext
var _type_lookup:TypeLookup
var _access:Access

var code_edit:CodeEdit


var _script_path:String
var _script_resource:GDScript

var _class_access:Dictionary = {}

var active_parser:GDScriptParser


func _init() -> void:
	code_edit_parser = CodeEditParser.new()
	_type_lookup = TypeLookup.new()
	_access = Access.new()
	
	var ref_objs = [code_edit_parser, _type_lookup, _access]
	for object in ref_objs:
		Utils.ParserRef.set_refs(object, self)
	
	_parser_cache = _static_parser_cache

#region ParserCache
func set_parser_cache(cache_dict:Dictionary):
	_parser_cache = cache_dict

func set_parser_cache_size(size:int):
	_max_cache_size = size

func set_get_parser_callable(callable:Callable):
	_get_cached_parser_callable = callable

func clean_parser_cache():
	var active_parser_cache = _parser_cache.get_or_add(Keys.CACHE_ACTIVE_PARSERS, {})
	if _max_cache_size == -1 or active_parser_cache.size() <= _max_cache_size:
		return
	var inactive = _parser_cache.get_or_add(Keys.CACHE_INACTIVE_PARSERS, {})
	var paths = active_parser_cache.keys()
	var current_size = paths.size()
	var erased = 0
	for path in paths:
		var parser = active_parser_cache[path].get(Keys.CACHE_PARSER)
		if is_instance_valid(parser):
			clean_resolve_cache(parser._class_access)
		_deactivate_parser(active_parser_cache, inactive, path)
		erased += 1
		if current_size - erased <= _max_cache_size:
			break
	
	#print("CACHE SIZE::", current_size, " -> ", active_parser_cache.size())


func clean_resolve_cache(class_dict:Dictionary):
	for access_name:String in class_dict.keys():
		var class_obj = class_dict[access_name]
		for key in class_obj._resolve_cache.keys():
			if not class_obj.has_script_member(key):
				class_obj._resolve_cache.erase(key)


func deactivate_parser(path:String):
	var active_parser_cache = _parser_cache.get_or_add(Keys.CACHE_ACTIVE_PARSERS, {})
	var inactive = _parser_cache.get_or_add(Keys.CACHE_INACTIVE_PARSERS, {})
	if active_parser_cache.has(path):
		_deactivate_parser(active_parser_cache, inactive, path)

func _deactivate_parser(active_cache:Dictionary, inactive_cache:Dictionary, path:String):
	var data = active_cache[path]
	data.erase(Keys.CACHE_PARSER) # this should free the parser
	inactive_cache[path] = data
	active_cache.erase(path) # move from active to inactive, should they be removed from inactive below?


func clear_parser_cache():
	_parser_cache.clear()
	_static_parser_cache.clear()
#endregion

#region ParserSetup

func clear_current_class():
	_class_access.clear()
	code_edit_parser.string_map_cache.clear()

func set_current_script(script:GDScript):
	if script != _script_resource:
		clear_current_class()
	_script_resource = script
	if _script_resource == null:
		print("GDScriptParser.set_current_script - SCRIPT NULL")
		return
	_script_path = _script_resource.resource_path

func get_current_script():
	return _script_resource

func set_code_edit(new_code_edit:CodeEdit, free_existing:=false):
	if is_instance_valid(code_edit):
		if free_existing:
			_code_edit_dispose()
	code_edit = new_code_edit

## Set script path and load
func set_script_path(new_path:String):
	_script_path = new_path
	_script_resource = load(_script_path)
	set_source_code(_script_resource.source_code)

func get_script_path():
	return _script_path

func set_source_code(source:String): # need a version if the script editor is set externally, maybe just parse_source()
	_create_buffer_code_edit()
	code_edit.text = source

#endregion


func parse(force:=false):
	get_code_edit_parser().string_map_cache.clear() # clear this everytime so this doesn't get out of hand
	
	code_edit_parser.parse_text(force)
	
	#print_hierarchy()

func get_global_class_name():
	var root_class = get_class_object() as ParserClass
	return root_class.class_name_data.get(Keys.MEMBER_NAME, "")

func get_code_edit_parser():
	return code_edit_parser

func get_type_lookup():
	return _type_lookup

func get_access():
	return _access

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

func get_classes():
	return _class_access.keys()

func get_class_object(identifier:String=""):
	return _class_access.get(identifier)

func get_class_at_line(line:int):
	for access_path in _class_access.keys():
		var _class = _class_access[access_path] as ParserClass
		if line in _class.line_indexes:
			return access_path
	print("get_class_at_line - LINE NOT FOUND ", line)
	return ""

func get_function_at_line(line:int):
	var access_path = get_class_at_line(line)
	var class_obj = _class_access.get(access_path)
	if class_obj != null:
		return class_obj.get_function_at_line(line)
	return ""

func set_inference_context(inf:InferenceContext):
	get_type_lookup().set_inference_context(inf)

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
	var class_obj = get_class_object(_class)
	var member = class_obj.get_member(identifier)
	return member

func set_class_objs(classes_dict:Dictionary):
	for access_name in classes_dict.keys():
		_set_class_obj(access_name, classes_dict[access_name])

func _set_class_obj(access_name:String, class_obj:ParserClass):
	Utils.ParserRef.set_refs(class_obj, self)
	for f in class_obj.functions.values():
		Utils.ParserRef.set_refs(f, self, class_obj)
	_class_access[access_name] = class_obj

func get_member_info_from_script(full_script_path:String):
	var script_data = UString.get_script_path_and_suffix(full_script_path)
	var script_path = script_data[0]
	var parser = get_parser_for_path(script_path)
	var class_path = script_data[1]
	var access_path = ""
	var member_name = class_path
	if class_path.contains("."):
		access_path = UString.trim_member_access_back(class_path)
		member_name = UString.get_member_access_back(class_path)
	
	if member_name.ends_with(Keys.ENUM_PATH_SUFFIX):
		member_name = member_name.trim_suffix(Keys.ENUM_PATH_SUFFIX)
	
	var class_obj = parser.get_class_object(access_path) as ParserClass
	if is_instance_valid(class_obj):
		return class_obj.get_member_data(member_name)


func get_line_context(line:int, column:int=0, insert_caret:=false):
	return code_edit_parser.get_line_context(line, column, insert_caret).get(Keys.CONTEXT_TEXT)

func resolve_expression_in_script(expression:String, script_path:String, class_path:String):
	var target_parser = get_parser_and_class_obj(script_path, class_path)
	return target_parser.parser.resolve_expression(expression, target_parser.class_obj.line_indexes[0])

func resolve_to_access_object_in_script(expression:String, script_path:String, class_path:String):
	var target_parser = get_parser_and_class_obj(script_path, class_path)
	return target_parser.parser.resolve_to_access_object(expression, target_parser.class_obj.line_indexes[0])

func get_parser_for_path(full_script_path:String, force_cache:=false) -> GDScriptParser:
	var script_data = UString.get_script_path_and_suffix(full_script_path)
	if script_data.is_empty():
		return
	var script_path = script_data[0]
	if not Utils.is_gdscript_path(full_script_path):
		#print("NOT A GDSCRIPT FILE::", full_script_path)
		return
	
	if is_instance_valid(active_parser) and not force_cache:
		if script_path == active_parser.get_script_path():
			return active_parser
		
	if script_path == _script_path and not force_cache:
		return self
	if _get_cached_parser_callable.is_valid():
		return _get_cached_parser_callable.call()
	if _parser_cache == null:
		print("PARSER CACHE NULL::", _script_path)
		pass
	
	var active_parsers_cache = _parser_cache.get_or_add(Keys.CACHE_ACTIVE_PARSERS, {})
	var parser_data = get_cached_parser_data(script_path)
	
	var cached_modified_time = parser_data.get(Keys.CACHE_MODIFIED, -1)
	var modified_time = FileAccess.get_modified_time(script_path)
	var file_changed = cached_modified_time != modified_time or cached_modified_time == -1
	parser_data[Keys.CACHE_MODIFIED] = modified_time
	
	var parser_valid = false
	var parser = parser_data.get(Keys.CACHE_PARSER) as GDScriptParser
	if is_instance_valid(parser):
		parser_valid = true
		#print("EXISTING PARSER::", script_path)
		active_parsers_cache.erase(script_path)
	else:
		parser = new()
		parser.set_parser_cache(_parser_cache)
		parser_data[Keys.CACHE_PARSER] = parser
		if is_instance_valid(active_parser):
			parser.active_parser = active_parser
	
	
	if not parser_valid or file_changed:
		#print("NEED UPDATE::", script_path)
		var script:GDScript
		if script_path.begins_with("res://"):
			script = load(script_path)
		else: # some type of caching issue with out of fs scripts. Full reload to ensure changes are reflected
			script = ResourceLoader.load(script_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		parser.set_current_script(script)
		parser.set_source_code(script.source_code)
		
		var classes = parser_data.get(Keys.CACHE_CLASSES, {})
		if not classes.is_empty():
			for access_name in classes.keys():
				parser._set_class_obj(access_name, classes[access_name])
	
	var need_parse = not parser_valid or file_changed or force_cache
	parser.parse(need_parse) # i think this should be last so that classes can be updated
	
	var tl = get_type_lookup()
	var inf = tl.get_inference_context()
	if is_instance_valid(inf):
		parser.set_inference_context(inf)
	
	parser_data[Keys.CACHE_CLASSES] = parser._class_access
	active_parsers_cache[script_path] = parser_data
	_parser_cache[Keys.CACHE_ACTIVE_PARSERS] = active_parsers_cache
	return parser

func activate_parser(path:String, parser:GDScriptParser):
	var _cached_parser = get_parser_for_path(path, true)
	_parser_cache[Keys.CACHE_ACTIVE_PARSERS][path][Keys.CACHE_PARSER] = parser

func get_cached_parser_data(script_path:String):
	var active_parsers_cache = _parser_cache.get_or_add(Keys.CACHE_ACTIVE_PARSERS, {})
	var parser_data = active_parsers_cache.get(script_path)
	if parser_data == null:
		var inactive_parsers = _parser_cache.get_or_add(Keys.CACHE_INACTIVE_PARSERS, {})
		parser_data = inactive_parsers.get(script_path, {})
	return parser_data

func cached_data_valid(script_path:String, data:Dictionary):
	var cached_modified_time = data.get(Keys.CACHE_MODIFIED, -1)
	var modified_time = FileAccess.get_modified_time(script_path)
	var file_changed = cached_modified_time != modified_time or cached_modified_time == -1
	var classes = data.get(Keys.CACHE_CLASSES, {})
	if classes.is_empty() or file_changed:
		return false
	return true



func get_parser_and_class_obj_for_script(script_path:String):
	if not Utils.is_gdscript_path(script_path):
		return {}
	var script_data = UString.get_script_path_and_suffix(script_path)
	var script_main_path = script_data[0]
	var class_path = script_data[1]
	if script_main_path == _script_path:
		var class_obj = _class_access.get(class_path) as ParserClass
		return {Keys.GET_PARSER: self, Keys.GET_CLASS_OBJ:class_obj}
	else:
		var parser = get_parser_for_path(script_main_path)
		var class_obj = parser.get_class_object(class_path)
		return {Keys.GET_PARSER: parser, Keys.GET_CLASS_OBJ:class_obj}

func get_parser_and_class_obj(script_path:String, class_path:String):
	if script_path == _script_path:
		var class_obj = _class_access.get(class_path) as ParserClass
		return {Keys.GET_PARSER: self, Keys.GET_CLASS_OBJ:class_obj}
	else:
		var parser = get_parser_for_path(script_path)
		var class_obj = parser.get_class_object(class_path)
		return {Keys.GET_PARSER: parser, Keys.GET_CLASS_OBJ:class_obj}

func _create_buffer_code_edit():
	if not is_instance_valid(code_edit):
		var code = CodeEdit.new()
		code.add_comment_delimiter("#", "", true)
		code.add_comment_delimiter("##", "", true)
		code.add_string_delimiter('"""', '"""')
		code.add_string_delimiter("'''", "'''")
		code.set_meta(Keys.PARSER_CODE_EDIT, true)
		set_code_edit(code)

func script_inherits(to_check:String, inherit_script:String):
	if not Utils.is_gdscript_path(to_check):
		return false
	var parser = get_parser_and_class_obj_for_script(to_check)
	var class_obj = parser.class_obj as ParserClass
	return class_obj.inherits_script(inherit_script)

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
		print(base_indent_str + "Constants:")
		for c in _class.constants.keys():
			print(member_indent_str + c)
		print("")
		#
		#print(base_indent_str + "Members:")
		#for m in _class.members.keys():
			#print(member_indent_str + m)
		#print("")
		
		print(base_indent_str + "Functions:")
		for f in _class.functions.keys():
			print(member_indent_str + f)
		print("")
