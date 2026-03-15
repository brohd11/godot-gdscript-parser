
const GDScriptParser = preload("res://addons/addon_lib/brohd/alib_runtime/utils/resource/gdscript/parser/gdscript_parser.gd")
const Utils = GDScriptParser.Utils
const Keys = Utils.Keys
const UFile = GDScriptParser.UFile


static var _extension_api:Dictionary = {}

static func _load_extension_api() -> void:
	var target_path:String = new().get_script().resource_path.get_base_dir().path_join("extension_api.json")
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
	
	# break it down into dict[class][method] = method_data, empty class = global func
	for dict in data.get("utility_functions", []):
		_extension_api[""][dict.get("name")] = dict
	
	var built_in_classes = data.get("builtin_classes", [])
	for dict in built_in_classes:
		var class_nm = dict.get("name")
		_extension_api[class_nm] = {}
		var methods = dict.get("methods", [])
		for m_dict in methods:
			_extension_api[class_nm][m_dict.get("name")] = m_dict
	
	var classes = data.get("classes", [])
	for dict in classes:
		var class_nm = dict.get("name")
		_extension_api[class_nm] = {}
		var methods = dict.get("methods", [])
		for m_dict in methods:
			_extension_api[class_nm][m_dict.get("name")] = m_dict

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
	if _extension_api.is_empty():
		_load_extension_api()
	var class_data = _extension_api.get(class_nm, {})
	var api_data = class_data.get(func_name, {})
	if not api_data.is_empty():
		if api_data.has("return_type"):
			return api_data.get("return_type", "void")
		elif api_data.has("return_value"):
			return api_data.get("return_value", {}).get("type", "void")
		return "void"
	return ""

static func is_global_method(identifier:String) -> bool:
	if _extension_api.is_empty():
		_load_extension_api()
	var class_data = _extension_api.get("", {})
	return class_data.has(identifier)

static func get_global_func_data(func_name:String) -> Dictionary:
	return get_func_data("", func_name)

static func get_global_func_return(func_name:String) -> String:
	return get_func_return("", func_name)
