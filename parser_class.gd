#! import-p Keys,

const GDScriptParser = preload("res://addons/addon_lib/brohd/alib_runtime/utils/resource/gdscript/parser/gdscript_parser.gd")
const ParserFunc = GDScriptParser.ParserFunc
const Utils = GDScriptParser.Utils
const ParserRef = Utils.ParserRef
const Keys = Utils.Keys
const UClassDetail = GDScriptParser.UClassDetail

@warning_ignore_start("unused_private_class_variable")
var _parser:WeakRef
var _code_edit_parser:WeakRef
@warning_ignore_restore("unused_private_class_variable")


var _resolve_cache:={}

var main_script_path:String
var class_name_data:= {}

var access_path:String
var script_resource:GDScript
var script_base_type:String
var script_access_path:String

var line_indexes:PackedInt32Array
var indent_level:int

var inner_classes:= {}
var constants:= {}
var members:= {}
var functions:={}

var inherited_members := {}
var _inherited_script_mod_cache := {}

func queue_refresh(): # need to figure out a cache for this
	_check_inherited_valid() # if any of inherited have changed, clear inh members dict
	for f in functions.values():
		f.queue_refresh()

func set_script_resource(script:GDScript):
	script_resource = script
	if is_instance_valid(script):
		script_base_type = script_resource.get_instance_base_type()
	else:
		script_base_type = "RefCounted"
	

func get_script_resource():
	return script_resource

func get_script_class_path():
	return Utils.UString.dot_join(main_script_path, access_path)


func set_lines(new_lines:PackedInt32Array):
	line_indexes = new_lines

func set_members(members_dict:Dictionary):
	members = members_dict
	for m in members.keys():
		_create_function(m, members[m])

func _create_function(name, data:Dictionary):
	var member_type = data.get(Keys.MEMBER_TYPE)
	if member_type != Keys.MEMBER_TYPE_FUNC and member_type != Keys.MEMBER_TYPE_STATIC_FUNC:
		return
	var function = ParserFunc.new()
	function.name = name
	Utils.ParserRef.set_refs(function, ParserRef.get_parser(self), self)
	function.class_indent = indent_level
	function.member_data = data
	function.declaration_line = data.get(Keys.LINE_INDEX, -1)
	function.func_lines = data.get(Keys.FUNC_LINES)
	functions[name] = function


func set_constants(const_dict:Dictionary):
	constants = const_dict
	#print("CONSTANTS: ", constants.keys())

func set_inner_classes(class_dict:Dictionary):
	inner_classes = class_dict
	#print("INNER CLASSES: ", inner_classes.keys())


func has_script_member(identifier:String):
	if members.has(identifier):
		return true
	elif functions.has(identifier):
		return true
	elif constants.has(identifier):
		return true
	elif inner_classes.has(identifier):
		return true


func get_member(member_name:String):
	if functions.has(member_name):
		return functions[member_name]
	elif members.has(member_name):
		return members[member_name]
	elif constants.has(member_name):
		return constants[member_name]
	elif inner_classes.has(member_name):
		return inner_classes[member_name]

func has_inherited_member(identifier:String):
	return get_inherited_members().has(identifier)

func get_inherited_member(identifier:String):
	return get_inherited_members().get(identifier)

func has_function(func_name:String):
	return functions.has(func_name)

func get_function(func_name:String):
	if func_name == "new":
		func_name = "_init"
	return functions.get(func_name)

func get_function_start_line(func_name:String):
	var func_obj = functions.get(func_name) as ParserFunc
	if func_obj:
		return func_obj.declaration_line

func get_function_at_line(line:int) -> String: # this
	for f:ParserFunc in functions.values():
		if f.func_lines.has(line):
			return functions.find_key(f)
	return Keys.CLASS_BODY

func has_enum(enum_name:String):
	var var_data = constants.get(enum_name)
	if var_data == null:
		return false
	return var_data.get(Keys.MEMBER_TYPE) == Keys.MEMBER_TYPE_ENUM

func get_enum_members(enum_name:String):
	var enum_data = constants.get(enum_name)
	if enum_data == null:
		return
	var code_edit_parser = Utils.ParserRef.get_code_edit_parser(self)
	var enum_check = code_edit_parser.get_type_from_line(enum_data.get(Keys.LINE_INDEX), enum_data.get(Keys.COLUMN_INDEX, 0))
	var result = enum_check.get("result")
	if result == null:
		return
	return result[1] # this is the members as dict

func get_members(include_inherited:=false):
	var dict = {}
	if include_inherited:
		dict.merge(get_inherited_members())
	dict.merge(members.duplicate())
	dict.merge(constants.duplicate())
	dict.merge(inner_classes.duplicate())
	dict.merge(functions.duplicate())
	return dict



func has_constant_or_class(identifier:String):
	return constants.has(identifier) or inner_classes.has(identifier)

func get_constant_or_class(identifier:String):
	if constants.has(identifier):
		return constants[identifier]
	elif inner_classes.has(identifier):
		return inner_classes[identifier]

func has_preload(path:String): # doesnt handle inherited, should cache this somehow
	var t = ALibRuntime.Utils.UProfile.TimeFunction.new("GET PRELOAD")
	#var inherited = get_inherited_members()
	#for member_name in inherited.keys():
		#var val = inherited[member_name]
		#if val is GDScript: # could add a enum check for this?, possibly move to a GDScriptParser implementation too
			#if val.resource_path == path:
				#return member_name
	
	
	var parser = Utils.ParserRef.get_parser(self)
	var type_lookup = parser.get_type_lookup()
	for c in constants.keys():
		var declaration = type_lookup.get_class_obj_member_type(c, self, {})
		var cached = _resolve_cache.get_or_add(c, {})
		var type:String
		if declaration != cached.get(Keys.CLASS_CACHE_DEC, ""):
			type = parser.resolve_expression(c, line_indexes[0])
			cached[Keys.CLASS_CACHE_TYPE] = type
		else:
			type = cached.get(Keys.CLASS_CACHE_TYPE, "")
		
		cached[Keys.CLASS_CACHE_DEC] = declaration
		_resolve_cache[c] = cached
		if type == path:
			t.stop()
			return c
	
	
	var base_script = get_class_base_script()
	if base_script == null:
		return
	var script_path = base_script.resource_path
	if script_path != "":
		var script_parser = parser.get_parser_for_path(script_path) #^ this assumes root class, I think is only way that it could work?
		var class_obj = script_parser.get_class_object() as GDScriptParser.ParserClass #^ possibly could hybrid, if the script has no path use class detail
		var preload_name = class_obj.has_preload(path)
		if preload_name != null:
			t.stop()
			return preload_name
	t.stop()

## Get and cache the preloads of current scripts ancestors.
func get_inherited_members() -> Dictionary:
	var t = ALibRuntime.Utils.UProfile.TimeFunction.new("GET INH")
	if not inherited_members.is_empty():
		return inherited_members
	
	_get_inherited_members()
	inherited_members.merge(UClassDetail.class_get_all_members(script_resource))
	t.stop()
	var base_script = get_class_base_script()
	if base_script != null:
		pass
		#print("COMPARE INHERITEDS")
		#var test = UClassDetail.script_get_all_members(base_script, UClassDetail.IncludeInheritance.ALL)
		#var smaller_str = "inh"
		#var smaller = test
		#var bigger = inherited_members
		#if inherited_members.size() < test.size():
			#smaller_str = "test"
			#smaller = inherited_members
			#bigger = test
		#elif inherited_members.size() == test.size():
			#print("EQUAL SIZE")
		#
		#for k in bigger.keys():
			#if not smaller.has(k):
				#print(k, " not in ", smaller_str)
				#print(bigger[k])
	
	return inherited_members
	

func _get_inherited_members():
	inherited_members.clear()
	var parser = Utils.ParserRef.get_parser(self)
	var inherited_scripts = get_inherited_scripts()
	for script_path in inherited_scripts:
		var script_parser = parser.get_parser_for_path(script_path)
		var class_obj = script_parser.get_class_object()
		inherited_members.merge(class_obj.get_members())
	



func class_has_member(identifier:String):
	if ClassDB.class_has_enum(script_base_type, identifier):
		return true
	elif ClassDB.class_has_integer_constant(script_base_type, identifier):
		return true
	elif ClassDB.class_has_method(script_base_type, identifier):
		return true
	elif ClassDB.class_has_signal(script_base_type, identifier):
		return true
	#var prop_list = ClassDB.class_get_property_list(script_base_type)
	#print("CALLING CLASS HAS MEMBER")
	#for p:Dictionary in prop_list:
		#print(p.name)
		#if p.name == identifier:
			#return true
	return false

func get_class_base_script():
	if is_instance_valid(script_resource):
		return script_resource.get_base_script()

func get_inherited_scripts() -> Array:
	var base_script = get_class_base_script()
	if base_script == null:
		return []
	return UClassDetail.script_get_inherited_script_paths(base_script)

func _check_inherited_valid():
	if _inherited_script_mod_cache == null:
		_inherited_script_mod_cache = {}
	if is_instance_valid(script_resource):
		if script_base_type != script_resource.get_instance_base_type():
			inherited_members.clear()
	
	var inherited_scripts = get_inherited_scripts()
	for path in inherited_scripts:
		var mod_time = FileAccess.get_modified_time(path)
		var cached = _inherited_script_mod_cache.get(path, -1)
		if mod_time != cached:
			inherited_members.clear()
		_inherited_script_mod_cache[path] = mod_time
	
