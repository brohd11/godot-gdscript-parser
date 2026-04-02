#! import-p Keys,

const GDScriptParser = preload("res://addons/addon_lib/brohd/alib_runtime/utils/resource/gdscript/parser/gdscript_parser.gd")
const ParserFunc = GDScriptParser.ParserFunc
const Utils = GDScriptParser.Utils
const ParserRef = Utils.ParserRef
const Keys = Utils.Keys
const UString = GDScriptParser.UString
const UClassDetail = GDScriptParser.UClassDetail

@warning_ignore_start("unused_private_class_variable")
var _parser:WeakRef
var _code_edit_parser:WeakRef
@warning_ignore_restore("unused_private_class_variable")


var _resolve_cache:={}

var main_script_path:String
var class_name_data:= {}
var name

var access_path:String
var script_resource:GDScript
var script_base_type:String
var script_access_path:String

var extended:String = "RefCounted"

var declaration_line:int
var line_indexes:PackedInt32Array
var indent_level:int

var inner_classes:= {}
var constants:= {}
var members:= {}
var functions:={}

var inherited_members := {}
var inherited_scripts := []
var _inherited_script_mod_cache := {}

var base_type_members := {}

func queue_refresh(): # need to figure out a cache for this
	#print("REFRESH")
	_set_inherited_scripts()
	_check_inherited_valid() # if any of inherited have changed, clear inh members dict
	for f in functions.values():
		f.queue_refresh()

func set_extends(new_extends:String):
	if new_extends != extended:
		inherited_members.clear()
		inherited_scripts.clear()
	extended = new_extends

func set_script_resource(script:GDScript):
	script_resource = script
	if is_instance_valid(script):
		script_base_type = script_resource.get_instance_base_type()
	else:
		script_base_type = "RefCounted"
	#print("INNERSCRIPT BASE::", script_base_type)


func get_script_resource():
	return script_resource

func get_script_class_path():
	return Utils.UString.dot_join(main_script_path, access_path)

func get_name():
	return UString.get_member_access_back(access_path)

func set_lines(new_lines:PackedInt32Array):
	line_indexes = new_lines
	declaration_line = line_indexes[0]

func set_members(members_dict:Dictionary):
	members = members_dict
	
	for f in functions.keys():
		if not members.has(f): # delete deleted funcs, these are in a seperate dict so they must be manually cleaned
			functions.erase(f)
	
	for m in members.keys():
		_create_function(m, members[m])
	
	#_set_inherited_scripts()

func _create_function(_name, data:Dictionary):
	var member_type = data.get(Keys.MEMBER_TYPE)
	if member_type != Keys.MEMBER_TYPE_FUNC and member_type != Keys.MEMBER_TYPE_STATIC_FUNC:
		return
	var function = ParserFunc.new()
	function.name = _name
	Utils.ParserRef.set_refs(function, ParserRef.get_parser(self), self)
	function.class_indent = indent_level
	function.member_data = data
	function.declaration_line = data.get(Keys.LINE_INDEX, -1)
	function.func_lines = data.get(Keys.FUNC_LINES)
	functions[_name] = function


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

func get_member_data(member_name:String):
	if members.has(member_name):
		return members[member_name]
	elif constants.has(member_name):
		return constants[member_name]
	elif inner_classes.has(member_name):
		return inner_classes[member_name]

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
	if main_script_path == "user://test_inher.gd":
		print("INH MEMBERS::TEST INHER")
		print("INH MEMBERS::TEST INHER::MEMBER::", members)
		print("INH MEMBERS::TEST INHER::CONST::", constants)
		print("INH MEMBERS::TEST INHER::IC::", inner_classes)
		print("INH MEMBERS::TEST INHER::METHOD::", functions)
	
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

func get_member_type(identifier:String):
	var member_data = get_member(identifier)
	if member_data == null:
		return ""
	elif member_data is ParserFunc:
		return member_data.get_return_type(true)
	else:
		var parser = Utils.ParserRef.get_parser(self)
		var type_lookup = parser.get_type_lookup()
		var declaration = type_lookup.get_class_obj_member_type(identifier, self, {})
		var cached = _resolve_cache.get_or_add(identifier, {})
		var type:String
		if declaration != cached.get(Keys.CLASS_CACHE_DEC, ""):
			if member_data.get(Keys.MEMBER_TYPE) == Keys.MEMBER_TYPE_CLASS:
				type = parser.get_type_lookup().resolve_inner_class_at_line(identifier, declaration_line)
			else:
				type = parser.resolve_expression(identifier, declaration_line)
			cached[Keys.CLASS_CACHE_TYPE] = type
		else:
			type = cached.get(Keys.CLASS_CACHE_TYPE, "")
		
		cached[Keys.CLASS_CACHE_DEC] = declaration
		_resolve_cache[identifier] = cached
		return type
	return ""

func has_preload(path:String): # doesnt handle inherited, should cache this somehow
	var t = ALibRuntime.Utils.UProfile.TimeFunction.new("GET PRELOAD")
	
	var all_const = get_inherited_members().duplicate()
	all_const.merge(constants.duplicate())
	
	var parser = Utils.ParserRef.get_parser(self)
	for c in all_const.keys():
		var data = all_const.get(c)
		var member_type = data.get(Keys.MEMBER_TYPE)
		if not Utils.member_is_const_class_enum(member_type):
			continue
		var script_path = data.get(Keys.SCRIPT_PATH) #ALERT if script path is moved out of member data, will need to change this
		
		var script_parser = parser.get_parser_for_path(script_path)
		var class_object = script_parser.get_class_object(data.get(Keys.ACCESS_PATH, ""))
		var type = class_object.get_member_type(c) # this will cache it in the proper class
		if type == path:
			t.stop()
			return c


## Get and cache the preloads of current scripts ancestors.
func get_inherited_members(include_class:=true) -> Dictionary:
	var t = ALibRuntime.Utils.UProfile.TimeFunction.new("GET INH::" + get_name())
	if main_script_path == "user://test_inher.gd":
		print("INH MEMBERS::MEMBERS::",inherited_members)
	if not inherited_members.is_empty():
		return inherited_members
	
	_get_inherited_members()
	#if include_class:
		#base_type_members = UClassDetail.class_get_all_members(script_resource) # i think this can be removed now, it is handled in resolve separately
		#inherited_members.merge(UClassDetail.class_get_all_members(script_resource))
	
	#t.stop()
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
	var inherited_script_paths = get_inherited_scripts()
	for script_path in inherited_script_paths:
		var script_parser_data = parser.get_parser_and_class_obj_for_script(script_path)
		var class_obj = script_parser_data.get(Keys.GET_CLASS_OBJ)
		
		#var inh_members = class_obj.get_members()
		
		inherited_members.merge(class_obj.get_members())
	
	if access_path == "":
		return
	var outer = get_outer_script_constants()
	#print("OUTER ", outer)
	inherited_members.merge(outer)
	#return

func get_outer_script_constants():
	var valid = {}
	if access_path == "":
		return valid
	
	var parser = Utils.ParserRef.get_parser(self)
	var parent_access_path = ""
	if access_path.contains("."):
		parent_access_path = UString.trim_member_access_back(access_path)
	
	var parent_class_obj = parser.get_class_object(parent_access_path) as GDScriptParser.ParserClass
	var par_inh_members = parent_class_obj.get_inherited_members()
	
	for member_name in par_inh_members.keys():
		var member_data = par_inh_members[member_name]
		if member_data is not Dictionary:
			continue
		if Utils.member_is_const_class_enum(member_data.get(Keys.MEMBER_TYPE)):
			valid[member_name] = member_data.duplicate()
	
	var outer = parent_class_obj.get_outer_script_constants()
	
	valid.merge(outer)
	return valid



func get_gdscript_constants():
	var valid = []
	for c in constants.keys():
		if get_member_declaration(c) != Keys.MEMBER_TYPE_CONST:
			continue
		var type = get_member_type(c)
		#if type.begins_with("res://") and not type.ends_with(Keys.ENUM_PATH_SUFFIX):
		if Utils.is_absolute_path(type) and not type.ends_with(Keys.ENUM_PATH_SUFFIX):
			valid.append(c)
	for ic in inner_classes.keys():
		valid.append(ic)
	return valid


func get_member_declaration(member_name:String):
	var member_data = get_member(member_name)
	if member_data == null: return ""
	return member_data.get(Keys.MEMBER_TYPE)

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

func inherits_script(script_path:String):
	return script_path in get_inherited_scripts()

func get_inherited_scripts() -> Array:
	if not inherited_scripts.is_empty():
		return inherited_scripts
	return _set_inherited_scripts()

func _set_inherited_scripts():
	#print("RESOLVE CLASS ", get_name())
	#return []
	var base_script = get_class_base_script()
	if base_script == null:
		return []
	var last_path = get_script_class_path()
	var valid = []
	var inh_scripts = UClassDetail.script_get_inherited_scripts(base_script)
	for script:GDScript in inh_scripts:
		
		if script.resource_path == "":
			if not ClassDB.class_exists(last_path):
				var extended_resolved = _get_extended_type_of_class(last_path)
				#print("GET INH EXTENDED ", extended_resolved, "::LOOKING FOR::", last_path)
				#if extended_resolved.begins_with("res://"):
				if Utils.is_absolute_path(extended_resolved):
					valid.append(extended_resolved)
					last_path = extended_resolved
		else:
			last_path = script.resource_path
			valid.append(script.resource_path)
	
	#print("INH SCRIPTS ", valid)
	inherited_scripts = valid
	return valid
	

func _get_extended_type_of_class(script_path:String): # maybe this should be in the parser for ease
	var parser = Utils.ParserRef.get_parser(self)
	var script_parser_data = parser.get_parser_and_class_obj_for_script(script_path)
	#print("PARSER EQ::", parser == script_parser_data.parser, " extends ", extended, " ", script_path)
	
	var class_obj = script_parser_data.get("class_obj")
	return class_obj.get_extended_type()

func get_extended_type():
	var parser = Utils.ParserRef.get_parser(self)
	return parser.get_type_lookup().resolve_inner_class_at_line(extended, declaration_line)


func _check_inherited_valid():
	if _inherited_script_mod_cache == null:
		_inherited_script_mod_cache = {}
	if is_instance_valid(script_resource):
		if script_base_type != script_resource.get_instance_base_type():
			inherited_members.clear()
	
	#inherited_scripts.clear()
	
	#if inherited_scripts.is_empty():
		#return
		#inherited_scripts = get_inherited_scripts()
	
	#print("INH MEMBERS::SCRIPTS::",inherited_scripts)
	#if main_script_path == "user://test_inher.gd":
	#print("INH MEMBERS::MEMBERS::",inherited_members.keys())
	
	var valid_scripts = {}
	for path in inherited_scripts:
		var script_data = UString.get_script_path_and_suffix(path)
		var script_path = script_data[0]
		
		var mod_time = FileAccess.get_modified_time(script_path)
		var cached = _inherited_script_mod_cache.get(script_path, -1)
		#print("INH MEMBERS::CHECK PATH::", script_path, "::IS VALID::", mod_time == cached)
		if mod_time != cached:
			inherited_members.clear()
		#else:
			#print("VALID")
			
		valid_scripts[script_path] = mod_time
	
	#if main_script_path == "user://test_inher.gd":
	#print("INH MEMBERS::MEMBERS::",inherited_members.keys())
	
	#inherited_members.clear()
	
	_inherited_script_mod_cache = valid_scripts
