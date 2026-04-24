
const GDScriptParser = preload("uid://c4465kdwgj042") #! resolve ALibRuntime.Utils.UGDScript.Parser
const Utils = GDScriptParser.Utils
const Keys = Utils.Keys
const UFile = GDScriptParser.UFile

const EXTENSION_API_PATH = "res://.godot/addons/gdscript_parser"

const _GDSCRIPT_FUNCS = {
	"char":"String",
	"len":"int",
	"type_exists": "bool",
	"get_stack": "Array",
	"inst_to_dict": "Dictionary",
	"dict_to_inst": "Object",
	"load": "Resource",
	"convert": "Variant"
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
			"return_value":{
				"type":_GDSCRIPT_FUNCS[key]
				}
			}
	
	# break it down into dict[class][method] = method_data, empty class = global func
	for dict in data.get("utility_functions", []):
		_extension_api[""][dict.get("name")] = dict
	
	var built_in_classes = data.get("builtin_classes", [])
	for class_dict in built_in_classes:
		var class_nm = class_dict.get("name")
		_extension_api[class_nm] = {}
		_add_to_dict(class_nm, class_dict.get("methods", []))
		_add_to_dict(class_nm, class_dict.get("constants", []))
		_add_to_dict(class_nm, class_dict.get("members", []))
	
	var classes = data.get("classes", [])
	for class_dict in classes:
		var class_nm = class_dict.get("name")
		_extension_api[class_nm] = {}
		_add_to_dict(class_nm, class_dict.get("methods", []))
		_add_to_dict(class_nm, class_dict.get("constants", []))
		_add_to_dict(class_nm, class_dict.get("enums", []))
		_add_to_dict(class_nm, class_dict.get("members", []))
		_add_to_dict(class_nm, class_dict.get("signals", []))
		_add_to_dict(class_nm, class_dict.get("properties", []))

static func _add_to_dict(class_nm, member_dict_array:Array):
	for member_dict in member_dict_array:
		_extension_api[class_nm][member_dict.get("name")] = member_dict


static func is_builtin_class(identifier:String) -> bool:
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
	return get_member_type("", func_name)


static func get_member_type(class_nm:String, member_name:String) -> String:
	if _extension_api.is_empty():
		_load_extension_api()
	var class_data = _extension_api.get(class_nm, {})
	var api_data = class_data.get(member_name, {})
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
		return "void"
	return ""
