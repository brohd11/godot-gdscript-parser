
#! import_p Keys,

const PLUGIN_EXPORTED = false
const CACHE_TYPES = true

# Whole persistent-cache subsystem lives in ScriptCache. These are aliases for existing references;
# ScriptCache is the single source of truth for state/version/location + all cache logic.
const ScriptCache = preload("res://addons/addon_lib/brohd/alib_runtime/utils/gdscript/parser/utils/cache.gd")
const STATE_LIVE = ScriptCache.STATE_LIVE
const STATE_CACHED_RESOLVED = ScriptCache.STATE_CACHED_RESOLVED
const PARSE_CACHE_DIR = ScriptCache.DEFAULT_DIR

const TF = preload("uid://ft7o6vspsurv") #! resolve ALibRuntime.Utils.UProfile.TimeFunction

const UString = preload("res://addons/addon_lib/brohd/alib_runtime/utils/u_string.gd")
const UClassDetail = preload("res://addons/addon_lib/brohd/alib_editor/utils/src/u_class_detail.gd")
const UFile = preload("res://addons/addon_lib/brohd/alib_runtime/utils/u_file.gd")
const UResource = preload("uid://72uu8yngsoht") #! resolve ALibRuntime.Utils.UResource

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
var _max_cache_size:int = 10
var _parse_cache_dir:String = PARSE_CACHE_DIR

var state:int = STATE_LIVE

var code_edit_parser:CodeEditParser
# this set's children props, allows tests for non ts parsing
var use_tree_sitter:bool = ClassDB.class_exists("GDScriptTreeSitter")
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
	code_edit_parser.use_tree_sitter = use_tree_sitter
	_type_lookup = TypeLookup.new()
	_access = Access.new()
	
	var ref_objs:Array = [code_edit_parser, _type_lookup, _access]
	for object:Object in ref_objs:
		Utils.ParserRef.set_refs(object, self)
	
	_parser_cache = _static_parser_cache


func set_autoload_cache() -> void:
	_type_lookup.set_autoload_cache()

#region ParserCache
func set_parser_cache(cache_dict:Dictionary) -> void:
	_parser_cache = cache_dict

func set_parser_cache_size(size:int) -> void:
	_max_cache_size = size

func set_parse_cache_dir(dir:String) -> void:
	_parse_cache_dir = dir

func set_get_parser_callable(callable:Callable) -> void:
	_get_cached_parser_callable = callable

func clean_parser_cache() -> void:
	var active_parser_cache:Dictionary = _parser_cache.get_or_add(Keys.CACHE_ACTIVE_PARSERS, {})
	if _max_cache_size == -1 or active_parser_cache.size() <= _max_cache_size:
		return
	var inactive:Dictionary = _parser_cache.get_or_add(Keys.CACHE_INACTIVE_PARSERS, {})
	var paths:Array = active_parser_cache.keys()
	var current_size:int = paths.size()
	var erased:int = 0
	for path:String in paths:
		var parser:GDScriptParser = active_parser_cache[path].get(Keys.CACHE_PARSER)
		if is_instance_valid(parser):
			clean_resolve_cache(parser._class_access)
		_deactivate_parser(active_parser_cache, inactive, path)
		erased += 1
		if current_size - erased <= _max_cache_size:
			break
	
	#print("CACHE SIZE::", current_size, " -> ", active_parser_cache.size())


func clean_resolve_cache(class_dict:Dictionary) -> void:
	for access_name:String in class_dict.keys():
		var class_obj:ParserClass = class_dict[access_name]
		for key:String in class_obj._resolve_cache.keys():
			if not class_obj.has_script_member(key):
				class_obj._resolve_cache.erase(key)


func deactivate_parser(path:String) -> void:
	var active_parser_cache:Dictionary = _parser_cache.get_or_add(Keys.CACHE_ACTIVE_PARSERS, {})
	var inactive:Dictionary = _parser_cache.get_or_add(Keys.CACHE_INACTIVE_PARSERS, {})
	if active_parser_cache.has(path):
		_deactivate_parser(active_parser_cache, inactive, path)

func _deactivate_parser(active_cache:Dictionary, inactive_cache:Dictionary, path:String) -> void:
	var data:Dictionary = active_cache[path]
	var parser:GDScriptParser = data.get(Keys.CACHE_PARSER) as GDScriptParser
	# persist before freeing so resolve work survives eviction / restart. Skip a parser that is its
	# own active_parser (the live editor script) - its buffer may be dirty vs the on-disk mtime.
	if is_instance_valid(parser) and parser != parser.active_parser:
		parser.write_cache()
	data.erase(Keys.CACHE_PARSER) # this should free the parser
	inactive_cache[path] = data
	active_cache.erase(path) # move from active to inactive, should they be removed from inactive below?


func clear_parser_cache() -> void:
	_parser_cache.clear()
	_static_parser_cache.clear()

#region PersistentDiskCache
## Serialize this parser's parsed+resolved classes to disk. See ScriptCache.write.
func write_cache() -> bool:
	return ScriptCache.write(self)

## Rehydrate a headless CACHED_RESOLVED parser from disk, or null. See ScriptCache.read.
func read_cache(script_path:String) -> GDScriptParser:
	return ScriptCache.read(self, script_path)

## Cache-aware constructor: ready-to-use parser for `script_path`. Pass a CodeEdit for the current,
## editable script (LIVE, bound to it); omit it for read-only use (disk cache if valid, else LIVE
## from disk source). See ScriptCache.from_cache.
static func from_cache(script_path:String, cache_dir:String = "", code_edit = null) -> GDScriptParser:
	return ScriptCache.from_cache(script_path, cache_dir, code_edit)
#endregion
#endregion

#region ParserSetup

func clear_current_class() -> void:
	_class_access.clear()
	code_edit_parser.string_map_cache.clear()

func set_current_script(script:GDScript) -> void:
	if script != _script_resource:
		clear_current_class()
	_script_resource = script
	if _script_resource == null:
		print_deb_err(["GDScriptParser.set_current_script - SCRIPT NULL"])
		return
	_script_path = _script_resource.resource_path

func get_current_script() -> GDScript:
	# resolution reads get_current_script().resource_path (type_lookup); a rehydrated parser has no
	# _script_resource until first resolve need, so lazily load source (sets _script_resource too).
	if not is_instance_valid(_script_resource) and state == STATE_CACHED_RESOLVED:
		_ensure_source_loaded()
	return _script_resource

func set_code_edit(new_code_edit:CodeEdit, free_existing:=false) -> void:
	if is_instance_valid(code_edit):
		if free_existing:
			_code_edit_dispose()
	code_edit = new_code_edit

## Set script path and load
func set_script_path(new_path:String) -> void:
	_script_path = new_path
	if FileAccess.file_exists(_script_path):
		_script_resource = load(_script_path)
		set_source_code(_script_resource.source_code)
	else:
		set_source_code("")

func get_script_path() -> String:
	return _script_path

func set_source_code(source:String) -> void: # need a version if the script editor is set externally, maybe just parse_source()
	_create_buffer_code_edit()
	code_edit.text = source

## Force tree-sitter on/off (default: GDScriptTreeSitter registered). call before parse()
## for tests exercising both tree-sitter and plain-text parse paths.
func set_use_tree_sitter(value:bool) -> void:
	use_tree_sitter = value
	if is_instance_valid(code_edit_parser):
		code_edit_parser.use_tree_sitter = value

#endregion

func cache_valid() -> bool:
	if is_instance_valid(code_edit_parser.tree_sitter_manager):
		return code_edit_parser.tree_sitter_manager.cache_valid()
	return not code_edit_parser.cache_dirty

func parse(force:=false) -> void:
	get_code_edit_parser().string_map_cache.clear() # clear this everytime so this doesn't get out of hand
	
	code_edit_parser.parse_text(force)
	
	#print_hierarchy()

func get_global_class_name() -> String:
	var root_class:ParserClass = get_class_object() as ParserClass
	if is_instance_valid(root_class):
		return root_class.class_name_data.get(Keys.MEMBER_NAME, "")
	return ""

func get_code_edit_parser() -> CodeEditParser:
	_ensure_source_loaded()
	return code_edit_parser

func get_type_lookup() -> TypeLookup:
	return _type_lookup

func get_access() -> Access:
	return _access

func get_string_map(string:String) -> UString.StringMap:
	return code_edit_parser.get_string_map(string)

func get_caret_context(parse_context:=true) -> CaretContext:
	if not is_instance_valid(_caret_context):
		_caret_context = CaretContext.new(self, parse_context)
	return _caret_context

func reset_caret_context() -> void:
	_caret_context = null

func get_members_hash() -> int:
	var hashes:Array = []
	for access:String in _class_access.keys():
		var obj:ParserClass = _class_access.get(access)
		hashes.append(obj.get_members_hash())
	return hashes.hash()

func has_class(identifier:String) -> bool:
	return _class_access.has(identifier)

func get_classes() -> Array:
	return _class_access.keys()

func get_class_object(identifier:String="") -> Variant:
	return _class_access.get(identifier)

func get_class_at_line(line:int) -> String:
	for access_path:String in _class_access.keys():
		var _class:ParserClass = _class_access[access_path] as ParserClass
		if line in _class.line_indexes:
			return access_path
	#print("get_class_at_line - LINE NOT FOUND ", line)
	return ""

func get_function_at_line(line:int) -> String:
	var access_path:String = get_class_at_line(line)
	var class_obj:Variant = _class_access.get(access_path)
	if class_obj != null:
		return class_obj.get_function_at_line(line)
	return ""

func set_inference_context(inf:InferenceContext) -> void:
	get_type_lookup().set_inference_context(inf)

func get_function_data(identifier_name:String, line:int=-1) -> Dictionary:
	_ensure_source_if_cached()
	if line == -1:
		line = code_edit.get_caret_line()

	var result:Dictionary = _type_lookup.get_function_data_at_line(identifier_name, line)
	#print("GET FUNCTION DATA::", result)
	return result

func resolve_expression_to_type(identifier_name:String, line:int=-1) -> String:
	_ensure_source_if_cached()
	if line == -1:
		line = code_edit.get_caret_line()

	var result:String = _type_lookup.resolve_expression_to_type_at_line(identifier_name, line)
	#print("GET IDENTIFIER::TO TYPE::", result)
	#ALibRuntime.DebugPrint.print_deb(self, "GET ID TYPE", identifier_name, result)
	return result

#! keys i-TypeLookup.get_empty_type_rich;
func resolve_expression_to_type_rich(identifier_name:String, line:int=-1) -> Dictionary:
	_ensure_source_if_cached()
	if line == -1:
		line = code_edit.get_caret_line()

	var result:Dictionary = _type_lookup.resolve_expression_to_var_data_at_line(identifier_name, line)
	#print("GET IDENTIFIER::TO TYPE::", result)
	#ALibRuntime.DebugPrint.print_deb(self, "GET ID TYPE", identifier_name, result)
	return result

func resolve_to_access_object(identifier:String, line:int=-1) -> TypeLookup.AccessObject:
	_ensure_source_if_cached()
	if line == -1:
		line = code_edit.get_caret_line()
	return _type_lookup.resolve_expression_to_access_object_at_line(identifier, line)

func _get_class_obj(line:int=-1) -> ParserClass:
	if line == -1:
		line = code_edit.get_caret_line()
	return _class_access.get(get_class_at_line(line)) as ParserClass

func get_member_info(identifier:String, line:int=-1) -> Variant:
	if line == -1:
		line = code_edit.get_caret_line()
	var _class:String = get_class_at_line(line)
	if _class == null:
		return
	var class_obj:ParserClass = get_class_object(_class)
	var member:Variant = class_obj.get_member(identifier)
	return member

func set_class_objs(classes_dict:Dictionary) -> void:
	for access_name:String in classes_dict.keys():
		_set_class_obj(access_name, classes_dict[access_name])

func _set_class_obj(access_name:String, class_obj:ParserClass) -> void:
	Utils.ParserRef.set_refs(class_obj, self)
	for f:ParserFunc in class_obj.functions.values():
		Utils.ParserRef.set_refs(f, self, class_obj)
	_class_access[access_name] = class_obj

func get_member_info_from_script(full_script_path:String) -> Variant:
	var script_data:Array[String] = Utils.type_path_get_script_data(full_script_path)
	var script_path:String = script_data[0]
	var parser:GDScriptParser = get_parser_for_path(script_path)
	#if not parser:
		#return
	var class_path:String = script_data[1]
	var access_path:String = ""
	var member_name:String = class_path
	if class_path.contains("."):
		access_path = UString.trim_member_access_back(class_path)
		member_name = UString.get_member_access_back(class_path)
	
	if member_name.ends_with(Keys.ENUM_PATH_SUFFIX):
		member_name = member_name.trim_suffix(Keys.ENUM_PATH_SUFFIX)
	
	var class_obj:Variant = parser.get_class_object(access_path)
	if is_instance_valid(class_obj):
		return class_obj.get_member_data(member_name)
	return

## Takes a type path in this format: "res://my_class.gd.InnerClass::member##Type"
func get_member_data_from_origin(origin_type_path:String) -> Variant:
	if not Utils.is_absolute_path(origin_type_path):
		return
	
	var non_member_part:String = Utils.type_path_get_non_member(origin_type_path)
	var member:String = Utils.type_path_get_member(origin_type_path)
	var parser_data:Dictionary = get_parser_and_class_obj_for_script(non_member_part)
	if not parser_data:
		return
	var member_data:Dictionary = parser_data.class_obj.get_member_data(member)
	return member_data
	

func get_line_context(line:int, column:int=0, insert_caret:=false) -> String:
	return code_edit_parser.get_line_context(line, column, insert_caret).get(Keys.CONTEXT_TEXT, "")

func resolve_expression_in_script_full(expression:String, full_access_path:String) -> String:
	var script_data = Utils.type_path_get_script_data(full_access_path)
	return resolve_expression_in_script(expression, script_data[0], script_data[1])


func resolve_expression_in_script(expression:String, script_path:String, class_path:String) -> String:
	var target_parser:Dictionary = get_parser_and_class_obj(script_path, class_path)
	if not target_parser or not target_parser.class_obj:
		print_deb_err(["Could not get parser for path::resolve_expression_in_script::", script_path, "::", class_path])
		return ""
	return target_parser.parser.resolve_expression_to_type(expression, target_parser.class_obj.line_indexes[0])

func resolve_to_access_object_in_script_full(expression:String, full_access_path:String) -> Variant:
	var script_data = Utils.type_path_get_script_data(full_access_path)
	return resolve_to_access_object_in_script(expression, script_data[0], script_data[1])
	
func resolve_to_access_object_in_script(expression:String, script_path:String, class_path:String) -> Variant:
	var target_parser:Dictionary = get_parser_and_class_obj(script_path, class_path)
	if not target_parser or not target_parser.class_obj:
		print_deb_err(["Could not get parser for path::resolve_to_access_object_in_script::", script_path, "::", class_path])
		return
	return target_parser.parser.resolve_to_access_object(expression, target_parser.class_obj.line_indexes[0])

func get_parser_for_path(full_script_path:String, force_cache:=false) -> GDScriptParser:
	var script_data:Array[String] = Utils.type_path_get_script_data(full_script_path)
	if script_data.is_empty():
		return
	var script_path:String = script_data[0]
	if not Utils.is_gdscript_path(script_path):
		print_deb_err(["get_parser_for_path::NOT A GDSCRIPT FILE::", full_script_path])
		return
	if not FileAccess.file_exists(script_path):
		_parser_cache.get_or_add(Keys.CACHE_ACTIVE_PARSERS, {}).erase(script_path)
		return
	
	if is_instance_valid(active_parser) and not force_cache:
		if script_path == active_parser.get_script_path():
			return active_parser
		
	if script_path == _script_path and not force_cache:
		return self
	if _get_cached_parser_callable.is_valid():
		return _get_cached_parser_callable.call()
	if _parser_cache == null:
		# is this needed? doesn't really do anything, think it was from first impl
		print_deb_err(["get_parser_for_path::PARSER CACHE NULL::", _script_path])
	
	
	
	var active_parsers_cache:Dictionary = _parser_cache.get_or_add(Keys.CACHE_ACTIVE_PARSERS, {})
	var parser_data:Variant = get_cached_parser_data(script_path)
	
	var cached_modified_time:int = parser_data.get(Keys.CACHE_MODIFIED, -1)
	var modified_time:int = FileAccess.get_modified_time(script_path)
	var file_changed:bool = cached_modified_time != modified_time or cached_modified_time == -1
	parser_data[Keys.CACHE_MODIFIED] = modified_time
	
	var parser_valid:bool = false
	var parser:Variant = parser_data.get(Keys.CACHE_PARSER) as GDScriptParser
	if is_instance_valid(parser):
		if parser.state == STATE_CACHED_RESOLVED:
			# rehydrated-from-disk parser already in the active cache: serve from cache and never
			# fall through to parse() (it has no code_edit). Only rebuild if the file changed.
			if file_changed:
				parser._upgrade_to_live()
			_finalize_parser_data(parser, parser_data, active_parsers_cache, script_path)
			return parser
		parser_valid = true
		#print("EXISTING PARSER::", script_path)
		active_parsers_cache.erase(script_path)
	else:
		if not force_cache:
			parser = read_cache(script_path) # disk cache; null unless the on-disk mtime matches
		if is_instance_valid(parser):
			if is_instance_valid(active_parser):
				parser.active_parser = active_parser
			parser_data[Keys.CACHE_PARSER] = parser
			_finalize_parser_data(parser, parser_data, active_parsers_cache, script_path)
			return parser
		parser = new()
		parser.set_parser_cache(_parser_cache)
		parser.set_parse_cache_dir(_parse_cache_dir)
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
		if not is_instance_valid(script):
			return
		parser.set_current_script(script)
		parser.set_source_code(script.source_code)
		
		var classes:Dictionary = parser_data.get(Keys.CACHE_CLASSES, {})
		if not classes.is_empty():
			for access_name:String in classes.keys():
				parser._set_class_obj(access_name, classes[access_name])
	
	var need_parse:bool = not parser_valid or file_changed or force_cache
	parser.parse(need_parse) # i think this should be last so that classes can be updated
	_finalize_parser_data(parser, parser_data, active_parsers_cache, script_path)
	return parser

## Shared tail for get_parser_for_path: share the inference context and write the parser + its
## classes back into the active cache.
func _finalize_parser_data(parser:GDScriptParser, parser_data:Dictionary, active_parsers_cache:Dictionary, script_path:String) -> void:
	var inf:InferenceContext = get_type_lookup().get_inference_context()
	if is_instance_valid(inf):
		parser.set_inference_context(inf)
	parser_data[Keys.CACHE_CLASSES] = parser._class_access
	active_parsers_cache[script_path] = parser_data
	_parser_cache[Keys.CACHE_ACTIVE_PARSERS] = active_parsers_cache

# Source-lifecycle hooks -> ScriptCache (logic lives there; these keep call sites thin).
func _ensure_source_loaded() -> void:
	ScriptCache.ensure_source(self)

func _ensure_source_if_cached() -> void:
	ScriptCache.ensure_source_if_cached(self)

func _upgrade_to_live() -> void:
	ScriptCache.upgrade_to_live(self)


# Think this is not used, doesn't make a ton of sense either...
func activate_parser(path:String, parser:GDScriptParser) -> void:
	var _cached_parser:GDScriptParser = get_parser_for_path(path, true)
	_parser_cache[Keys.CACHE_ACTIVE_PARSERS][path][Keys.CACHE_PARSER] = parser

func get_cached_parser_data(script_path:String) -> Dictionary:
	var active_parsers_cache:Dictionary = _parser_cache.get_or_add(Keys.CACHE_ACTIVE_PARSERS, {})
	var parser_data:Variant = active_parsers_cache.get(script_path)
	if parser_data == null:
		var inactive_parsers:Dictionary = _parser_cache.get_or_add(Keys.CACHE_INACTIVE_PARSERS, {})
		parser_data = inactive_parsers.get(script_path, {})
	return parser_data

func cached_data_valid(script_path:String, data:Dictionary) -> bool:
	var cached_modified_time:int = data.get(Keys.CACHE_MODIFIED, -1)
	var modified_time:int = FileAccess.get_modified_time(script_path)
	var file_changed:bool = cached_modified_time != modified_time or cached_modified_time == -1
	var classes:Dictionary = data.get(Keys.CACHE_CLASSES, {})
	if classes.is_empty() or file_changed:
		return false
	return true



#! keys parser:GDScriptParser class_obj:ParserClass
func get_parser_and_class_obj_for_script(script_path:String) -> Dictionary:
	if not Utils.is_gdscript_path(script_path):
		return {}
	var script_data:Array[String] = Utils.type_path_get_script_data(script_path)
	var script_main_path:String = script_data[0]
	var class_path:String = script_data[1]
	var parser:GDScriptParser = self
	var class_obj:ParserClass
	if script_main_path == _script_path:
		class_obj = _class_access.get(class_path) as ParserClass
	else:
		parser = get_parser_for_path(script_main_path)
		if not parser:
			return {}
		class_obj = parser.get_class_object(class_path)
	
	return {Keys.GET_PARSER: parser, Keys.GET_CLASS_OBJ:class_obj}


func get_parser_and_class_obj(script_path:String, class_path:String) -> Variant:
	if script_path == _script_path:
		var class_obj:ParserClass = _class_access.get(class_path) as ParserClass
		return {Keys.GET_PARSER: self, Keys.GET_CLASS_OBJ:class_obj}
	else:
		var parser:GDScriptParser = get_parser_for_path(script_path)
		if not parser:
			if not PLUGIN_EXPORTED:
				printerr("Could not get parser for path::", script_path, "::", class_path)
			return
		var class_obj:ParserClass = parser.get_class_object(class_path)
		return {Keys.GET_PARSER: parser, Keys.GET_CLASS_OBJ:class_obj}

func _create_buffer_code_edit() -> void:
	if not is_instance_valid(code_edit):
		var code:CodeEdit = CodeEdit.new()
		code.add_comment_delimiter("#", "", true)
		code.add_comment_delimiter("##", "", true)
		code.add_string_delimiter('"""', '"""')
		code.add_string_delimiter("'''", "'''")
		code.set_meta(Keys.PARSER_CODE_EDIT, true)
		set_code_edit(code)

func script_inherits(to_check:String, inherit_script:String) -> bool:
	if not Utils.is_gdscript_path(to_check):
		return false
	var parser:Dictionary = get_parser_and_class_obj_for_script(to_check)
	var class_obj:ParserClass = parser.class_obj as ParserClass
	return class_obj.inherits_script(inherit_script)


func _code_edit_dispose() -> void:
	var meta:bool = code_edit.get_meta(Keys.PARSER_CODE_EDIT, false)
	if meta:
		code_edit.queue_free()

# this can't use above due to a lifecycle issue
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		#_code_edit_dispose()
		if is_instance_valid(code_edit):
			var meta:bool = code_edit.get_meta(Keys.PARSER_CODE_EDIT, false)
			if meta:
				code_edit.queue_free()


static func print_deb_err(args:Array) -> void:
	if not PLUGIN_EXPORTED:
		return
	printerr("::".join(args))
