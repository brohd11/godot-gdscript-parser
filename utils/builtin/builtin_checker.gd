
const GDScriptParser = preload("uid://c4465kdwgj042") #! resolve ALibRuntime.Utils.UGDScript.Parser
const Utils = GDScriptParser.Utils
const Keys = Utils.Keys
const UFile = GDScriptParser.UFile

const CLASS_NAME = &"<%class_name%>"
const MEMBER_TYPE = &"member_type"
const METHODS = &"methods"
const PROPERTIES = &"properties"
const SIGNALS = &"signals"
const MEMBERS = &"members"
const CONSTANTS = &"constants"
const ENUMS = &"enums"

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
	"null": true,
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
	#"Object": true, # want to handle this custom, since it's a little different than the other variants
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
		var exe_path:String = OS.get_executable_path()
		var args:Array = ["--headless", "--dump-extension-api"]
		var exit:int = OS.execute(exe_path, args)
		if exit != 0:
			printerr("Failed to generate extension_api.json: ", exit)
		else:
			DirAccess.make_dir_recursive_absolute(target_path.get_base_dir())
			var err:Error = DirAccess.rename_absolute("res://extension_api.json", target_path)
			if err != OK:
				printerr("Could not move extension_api.json to: ", target_path)
				return
	
	if not FileAccess.file_exists(target_path):
		printerr("Failed to generate extension_api.json for GDScriptParser - This should not happen, file an issue on GitHub")
		return
	var data:Dictionary = UFile.read_from_json(target_path)
	
	_extension_api.clear()
	_extension_api[""] = {}
	
	for key:String in _GDSCRIPT_FUNCS.keys():
		_extension_api[""][key] = {
			MEMBER_TYPE: METHODS,
			"return_value":{
				"type":_GDSCRIPT_FUNCS[key]
				}
			}
	
	# break it down into dict[class][method] = method_data, empty class = global func
	for dict:Dictionary in data.get("utility_functions", []):
		dict[MEMBER_TYPE] = METHODS
		_extension_api[""][dict.get("name")] = dict
	
	for dict:Dictionary in data.get("global_enums", []):
		dict[MEMBER_TYPE] = ENUMS
		var enum_name:String = dict.get("name")
		_extension_api[""][enum_name] = dict
		for v:Dictionary in dict.get("values"):
			_extension_api[""][v.get("name")] = {
				MEMBER_TYPE: ENUMS,
				"type": "enum::" + enum_name
			}
			pass
	
	var built_in_classes:Array = data.get("builtin_classes", [])
	for class_dict:Dictionary in built_in_classes:
		var class_nm:String = class_dict.get("name")
		_extension_api[class_nm] = {CLASS_NAME: class_nm}
		_add_to_dict(class_nm, METHODS, class_dict)
		_add_to_dict(class_nm, CONSTANTS, class_dict)
		_add_to_dict(class_nm, MEMBERS, class_dict)
	
	var classes:Array = data.get("classes", [])
	for class_dict:Dictionary in classes:
		var class_nm:String = class_dict.get("name")
		_extension_api[class_nm] = {CLASS_NAME: class_nm}
		_add_to_dict(class_nm, METHODS, class_dict)
		_add_to_dict(class_nm, CONSTANTS, class_dict)
		_add_to_dict(class_nm, ENUMS, class_dict)
		_add_to_dict(class_nm, MEMBERS, class_dict)
		_add_to_dict(class_nm, SIGNALS, class_dict)
		_add_to_dict(class_nm, PROPERTIES, class_dict)

static func _add_to_dict(class_nm:String, member_string:String, class_dict:Dictionary) -> void:
	var member_dict_array:Array = class_dict.get(member_string, [])
	var member_string_name:StringName = StringName(member_string)
	for member_dict:Dictionary in member_dict_array:
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
	
	var all_class_data:Array[Dictionary] = get_class_data(class_nm)
	for class_data:Dictionary in all_class_data:
		var api_data:Dictionary = class_data.get(func_name, {})
		if not api_data.is_empty():
			var data:Dictionary = {Keys.FUNC_ARGS:{}, Keys.FUNC_RETURN: "void"}
			for arg:Dictionary in api_data.get("arguments", []):
				data[Keys.FUNC_ARGS][arg.get("name")] = {
					Keys.TYPE: arg.get("type", ""),
					Keys.MEMBER_TYPE: Keys.MEMBER_TYPE_FUNC_ARG
				}
			if api_data.has("return_type"):
				data[Keys.FUNC_RETURN] = api_data["return_type"]
			elif api_data.has("return_value"):
				data[Keys.FUNC_RETURN] = api_data["return_value"].get("type")
			return data
	return {}

static func get_func_return(class_nm:String, func_name:String) -> String:
	return get_member_type(class_nm, func_name)

static func is_global_method(identifier:String) -> bool:
	if _extension_api.is_empty():
		_load_extension_api()
	var class_data:Dictionary = _extension_api.get("", {})
	if not class_data.has(identifier):
		return false
	return class_data.get(identifier).get(MEMBER_TYPE) == METHODS

static func is_global_enum(identifier:String) -> bool:
	if _extension_api.is_empty():
		_load_extension_api()
	var class_data:Dictionary = _extension_api.get("", {})
	if not class_data.has(identifier):
		return false
	return class_data.get(identifier).get(MEMBER_TYPE) == ENUMS

static func get_global_member_type(identifier:String) -> String:
	return get_member_type("", identifier, false)

static func get_global_func_data(func_name:String) -> Dictionary:
	return get_func_data("", func_name)

static func get_global_func_return(func_name:String) -> String:
	return get_member_type("", func_name, false)

static func class_has_method(class_nm:String, member_name:String, include_inheritance:=true) -> bool:
	if _extension_api.is_empty():
		_load_extension_api()
	var class_data:Variant = _extension_api.get(class_nm)
	if class_data == null:
		return false
	if class_data.has(member_name):
		var member_data:Variant = class_data.get(member_name)
		if member_data:
			return member_data.get(MEMBER_TYPE) == METHODS
			#return member_data.has("return_value") or member_data.has("return_type")
	if not include_inheritance or not ClassDB.class_exists(class_nm):
		return false
	var inherited:StringName = ClassDB.get_parent_class(class_nm)
	while inherited != "":
		var inh_class_data:Variant = _extension_api.get(inherited)
		if inh_class_data and inh_class_data.has(member_name):
			var member_data:Variant = class_data.get(member_name)
			if member_data:
				return member_data.get(MEMBER_TYPE) == METHODS
				#return member_data.has("return_value") or member_data.has("return_type")
		inherited = ClassDB.get_parent_class(inherited)
	return false

static func class_has_member(class_nm:String, member_name:String, include_inheritance:=true) -> bool:
	if _extension_api.is_empty():
		_load_extension_api()
	var class_data:Variant = _extension_api.get(class_nm)
	if class_data == null:
		return false
	if class_data.has(member_name):
		return true
	if not include_inheritance or not ClassDB.class_exists(class_nm):
		return false
	var inherited:StringName = ClassDB.get_parent_class(class_nm)
	while inherited != "":
		var inh_class_data:Variant = _extension_api.get(inherited)
		if inh_class_data and inh_class_data.has(member_name):
			return true
		inherited = ClassDB.get_parent_class(inherited)
	return false

static func get_member_type(class_nm:String, member_name:String, include_inheritance:=true) -> String:
	var direct_check:String = _get_member_type(class_nm, member_name)
	if not include_inheritance or not ClassDB.class_exists(class_nm):
		return direct_check
	if direct_check != "":
		return direct_check
	
	var inherited:StringName = ClassDB.get_parent_class(class_nm)
	while inherited != "":
		var inh_check:String = _get_member_type(inherited, member_name)
		if inh_check != "":
			return inh_check
		inherited = ClassDB.get_parent_class(inherited)
	return ""


static func _get_member_type(class_nm:String, member_name:String) -> String:
	if _extension_api.is_empty():
		_load_extension_api()
	var class_data:Dictionary = _extension_api.get(class_nm, {})
	var api_data:Dictionary = class_data.get(member_name, {})
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
			var signal_args:Array = api_data.get("arguments",[])
			if signal_args.size() == 1:
				return signal_args[0].get("type")
			else:
				return "Array"
			
		return "void"
	return ""






static func is_variant_type(type:String) -> bool:
	if type.begins_with("D"):
		if type.begins_with("Dictionary") and type.contains("["):
			type = "Dictionary"
	elif type.begins_with("A"):
		if type.begins_with("Array") and type.contains("["):
			type = "Array"
	return _VARIANTS.has(type)

static func get_variant_index_access_type(type:String) -> String:
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

static func get_class_names() -> Array:
	if _extension_api.is_empty():
		_load_extension_api()
	var names:Array = _extension_api.keys()
	names.erase("")
	return names

static func get_class_data(class_nm:StringName, include_inherited:=true) -> Array[Dictionary]:
	if _extension_api.is_empty():
		_load_extension_api()
	var class_data_array:Array[Dictionary] = [_extension_api.get(class_nm, {})]
	if not include_inherited or not ClassDB.class_exists(class_nm):
		return class_data_array
	var inherited:StringName = ClassDB.get_parent_class(class_nm)
	while inherited != "":
		class_data_array.append(_extension_api.get(inherited, {}))
		inherited = ClassDB.get_parent_class(inherited)
	return class_data_array

static func get_member_data(class_nm:StringName, member_name:String, include_inherited:=true) -> Dictionary:
	var class_data_array:Array[Dictionary] = get_class_data(class_nm, include_inherited)
	for dict:Dictionary in class_data_array:
		if dict.has(member_name):
			#var member_data = dict.get(member_name, {})
			#if member_data is String: # this check was was for class_name, should not be an issue now
				#print(class_nm, "::", member_name, "::", member_data)
			return dict.get(member_name, {})
	return {}

static func is_member_const(class_nm:StringName, member_name:String, include_inherited:=true) -> bool:
	var member_data:Dictionary = get_member_data(class_nm, member_name, include_inherited)
	var member_type:Variant = member_data.get(MEMBER_TYPE)
	if member_type == MEMBERS or member_type == SIGNALS:
		return false
	if member_type == CONSTANTS or member_type == ENUMS:
		return true
	
	return true


# these methods are easier but slower
static func class_has_method_test(class_nm:String, member_name:String, include_inheritance:=true) -> bool:
	var meth_check:Callable = func(data) -> bool:
		return data.get(MEMBER_TYPE) == &"methods"
	return _class_has(meth_check, class_nm, member_name, include_inheritance)

static func class_has_signal(class_nm:String, member_name:String, include_inheritance:=true) -> bool:
	
	var signal_check:Callable = func(data) -> bool:
		if data == null:
			return false
		return data.get(MEMBER_TYPE, &"") == &"signals"
	
	return _class_has(signal_check, class_nm, member_name, include_inheritance)

static func class_has_enum(class_nm:String, member_name:String, include_inheritance:=true) -> bool:
	
	var signal_check:Callable = func(data) -> bool:
		if data == null:
			return false
		return data.get(MEMBER_TYPE, &"") == ENUMS
	
	return _class_has(signal_check, class_nm, member_name, include_inheritance)


static func _class_has(check_callable:Callable, class_nm:String, member_name:String, include_inheritance:=true) -> bool:
	if _extension_api.is_empty():
		_load_extension_api()
	var class_data:Variant = _extension_api.get(class_nm)
	if class_data == null:
		return false
	if class_data.has(member_name):
		var mem_data:Variant = class_data.get(member_name)
		if mem_data and check_callable.call(mem_data):
			return true
	if not include_inheritance or not ClassDB.class_exists(class_nm):
		return false
	var inherited:StringName = ClassDB.get_parent_class(class_nm)
	while inherited != "":
		var inh_class_data:Variant = _extension_api.get(inherited)
		if inh_class_data and inh_class_data.has(member_name):
			var inh_mem_data:Variant = inh_class_data.get(member_name)
			if inh_mem_data and check_callable.call(inh_mem_data):
				return true
		inherited = ClassDB.get_parent_class(inherited)
	return false
