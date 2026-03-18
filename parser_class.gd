
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

var dirty_flag:=true

var main_script_path:String

var access_path:String
var script_resource:GDScript
var script_base_type:String
var script_access_path:String

var source_code:String

var line_indexes:PackedInt32Array
var indent_level:int

var inherited_members = {}

var inner_classes:= {}
var constants:= {}
var members:= {}
var functions:={}

func queue_refresh():
	inherited_members.clear()
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
	var inherited = get_inherited_members()
	for member_name in inherited.keys():
		var val = inherited[member_name]
		if val is GDScript: # could add a enum check for this?, possibly move to a GDScriptParser implementation too
			if val.resource_path == path:
				return member_name
	
	
	var parser = Utils.ParserRef.get_parser(self)
	for c in constants.keys():
		var type = parser.resolve_expression(c, line_indexes[0])
		print(type)
		if type == path:
			t.stop()
			return c
	t.stop()

## Get and cache the preloads of current scripts ancestors.
func get_inherited_members() -> Dictionary:
	#var inherited_section = data_cache.get_or_add(_Keys.SCRIPT_INHERITED_MEMBERS, {})
	#var cached_data = CacheHelper.get_cached_data(script.resource_path, inherited_section)
	#if cached_data != null:
		#return cached_data
	if not is_instance_valid(script_resource):
		print("NOT VALID SCRIPT")
		return {}
	if not inherited_members.is_empty():
		return inherited_members
	var base_script = script_resource.get_base_script()
	if base_script == null:
		inherited_members = UClassDetail.class_get_all_members(script_resource)
	else:#^c I was not getting class data before, now I am... should I?? Either way, should cache.
		#var inherited_members = UClassDetail.script_get_all_members(base_script, UClassDetail.IncludeInheritance.SCRIPTS_ONLY)
		inherited_members = UClassDetail.script_get_all_members(base_script, UClassDetail.IncludeInheritance.ALL)
	#var inh_paths = UClassDetail.script_get_inherited_script_paths(base_script)
	#CacheHelper.store_data(script_resource.resource_path, inherited_members, inherited_section, inh_paths)
	return inherited_members

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
