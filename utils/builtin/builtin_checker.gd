
const GDScriptParser = preload("uid://c4465kdwgj042") #! resolve ALibRuntime.Utils.UGDScript.Parser
const Utils = GDScriptParser.Utils
const Keys = Utils.Keys
const UFile = GDScriptParser.UFile

const MEMBER_TYPE = &"member_type"
const _METHODS = &"methods"
const _PROPERTIES = &"properties"
const _SIGNALS = &"signals"
const _MEMBERS = &"members"
const _CONSTANTS = &"constants"
const _ENUMS = &"enums"

const EXTENSION_API_PATH = "res://.godot/addons/gdscript_parser"

const _GDSCRIPT_FUNCS = {
	"char":"String",
	"len":"int",
	"type_exists": "bool",
	"get_stack": "Array",
	"inst_to_dict": "Dictionary",
	"dict_to_inst": "Object",
	"load": "Resource",
	"convert": "Variant",
	"range": "Array[int]"
}

const _VARIANTS: Dictionary = {
	# Primitives & Core Types
	"Variant":true,
	"Nil": true,
	"bool": true,
	"int": true,
	"float": true,
	"String": true,
	"void": true, # Valid for return types
	
	# Vector Types
	"Vector2": true,
	"Vector2i": true,
	"Vector3": true,
	"Vector3i": true,
	"Vector4": true,
	"Vector4i": true,
	
	# Matrix & Transform Types
	"Transform2D": true,
	"Projection": true,
	"Basis": true,
	"Transform3D": true,
	"Quaternion": true,
	
	# Geometry Types
	"Rect2": true,
	"Rect2i": true,
	"Plane": true,
	"AABB": true,
	
	# Miscellaneous Core Types
	"Color": true,
	"StringName": true,
	"NodePath": true,
	"RID": true,
	
	# Core Objects
	"Object": true,
	"Callable": true,
	"Signal": true,
	"Dictionary": true,
	"Array": true,
	
	# Packed Arrays
	"PackedByteArray": true,
	"PackedInt32Array": true,
	"PackedInt64Array": true,
	"PackedFloat32Array": true,
	"PackedFloat64Array": true,
	"PackedStringArray": true,
	"PackedVector2Array": true,
	"PackedVector3Array": true,
	"PackedColorArray": true,
	"PackedVector4Array": true,
	}


static var _extension_api:Dictionary = {}

static func _load_extension_api() -> void:
	var target_path:String = EXTENSION_API_PATH.path_join("extension_api.json")
	if not FileAccess.file_exists(target_path):
		var exe_path = OS.get_executable_path()
		var args = ["--headless", "--dump-extension-api"]
		var exit = OS.execute(exe_path, args)
		if exit != 0:
			printerr("Failed to generate extension_api.json: ", exit)
		else:
			DirAccess.make_dir_recursive_absolute(target_path.get_base_dir())
			var err = DirAccess.rename_absolute("res://extension_api.json", target_path)
			if err != OK:
				printerr("Could not move extension_api.json to: ", target_path)
				return
	
	if not FileAccess.file_exists(target_path):
		printerr("Failed to generate extension_api.json")
		return
	var data = UFile.read_from_json(target_path)
	
	_extension_api.clear()
	_extension_api[""] = {}
	
	for key in _GDSCRIPT_FUNCS.keys():
		_extension_api[""][key] = {
			MEMBER_TYPE: _METHODS,
			"return_value":{
				"type":_GDSCRIPT_FUNCS[key]
				}
			}
	
	# break it down into dict[class][method] = method_data, empty class = global func
	for dict in data.get("utility_functions", []):
		dict[MEMBER_TYPE] = _METHODS
		_extension_api[""][dict.get("name")] = dict
	
	var built_in_classes = data.get("builtin_classes", [])
	for class_dict in built_in_classes:
		var class_nm = class_dict.get("name")
		_extension_api[class_nm] = {}
		_add_to_dict(class_nm, _METHODS, class_dict)
		_add_to_dict(class_nm, _CONSTANTS, class_dict)
		_add_to_dict(class_nm, _MEMBERS, class_dict)
	
	var classes = data.get("classes", [])
	for class_dict in classes:
		var class_nm = class_dict.get("name")
		_extension_api[class_nm] = {}
		_add_to_dict(class_nm, _METHODS, class_dict)
		_add_to_dict(class_nm, _CONSTANTS, class_dict)
		_add_to_dict(class_nm, _ENUMS, class_dict)
		_add_to_dict(class_nm, _MEMBERS, class_dict)
		_add_to_dict(class_nm, _SIGNALS, class_dict)
		_add_to_dict(class_nm, _PROPERTIES, class_dict)

static func _add_to_dict(class_nm, member_string:String, class_dict:Dictionary):
	var member_dict_array = class_dict.get(member_string, [])
	var member_string_name = StringName(member_string)
	for member_dict in member_dict_array:
		member_dict[MEMBER_TYPE] = member_string_name
		_extension_api[StringName(class_nm)][member_dict.get("name")] = member_dict


static func is_builtin_class(identifier:String) -> bool:
	if identifier == "":
		return false
	if _extension_api.is_empty():
		_load_extension_api()
	return _extension_api.has(identifier)


static func get_func_data(class_nm:String, func_name:String) -> Dictionary:
	if _extension_api.is_empty():
		_load_extension_api()
	
	var class_data = _extension_api.get(class_nm, {})
	var api_data = class_data.get(func_name, {})
	if not api_data.is_empty():
		var data = {Keys.FUNC_ARGS:{}, Keys.FUNC_RETURN: api_data.get("return_type", "void")}
		for arg in api_data.get("arguments", []):
			data[Keys.FUNC_ARGS][arg.get("name")] = {
				Keys.TYPE: arg.get("type", ""),
				Keys.MEMBER_TYPE: Keys.MEMBER_TYPE_FUNC_ARG
			}
		return data
	return {}

static func get_func_return(class_nm:String, func_name:String) -> String:
	return get_member_type(class_nm, func_name)

static func is_global_method(identifier:String) -> bool:
	if _extension_api.is_empty():
		_load_extension_api()
	var class_data = _extension_api.get("", {})
	return class_data.has(identifier)

static func get_global_func_data(func_name:String) -> Dictionary:
	return get_func_data("", func_name)

static func get_global_func_return(func_name:String) -> String:
	return get_member_type("", func_name, false)

static func class_has_method(class_nm:String, member_name:String, include_inheritance:=true) -> bool:
	if _extension_api.is_empty():
		_load_extension_api()
	var class_data = _extension_api.get(class_nm)
	if class_data == null:
		return false
	if class_data.has(member_name):
		var member_data = class_data.get(member_name)
		if member_data:
			return member_data.get(MEMBER_TYPE) == _METHODS
			#return member_data.has("return_value") or member_data.has("return_type")
	if not include_inheritance or not ClassDB.class_exists(class_nm):
		return false
	var inherited = ClassDB.get_parent_class(class_nm)
	while inherited != "":
		var inh_class_data = _extension_api.get(inherited)
		if inh_class_data and inh_class_data.has(member_name):
			var member_data = class_data.get(member_name)
			if member_data:
				return member_data.get(MEMBER_TYPE) == _METHODS
				#return member_data.has("return_value") or member_data.has("return_type")
		inherited = ClassDB.get_parent_class(inherited)
	return false

static func class_has_member(class_nm:String, member_name:String, include_inheritance:=true) -> bool:
	if _extension_api.is_empty():
		_load_extension_api()
	var class_data = _extension_api.get(class_nm)
	if class_data == null:
		return false
	if class_data.has(member_name):
		return true
	if not include_inheritance or not ClassDB.class_exists(class_nm):
		return false
	var inherited = ClassDB.get_parent_class(class_nm)
	while inherited != "":
		var inh_class_data = _extension_api.get(inherited)
		if inh_class_data and inh_class_data.has(member_name):
			return true
		inherited = ClassDB.get_parent_class(inherited)
	return false

static func get_member_type(class_nm:String, member_name:String, include_inheritance:=true) -> String:
	var direct_check = _get_member_type(class_nm, member_name)
	if not include_inheritance or not ClassDB.class_exists(class_nm):
		return direct_check
	if direct_check != "":
		return direct_check
	
	var inherited = ClassDB.get_parent_class(class_nm)
	while inherited != "":
		var inh_check = _get_member_type(inherited, member_name)
		if inh_check != "":
			return inh_check
		inherited = ClassDB.get_parent_class(inherited)
	return ""


static func _get_member_type(class_nm:String, member_name:String) -> String:
	if _extension_api.is_empty():
		_load_extension_api()
	var class_data = _extension_api.get(class_nm, {})
	var api_data = class_data.get(member_name, {})
	if member_name == "text_changed":
		print("EXIT::_get_member_type", class_nm, " -> ", api_data)
	if not api_data.is_empty():
		if api_data.has("return_type"):
			return api_data.get("return_type", "void")
		elif api_data.has("return_value"):
			return api_data.get("return_value", {}).get("type", "void")
		elif api_data.has("type"):
			return api_data.get("type", "Nil")
		elif api_data.has("value"): # integer constants, this may be handled by ClassDB
			return api_data.get("value")
		elif api_data.has("values"): # enum has this, may be handled by ClassDB
			#return api_data.get("value")
			return "enum" # not sure about this
		elif api_data.has("arguments"):
			var signal_args = api_data.get("arguments",[])
			if signal_args.size() == 1:
				return signal_args[0].get("type")
			else:
				return "Array"
			
		return "void"
	return ""






static func is_variant_type(type:String):
	if type.begins_with("D"):
		if type.begins_with("Dictionary") and type.contains("["):
			type = "Dictionary"
	elif type.begins_with("A"):
		if type.begins_with("Array") and type.contains("["):
			type = "Array"
	return _VARIANTS.has(type)

static func get_variant_index_access_type(type:String):
	match type:
		"PackedByteArray", "PackedInt32Array", "PackedInt64Array", "Vector2i", "Vector3i", "Vector4i":
			return "int"
		"PackedFloat32Array", "PackedFloat64Array", "Vector2", "Vector3", "Vector4", "Color":
			return "float"
		"PackedStringArray", "String", "StringName":
			return "String"
		"PackedVector2Array", "Transform2D":
			return "Vector2"
		"PackedVector3Array", "Basis":
			return "Vector3"
		"PackedColorArray":
			return "Color"
		_:
			return "Variant" # Not a known primitive index

static func get_class_names():
	if _extension_api.is_empty():
		_load_extension_api()
	var names = _extension_api.keys()
	names.erase("")
	return names

static func get_class_data(class_nm:StringName, include_inherited:=true):
	if _extension_api.is_empty():
		_load_extension_api()
	var class_data = _extension_api.get(class_nm, {})
	if not include_inherited or not ClassDB.class_exists(class_nm):
		return class_data
	var inherited = ClassDB.get_parent_class(class_nm)
	while inherited != "":
		class_data.merge(_extension_api.get(inherited, {}))
		inherited = ClassDB.get_parent_class(inherited)
	return class_data

static func get_member_data(class_nm:StringName, member_name:String, include_inherited:=true):
	var class_data = get_class_data(class_nm, include_inherited)
	return class_data.get(member_name, {})

static func is_member_const(class_nm:StringName, member_name:String, include_inherited:=true):
	var member_data = get_member_data(class_nm, member_name, include_inherited)
	var member_type = member_data.get(MEMBER_TYPE)
	if member_type == _MEMBERS or member_type == _SIGNALS:
		return false
	if member_type == _CONSTANTS or member_type == _ENUMS:
		return true
	
	return true


# these methods are easier but slower
static func class_has_method_test(class_nm:String, member_name:String, include_inheritance:=true) -> bool:
	var meth_check = func(data) -> bool:
		return data.get(MEMBER_TYPE) == &"methods"
	return _class_has(meth_check, class_nm, member_name, include_inheritance)

static func class_has_signal(class_nm:String, member_name:String, include_inheritance:=true) -> bool:
	
	var signal_check:= func(data) -> bool:
		if data == null:
			return false
		return data.get(MEMBER_TYPE, &"") == &"signals"
	
	return _class_has(signal_check, class_nm, member_name, include_inheritance)

static func _class_has(check_callable:Callable, class_nm:String, member_name:String, include_inheritance:=true) -> bool:
	if _extension_api.is_empty():
		_load_extension_api()
	var class_data = _extension_api.get(class_nm)
	if class_data == null:
		return false
	if class_data.has(member_name):
		var mem_data = class_data.get(member_name)
		if mem_data and check_callable.call(mem_data):
			return true
	if not include_inheritance or not ClassDB.class_exists(class_nm):
		return false
	var inherited = ClassDB.get_parent_class(class_nm)
	while inherited != "":
		var inh_class_data = _extension_api.get(inherited)
		if inh_class_data and inh_class_data.has(member_name):
			var inh_mem_data = inh_class_data.get(member_name)
			if inh_mem_data and check_callable.call(inh_mem_data):
				return true
		inherited = ClassDB.get_parent_class(inherited)
	return false
