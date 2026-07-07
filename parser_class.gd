#! import_p Keys,

const PLUGIN_EXPORTED = false

const GDScriptParser = preload("uid://c4465kdwgj042") #! resolve ALibRuntime.Utils.UGDScript.Parser
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

var use_ts:bool = false

var _resolve_cache:={}

var main_script_path:String
var class_name_data:= {}
var name:String
var _members_hash:int=-1

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

var _check_inherited_debounce:=false
var inherited_members:Dictionary = {}
var inherited_scripts:= []
var _inherited_script_mod_cache:= {}

func queue_refresh(): # need to figure out a cache for this
	#print("REFRESH")
	_members_hash = -1
	_set_inherited_scripts()
	_check_inherited_valid() # if any of inherited have changed, clear inh members dict
	for f in functions.values():
		f.queue_refresh()
	
	_clean_resolve_cache()

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

func get_members_hash():
	if _members_hash is int and _members_hash != -1:
		return _members_hash
	
	var all_members := []
	for dict in [members, constants, inner_classes]:
		var names = dict.keys()
		names.sort()
		all_members.append_array(names)
	
	for f in functions.values():
		var args = f.get_arguments_raw()
		if not args.is_empty():
			all_members.append(args)
	
	_members_hash = all_members.hash()
	return _members_hash

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


func _create_function(_name, data:Dictionary):
	if use_ts:
		_create_function_ts(_name, data)
		return
	var member_type = data.get(Keys.MEMBER_TYPE)
	if member_type != Keys.MEMBER_TYPE_FUNC and member_type != Keys.MEMBER_TYPE_STATIC_FUNC:
		return
	var function:ParserFunc
	if functions.has(_name):
		function = functions[_name]
		function.queue_refresh()
	else:
		function = ParserFunc.new()
		function.name = _name
		Utils.ParserRef.set_refs(function, ParserRef.get_parser(self), self)
		functions[_name] = function
	function.class_indent = indent_level
	function.member_data = data
	function.declaration_line = data.get(Keys.LINE_INDEX, -1)
	function.func_lines = data.get(Keys.FUNC_LINES)

func _create_function_ts(_name, data:Dictionary):
	#print(data)
	var member_type = data.get(Keys.MEMBER_TYPE)
	if member_type != Keys.MEMBER_TYPE_FUNC and member_type != Keys.MEMBER_TYPE_STATIC_FUNC:
		return
	var function:ParserFunc
	if functions.has(_name):
		function = functions[_name]
		function.queue_refresh()
	else:
		function = ParserFunc.new()
		function.name = _name
		Utils.ParserRef.set_refs(function, ParserRef.get_parser(self), self)
		functions[_name] = function
	
	var start_line = data.get(Keys.LINE_INDEX)
	var end_line = data.get("end_line")
	function.declaration_line = start_line
	function.func_lines = range(start_line, end_line + 1)
	function.class_indent = indent_level
	function.member_data = data
	function._return_type_raw = data.get("return_type")
	
	
	var args = data.get("args")
	data.erase("args")
	function.arguments = args
	
	var locals = data.get("locals")
	data.erase("locals")
	function.local_vars = locals
	# setting mapped to true stops redundant reads, seems to work ok...
	function._local_vars_mapped = true
	

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
	return false

func get_member_data(member_name:String, include_inherited:=false):
	if members.has(member_name):
		return members[member_name]
	elif constants.has(member_name):
		return constants[member_name]
	elif inner_classes.has(member_name):
		return inner_classes[member_name]
	if not include_inherited:
		return
	var inh_members = get_inherited_members()
	if inh_members.has(member_name):
		return inh_members[member_name]

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

func has_script_signal(signal_name:String):
	var sig_data = members.get(signal_name)
	if sig_data == null:
		return false
	return sig_data.get(Keys.MEMBER_TYPE) == Keys.MEMBER_TYPE_SIGNAL

func get_script_signal_args(signal_name:String, infer_to_type:=false):
	var sig_data = members.get(signal_name)
	if sig_data == null:
		if infer_to_type:
			return ""
		return null
	if sig_data.get(Keys.MEMBER_TYPE) != Keys.MEMBER_TYPE_SIGNAL:
		if infer_to_type:
			return ""
		return null
	var code_edit_parser = Utils.ParserRef.get_code_edit_parser(self)
	var signal_check = code_edit_parser.get_type_from_line(sig_data.get(Keys.LINE_INDEX), sig_data.get(Keys.COLUMN_INDEX, 0))
	var result = signal_check.get("result")
	if result == null:
		if infer_to_type:
			return ""
		return null
	var args = result.get(Keys.SIGNAL_ARGS, {})
	for arg_name in args.keys():
		var type = args[arg_name]
		if type != "":
			args[arg_name] = Utils.type_path_add_ins(type)
		
	if not infer_to_type:
		return args # this is the args as dict
	if args.is_empty():
		return "void"
	elif args.size() > 1:
		return "Array"
	else:
		return args[args.keys()[0]]

func get_enum_members(enum_name:String):
	var enum_data = constants.get(enum_name)
	if enum_data == null:
		return
	var code_edit_parser:Utils.CodeEditParser = Utils.ParserRef.get_code_edit_parser(self)
	var enum_check = code_edit_parser.get_type_from_line(enum_data.get(Keys.LINE_INDEX), enum_data.get(Keys.COLUMN_INDEX, 0))
	var result = enum_check.get("result")
	if result == null:
		return
	return result[1] # this is the members as dict

func get_members() -> Dictionary:
	var dict = {}
	dict.merge(members.duplicate())
	dict.merge(constants.duplicate())
	dict.merge(inner_classes.duplicate())
	dict.merge(functions.duplicate()) # think this can be removed, this will not overwrite as is
	return dict # maybe get_member to only return data to align with name, or could have flag to check function object?



func has_constant_or_class(identifier:String):
	return constants.has(identifier) or inner_classes.has(identifier)

func get_constant_or_class(identifier:String):
	if constants.has(identifier):
		return constants[identifier]
	elif inner_classes.has(identifier):
		return inner_classes[identifier]

func get_member_type(identifier:String, include_inherited:=false) -> String:
	if has_script_member(identifier):
		var type_rich = get_member_type_rich(identifier)
		return type_rich.get("type", "")
	if not include_inherited:
		return ""
	if has_inherited_member(identifier):
		var member_data = get_inherited_member(identifier)
		var script_path = member_data.get(Keys.SCRIPT_PATH)
		script_path = UString.dot_join(script_path, member_data.get(Keys.ACCESS_PATH, &""))
		var parser = Utils.ParserRef.get_parser(self)
		var parser_data = parser.get_parser_and_class_obj_for_script(script_path)
		var next_class = parser_data.class_obj as GDScriptParser.ParserClass
		return next_class.get_member_type(identifier)
	return ""

func get_member_type_rich(identifier:String):
	var t = GDScriptParser.TF.new("GET MEMBER::" + identifier)
	var member_data = get_member(identifier)
	if member_data == null:
		return GDScriptParser.TypeLookup.get_empty_type_rich()
	
	var parser = Utils.ParserRef.get_parser(self)
	
	var cache_valid = cached_resolve_valid_for_member(identifier)
	var cached = _resolve_cache.get_or_add(identifier, {})
	var type_rich:Dictionary
	if not cache_valid:
		# resolve-cache miss on a rehydrated parser: lazily attach the source buffer so the live
		# resolve below can read declaration lines (keeps the cached class structure intact).
		if parser.state == GDScriptParser.STATE_CACHED_RESOLVED:
			parser._ensure_source_loaded()
		#var t = GDScriptParser.TF.new("GET TYPE")
		if member_data is ParserFunc:
			cached[Keys.CLASS_CACHE_DEC] = member_data.get_return_type_raw()
			
			type_rich = member_data.get_return_type_rich()
			cached["deps"] = GDScriptParser.InferenceContext.get_dependencies_from_member_stack(type_rich)
		elif member_data.get(Keys.MEMBER_TYPE) == Keys.MEMBER_TYPE_CLASS:
			cached[Keys.CLASS_CACHE_DEC] = parser.get_type_lookup().get_class_obj_member_type(identifier, self, {})
			
			var class_type = parser.get_type_lookup().resolve_inner_class_at_line(identifier, declaration_line)
			type_rich = GDScriptParser.TypeLookup.get_empty_type_rich()
			type_rich.origin = class_type
			type_rich.type = class_type # should this be different?
			
		else:
			cached[Keys.CLASS_CACHE_DEC] = parser.get_type_lookup().get_class_obj_member_type(identifier, self, {})
			
			type_rich = parser.resolve_expression_to_type_rich(identifier, declaration_line)
			cached["deps"] = GDScriptParser.InferenceContext.get_dependencies_from_member_stack(type_rich)
			# ALERT unsure about this. Do I want the type to evaluate to the explicit type or the origin
			# i think this way, it ensures the most recent explicit type or inference, then you can get origin if needed
			# this will set the find_origin to false, then back to it's original setting
			#type = parser.get_type_lookup().resolve_expression_to_type_at_line(identifier, declaration_line)
		cached[Keys.CLASS_CACHE_TYPE] = type_rich
		#t.stop()
	else:
		type_rich = cached.get(Keys.CLASS_CACHE_TYPE, &"")
	
	
	_resolve_cache[identifier] = cached
	#t.stop("GET MEMBER::WAS_VALID::" + str(cache_valid) + "::" + identifier + " -> " + type)
	return type_rich

func cached_resolve_valid_for_member(identifier:String):
	if not GDScriptParser.CACHE_TYPES:
		return false

	var member_data = get_member(identifier)
	if member_data == null:
		return false
	
	var parser = Utils.ParserRef.get_parser(self)

	# CACHED_RESOLVED parser has no live source: validity is deps-only (see ScriptCache).
	if parser.state == GDScriptParser.STATE_CACHED_RESOLVED:
		return GDScriptParser.ScriptCache.cached_resolve_valid(self, identifier)

	var is_func = member_data is ParserFunc
	var declaration:String
	if is_func:
		declaration = member_data.get_return_type_raw()
	else:
		declaration = parser.get_type_lookup().get_class_obj_member_type(identifier, self, {})
	
	var cached = _resolve_cache.get_or_add(identifier, {})
	if not cached.has("deps"):
		return false
	var cached_deps = cached.get("deps", {})
	if cached_deps == null:
		cached_deps = {}
	
	if not GDScriptParser.InferenceContext.validate_dependencies(cached_deps, main_script_path):
		return false
	
	# this seems to be working now that this can use the member stack to determine deps
	# everything seems to be updating properly so far...
	var cached_type = cached.get(Keys.CLASS_CACHE_TYPE, {})
	var cache_valid = cached.get(Keys.CLASS_CACHE_DEC, "") == declaration and cached_type.get("type") != &""
	
	return cache_valid

func get_cached_resolve_for_member(identifier:String):
	return _resolve_cache.get(identifier, {}).get(Keys.CLASS_CACHE_TYPE, &"")

func is_member_static_typed(identifier:String):
	var member_data = get_member(identifier)
	if member_data == null:
		return false
	
	if member_data is ParserFunc:
		return member_data.has_static_return()
	
	var member_type = member_data.get(Keys.MEMBER_TYPE)
	if Utils.member_is_const_class_enum(member_type) or member_type == Keys.MEMBER_TYPE_SIGNAL:
		return true # these don't really need anything, maybe signal?
	
	var code_edit_parser = Utils.ParserRef.get_code_edit_parser(self)
	
	var line_index = member_data.get(Keys.LINE_INDEX)
	var column = member_data.get(Keys.COLUMN_INDEX, 0)
	var type_data = code_edit_parser.get_type_from_line(line_index, column)
	var result = type_data.get("result")
	if result == null:
		return false
	
	if result is Array and result.size() == 4:
		return result[1] != "" or result[3]
	else:
		GDScriptParser.print_deb_err(["NOT AN ARRAY IN MEMBER STATIC TYPED", result])
		return false
	return true

func has_preload(path:String) -> Variant: # doesnt handle inherited, should cache this somehow
	var all_const = get_inherited_members().duplicate()
	all_const.merge(constants.duplicate())
	#print("TO FIND::", path)
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
		#print("PRELOAD TYPE::", type)
		if type == path:
			return c
	
	var inherited_script_paths = get_inherited_scripts()
	for script_path in inherited_script_paths:
		var script_parser_data = parser.get_parser_and_class_obj_for_script(script_path)
		var class_obj = script_parser_data.get(Keys.GET_CLASS_OBJ)
		var check = class_obj.has_preload(path)
		if check:
			return check
	
	return


## Get and cache the preloads of current scripts ancestors.
func get_inherited_members() -> Dictionary:
	_check_inherited_valid()
	
	if not inherited_members.is_empty():
		return inherited_members
	#var t = GDScriptParser.TF.new("INHCHJECK::" + get_name())
	_get_inherited_members()
	
	#t.stop()
	
	#^ debug print, compare UClassDetail to new parser
	#var base_script = get_class_base_script()
	#if base_script != null:
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
	

func _get_inherited_members() -> void:
	inherited_members.clear()
	var parser = Utils.ParserRef.get_parser(self)
	var inherited_script_paths = get_inherited_scripts()
	for script_path in inherited_script_paths:
		var script_parser_data = parser.get_parser_and_class_obj_for_script(script_path)
		var class_obj = script_parser_data.get(Keys.GET_CLASS_OBJ)
		inherited_members.merge(class_obj.get_members())
	
	if access_path == "":
		return
	var outer = get_outer_script_constants()
	inherited_members.merge(outer)

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


func get_gdscript_constants(as_dict:=false):
	var valid = {}
	for c in constants.keys():
		var member_data = constants[c] as Dictionary
		if member_data[Keys.MEMBER_TYPE] == Keys.MEMBER_TYPE_ENUM:
			var path = Utils.get_class_access_path_from_member_data(member_data)
			path = Utils.type_path_add_member(path, c) + Keys.ENUM_PATH_SUFFIX
			valid[c] = path
			continue
		elif member_data[Keys.MEMBER_TYPE] != Keys.MEMBER_TYPE_CONST:
			continue
		var type = get_member_type(c)
		if Utils.is_absolute_path(type) and (not type.contains(Keys.MEMBER_DELIM) or Utils.type_path_get_type(type, true) == "Enum"):
			valid[c] = type
		
	for ic in inner_classes.keys():
		var member_data = inner_classes[ic] as Dictionary
		valid[ic] = member_data.get(Keys.TYPE)
	
	var main_parser = Utils.ParserRef.get_parser(self)
	var inher = get_inherited_members()
	for member in inher.keys():
		var member_data = inher[member]
		if member_data[Keys.MEMBER_TYPE] == Keys.MEMBER_TYPE_CONST:
			var inh_script_path = member_data[Keys.SCRIPT_PATH]
			var target_class_obj = self
			if inh_script_path != main_script_path:
				var full_script_path = UString.dot_join(inh_script_path, member_data[Keys.ACCESS_PATH])
				var inh_parser = main_parser.get_parser_and_class_obj_for_script(full_script_path)
				target_class_obj = inh_parser.class_obj
			var type = target_class_obj.get_member_type(member)
			if Utils.is_absolute_path(type) and (not type.contains(Keys.MEMBER_DELIM) or Utils.type_path_get_type(type, true) == "Enum"):
				valid[member] = type
		elif member_data[Keys.MEMBER_TYPE] == Keys.MEMBER_TYPE_CLASS:
			valid[member] = member_data.get(Keys.TYPE)
		elif member_data[Keys.MEMBER_TYPE] == Keys.MEMBER_TYPE_ENUM:
			var path = Utils.get_class_access_path_from_member_data(member_data)
			path = Utils.type_path_add_member(path, member) + Keys.ENUM_PATH_SUFFIX
			valid[member] = path
	
	if as_dict:
		return valid
	return valid.keys()


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

func get_class_member_type(identifier:String, resolve_const:=false):
	return GDScriptParser.TypeLookup.get_class_member_type(script_base_type, identifier)


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
				if Utils.is_absolute_path(extended_resolved):
					valid.append(StringName(extended_resolved))
					last_path = extended_resolved
		else:
			last_path = script.resource_path
			valid.append(StringName(script.resource_path))
	
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
	if _check_inherited_debounce:
		return
	_check_inherited_debounce = true
	if _inherited_script_mod_cache == null:
		_inherited_script_mod_cache = {}
	if is_instance_valid(script_resource):
		if script_base_type != script_resource.get_instance_base_type():
			inherited_members.clear()
	
	var valid_scripts = {}
	for path in inherited_scripts:
		var script_data = UString.get_script_path_and_suffix(path)
		var script_path = script_data[0]
		
		var mod_time = FileAccess.get_modified_time(script_path)
		var cached = _inherited_script_mod_cache.get(script_path, -1)
		if mod_time != cached:
			inherited_members.clear()
		
		valid_scripts[script_path] = mod_time
	
	_inherited_script_mod_cache = valid_scripts
	#await Engine.get_main_loop().root.get_tree().process_frame
	var def = func(): _check_inherited_debounce = false
	def.call_deferred()
	_check_inherited_debounce = false


func _clean_resolve_cache():
	for member_name in _resolve_cache.keys():
		if not has_script_member(member_name):
			_resolve_cache.erase(member_name)
