const UString = preload("res://addons/addon_lib/brohd/alib_runtime/utils/u_string.gd")

const GDScriptParser = preload("res://addons/addon_lib/brohd/alib_runtime/utils/resource/gdscript/parser/gdscript_parser.gd")
const Keys = preload("res://addons/addon_lib/brohd/alib_runtime/utils/resource/gdscript/parser/utils/keys.gd")
const CodeEditParser = preload("res://addons/addon_lib/brohd/alib_runtime/utils/resource/gdscript/parser/utils/code_edit_parser.gd")
const BuiltInChecker = preload("res://addons/addon_lib/brohd/alib_runtime/utils/resource/gdscript/parser/utils/builtin/builtin_checker.gd")
const AccessObject = GDScriptParser.TypeLookup.AccessObject

const UClassDetail = GDScriptParser.UClassDetail

const DECLARATIONS = [&"class ", &"var ", &"static ", &"func ", &"enum ", &"const ", &"signal "]

const ENUM_SUFFIX = Keys.ENUM_PATH_SUFFIX

static var _class_regex:RegEx
static var _var_const_regex:RegEx
static var _preload_regex:RegEx
static var _enum_regex:RegEx
static var _func_regex:RegEx
static var _arg_regex:RegEx
static var _signal_regex:RegEx


static func get_func_name_in_line(stripped_line_text:String) -> String:
	if not (stripped_line_text.begins_with("func ") or stripped_line_text.begins_with("static func ")):
		return ""
	var func_name = stripped_line_text.get_slice("func ", 1).get_slice("(", 0)
	return func_name.strip_edges()

static func get_class_name_in_line(stripped_line_text:String) -> String:
	if not stripped_line_text.begins_with("class "): # "" <- parser
		return ""
	var _class = stripped_line_text.get_slice("class ", 1).get_slice(":", 0) # "" <- parser
	if _class.find("extends ") > -1: #  "" <- parser
		_class = _class.get_slice("extends ", 0) #  "" <- parser
	return _class.strip_edges()



static func get_class_info(stripped_line: String):
	if not is_instance_valid(_class_regex):
		_class_regex = RegEx.new()
		_class_regex.compile("^class\\s+([a-zA-Z_]\\w*)(?:\\s+extends\\s+([a-zA-Z0-9_.]+))?")
	var _match = _class_regex.search(stripped_line)
	if not _match:
		return null
		
	var _class_name = _match.get_string(1)
	var extends_name = _match.get_string(2) # Will be empty if no 'extends'
	return [_class_name, extends_name]


static func get_var_or_const_info(stripped_line:String):# -> Array:
	if not is_instance_valid(_var_const_regex):
		_var_const_regex = RegEx.new()
		_var_const_regex.compile("^(?:static\\s+)?(?:var|const)\\s+([a-zA-Z_]\\w*)(?:\\s*:\\s*(?!=)([^=]+?))?(?:\\s*(?::?=)\\s*(.*))?$")
	if not is_instance_valid(_preload_regex):
		_preload_regex = RegEx.new()
		_preload_regex.compile("preload\\(\\s*[\"']([^\"']+)[\"']\\s*\\)(.*)")
	
	var _match = _var_const_regex.search(stripped_line)
	if not _match:
		return null# [] # Not a valid var/const declaration
	
	var name = _match.get_string(1).strip_edges()
	var type_hint = _match.get_string(2).strip_edges()
	var assignment = _match.get_string(3).strip_edges()

	# --- HANDLE THE PRELOAD REQUEST ---
	if assignment.begins_with("preload"):
		var p_match = _preload_regex.search(assignment)
		if p_match:
			var path = p_match.get_string(1)
			var tail = p_match.get_string(2).strip_edges()
			# This turns preload("my_path").SomeClass -> "my_path.SomeClass"
			assignment = path + tail 
			
	if type_hint == "":
		type_hint = assignment

	return [name, type_hint]


static func get_enum_info(stripped_line: String) -> Array:
	if not is_instance_valid(_enum_regex):
		_enum_regex = RegEx.new()
		_enum_regex.compile("^enum\\s+([a-zA-Z_]\\w*)?\\s*\\{([^}]*)\\}")
	r"^enum\s+([a-zA-Z_]\w*)?\s*\{([^}]*)\}"
	var _match = _enum_regex.search(stripped_line)
	if not _match:
		return []

	var enum_name = _match.get_string(1).strip_edges() # Will be "" if unnamed enum
	var body_text = _match.get_string(2).strip_edges()

	var enum_data = {}
	var current_value = 0
	
	if not body_text.is_empty():
		# Split by comma (handles single-line and multi-line if they were combined)
		var members = body_text.split(",")
		
		for m in members:
			var clean_m = m.strip_edges()
			
			# Skip empty strings caused by trailing commas (e.g., {A, B,})
			if clean_m.is_empty():
				continue
				
			# Handle explicit assignments (e.g., ITEM = 5)
			if "=" in clean_m:
				var parts = clean_m.split("=")
				var m_name = parts[0].strip_edges()
				var m_val_str = parts[1].strip_edges()
				
				# If it's a standard number, update our current value counter
				if m_val_str.is_valid_int():
					current_value = m_val_str.to_int()
					enum_data[m_name] = current_value
				else:
					# Fallback for complex expressions (e.g. ITEM = 1 << 2)
					# Just store the string expression, but keep the counter moving
					enum_data[m_name] = m_val_str 
				
				current_value += 1
			else:
				# Standard auto-incrementing member
				enum_data[clean_m] = current_value
				current_value += 1
	
	return [enum_name, enum_data]


static func get_func_info(stripped_text: String) -> Dictionary:
	_initialize_arg_regex()
	if not is_instance_valid(_func_regex):
		_func_regex = RegEx.new()
		_func_regex.compile("^(?:static\\s+)?func\\s+([a-zA-Z_]\\w*)\\s*\\((.*)\\)(?:\\s*->\\s*([^:]+))?")
	
	print("GET FUNC::", stripped_text)
	var func_data = { Keys.FUNC_ARGS: {} }
	
	var _match = _func_regex.search(stripped_text)
	if not _match:
		return {} # Not a valid function signature
	
	var func_name = _match.get_string(1)
	var args_string = _match.get_string(2).strip_edges()
	var return_type = _match.get_string(3).strip_edges()
	
	func_data[Keys.FUNC_NAME] = func_name
	if not return_type.is_empty():
		func_data[Keys.FUNC_RETURN] = return_type
	
	if not args_string.is_empty():
		var split_args = safe_split_args(args_string)
		
		for arg_str in split_args:
			var arg_match = _arg_regex.search(arg_str)
			if arg_match:
				var arg_name = arg_match.get_string(1).strip_edges()
				var type_hint = arg_match.get_string(2).strip_edges()
				var default_val = arg_match.get_string(3).strip_edges()
				
				# If no type hint was provided, use the default value as the fallback
				# (Just like you did with your variable logic!)
				if type_hint.is_empty():
					type_hint = default_val
					
				func_data[Keys.FUNC_ARGS][arg_name] = type_hint

	return func_data


static func get_signal_info(stripped_text: String) -> Dictionary:
	_initialize_arg_regex()
	if not is_instance_valid(_signal_regex):
		_signal_regex = RegEx.new()
		_signal_regex.compile("^signal\\s+([a-zA-Z_]\\w*)(?:\\s*\\((.*)\\))?")
	
	
	var signal_data = { Keys.SIGNAL_ARGS: {} }
	
	var _match = _signal_regex.search(stripped_text)
	if not _match:
		return {} # Not a valid signal declaration

	var signal_name = _match.get_string(1)
	signal_data[Keys.SIGNAL_NAME] = signal_name
	
	var args_string = _match.get_string(2).strip_edges()

	# --- HANDLE ARGUMENTS ---
	if not args_string.is_empty():
		# Re-use our bulletproof splitter!
		var split_args = safe_split_args(args_string)
		
		for arg_str in split_args:
			# Re-use our function argument regex!
			var arg_match = _arg_regex.search(arg_str)
			if arg_match:
				var arg_name = arg_match.get_string(1).strip_edges()
				var type_hint = arg_match.get_string(2).strip_edges()
				
				# We ignore Group 3 (default values) because signals can't have them
				signal_data[Keys.SIGNAL_ARGS][arg_name] = type_hint

	return signal_data


static func safe_split_args(args_str: String) -> Array[String]:
	var args: Array[String] = []
	var current_arg := ""
	var bracket_depth := 0
	var in_string := false
	var string_char := ""

	for i in range(args_str.length()):
		var c = args_str[i]

		if in_string:
			current_arg += c
			# Safely exit string, ignoring escaped quotes like \"
			if c == string_char and args_str[i-1] != "\\":
				in_string = false
		else:
			if c == '"' or c == "'":
				in_string = true
				string_char = c
				current_arg += c
			elif c in ["(", "[", "{"]:
				bracket_depth += 1
				current_arg += c
			elif c in [")", "]", "}"]:
				bracket_depth -= 1
				current_arg += c
			elif c == "," and bracket_depth == 0:
				# We found a REAL comma! Save the arg and reset.
				args.append(current_arg.strip_edges())
				current_arg = ""
			else:
				current_arg += c

	if not current_arg.strip_edges().is_empty():
		args.append(current_arg.strip_edges())

	return args


static func line_has_any_declaration(stripped_line:String):
	for dec in DECLARATIONS:
		if stripped_line.begins_with(dec):
			return true
	return false

static func add_var_to_dict(stripped_line:String, line:int, dict:Dictionary, int_key:=false):
	var var_data = get_var_or_const_info(stripped_line)
	if var_data != null:
		var var_name = var_data[0]
		var type = var_data[1]
		if type.find(".new(") > -1:
			type = type.get_slice(".new(", 0)
		var key = line if int_key else var_name
		dict[key] = {
			Keys.MEMBER_NAME: var_name,
			Keys.LINE_INDEX: line,
			Keys.MEMBER_TYPE: Keys.MEMBER_TYPE_VAR,
			Keys.TYPE: type,
			}
	return var_data


#region Access Object

static func get_access_object(current_script_path:String, type_path:String, access_object:AccessObject, argument_object:AccessObject):
	if argument_object == null:
		print_deb(T.ACCESS_PATH, "ACCESS")
		return access_object
	
	var access_script_data = UString.get_script_path_and_suffix(access_object.declaration_type)
	var access_script_path = access_script_data[0]
	
	var type_script_data = UString.get_script_path_and_suffix(type_path)
	var type_script_path = type_script_data[0]
	#var arg_front = UString.get_member_access_front(argument_object.access_symbol) # not sure about doing this, it does simplify though
	print("ARG ACCESS ", argument_object.access_symbol)
	
	 # if access object is current script and type is outside of script, use argument. Then if argument is current, that is fine
	var func_access_is_current_script = access_script_path.begins_with(current_script_path)
	if func_access_is_current_script and type_script_path != access_script_path:
		print_deb(T.ACCESS_PATH, "ARG")
		return argument_object
	#elif UClassDetail.get_global_class_path(arg_front) != "": # if arg uses a global access, use it
		#print_deb(T.ACCESS_PATH, "ARG")
		#return argument_object
	else: # finally, use access object
		print_deb(T.ACCESS_PATH, "ACCESS")
		return access_object


static func find_path_to_type_operation(from_access:AccessObject, to_find:String):
	print_deb(T.ACCESS_PATH, "TO FIND",to_find)
	var symbol = from_access.declaration_symbol
	var access_obj_type = from_access.declaration_type
	print_deb(T.ACCESS_PATH, "DEC",  symbol, access_obj_type)
	print_deb(T.ACCESS_PATH, "ACCESS", from_access.access_symbol, from_access.access_type)
	if access_obj_type.ends_with(ENUM_SUFFIX): # if direct declaration is enum, switch to access symbol
		symbol = from_access.access_symbol # this could be used for other suffixes in future
		access_obj_type = from_access.access_type
	
	print_deb(T.ACCESS_PATH, symbol, access_obj_type)
	
	var access_script_data = UString.get_script_path_and_suffix(access_obj_type)
	var access_script_path = access_script_data[0] # get script of access object resolved type
	var access_script = load(access_script_path) as GDScript
	var access_class_path = access_script_data[1].trim_suffix(ENUM_SUFFIX)
	
	var to_find_script_data = UString.get_script_path_and_suffix(to_find)
	var to_find_script_path = to_find_script_data[0] # get script of type to find
	var to_find_script = load(to_find_script_path) as GDScript
	var to_find_class_path = to_find_script_data[1].trim_suffix(ENUM_SUFFIX) # trim suffix here? should not be needed after since we knew it going in
	
	print_deb(T.ACCESS_PATH, access_script, to_find_script)
	
	#if to_find_script.get_global_name() != "": # if to find is a global script, just use it, and append the inner class path
		#return UString.dot_joinv([to_find_script.get_global_name(), to_find_class_path]) # had this as the last, but seemed to have issues with returning without access name
	
	if access_script_path == to_find_script_path: # access script is the type script
		to_find_class_path = to_find_class_path.trim_prefix(access_class_path).trim_prefix(".") # trim the access paths class path, if not accessing from script root
		if access_obj_type.ends_with(ENUM_SUFFIX): # at this point, this would mean we've switched to access symbol and it is still enum
			print_deb(T.ACCESS_PATH, "OBJ IS ENUM")
			return from_access.declaration_symbol  # switch back to declaration which will have full path from access to declaration or named var, i think
		elif from_access.declaration_type.ends_with(ENUM_SUFFIX): #^ not sure about this, but is needed for when classes imported as const in the current file
			return from_access.declaration_symbol
		return UString.dot_join(symbol, to_find_class_path)
	else: # access is not the type script, but we accessed it from this so it should be somewhere. Search for the script preloaded
		var access = UClassDetail.script_get_member_by_value(access_script, to_find_script, true, ["const", "enum"])
		if access != null:
			return UString.dot_joinv([symbol, access, to_find_class_path])
	
	if to_find_script.get_global_name() != "": # if to find is a global script, just use it, and append the inner class path
		print_deb(T.ACCESS_PATH, "GLOBAL")
		return UString.dot_joinv([to_find_script.get_global_name(), to_find_class_path]) # had this as the last, but seemed to have issues with returning without access name
	
	return "NO PATH - OPERATION"


static func find_path_to_type_function(from_access:AccessObject, argument_access:AccessObject, to_find:String, function_object:String):
	if argument_access == null or from_access == argument_access: # if no valid argument access or is our main object, can just do the operation func
		return find_path_to_type_operation(from_access, to_find)
	
	print_deb(T.ACCESS_PATH, "FUNCTION")
	var symbol = from_access.declaration_symbol
	var access_obj_type = from_access.declaration_type
	print_deb(T.ACCESS_PATH, "DEC",  symbol, access_obj_type)
	print_deb(T.ACCESS_PATH, "ACCESS", from_access.access_symbol, from_access.access_type)
	if access_obj_type.ends_with(ENUM_SUFFIX): # same logic as above
		symbol = from_access.access_symbol
		access_obj_type = from_access.access_type
	print_deb(T.ACCESS_PATH, symbol, access_obj_type)
	
	var access_script_data = UString.get_script_path_and_suffix(access_obj_type) # same logic as above
	var access_script_path = access_script_data[0]
	var access_script = load(access_script_path) as GDScript
	var access_class_path = access_script_data[1].trim_suffix(ENUM_SUFFIX) # don't need for a search by val
	
	var to_find_script_data = UString.get_script_path_and_suffix(to_find) # same logic as above
	var to_find_script_path = to_find_script_data[0]
	var to_find_script = load(to_find_script_path) as GDScript
	var to_find_class_path = to_find_script_data[1].trim_suffix(ENUM_SUFFIX) # trim suffix here? should not be needed after since we knew it going in
	print_deb(T.ACCESS_PATH, access_script, to_find_script)
	
	var function_object_script_data = UString.get_script_path_and_suffix(function_object) # function object is script where the function is
	var function_object_path = function_object_script_data[0]
	var func_script = load(function_object_path) as GDScript
	
	#if from_access != argument_access: # should be fine to comment, can't get here logically?
	var path_access = symbol # default to the chosen symbol
	if access_script_path != to_find_script_path: # access script is not the type script
		var access = UClassDetail.script_get_member_by_value(access_script, func_script, true)
		if access != null:
			path_access = UString.dot_join(symbol, access) # if we find func script in the access script, append access to symbol
	
	print_deb(T.ACCESS_PATH, "ARG DEC", argument_access.declaration_symbol, argument_access.declaration_type)
	print_deb(T.ACCESS_PATH, "ARG ACCESS", argument_access.access_symbol, argument_access.access_type)
	
	# attempt to find the declaration symbol in the script, this would be for consts in the body but used in inner classes
	var rev_find = reverse_search_for_member(function_object, argument_access.declaration_symbol)
	print_deb(T.ACCESS_PATH, "REV FIND", "FUNC OBJ", function_object, rev_find)
	
	if rev_find != null: # found a path to the symbol, reverse search returns a path without symbol
		if argument_access.declaration_type.ends_with(ENUM_SUFFIX): # arg is direct enum declaration
			print_deb(T.ACCESS_PATH, "IS NUM", rev_find, argument_access.declaration_symbol)
			to_find_class_path = UString.dot_join(rev_find, argument_access.declaration_symbol) # to class path ovewritten to new path
			if func_script.get_global_name() != "": # found the arg in the function object, rebase if global name. But what if no global name?
				path_access = func_script.get_global_name()
			else:
				var arg_script_data = UString.get_script_path_and_suffix(argument_access.access_type)
				var arg_script_path = arg_script_data[0]
				if arg_script_path == access_script_path:
					return argument_access.declaration_symbol
			return UString.dot_join(path_access, to_find_class_path) # return access symbol to declaration symbol path
		else: # no path found, currently, do nothing
			# was planning on using function object but seems ok to use below logic
			#var func_script_data = UString.get_script_path_and_suffix(function_object)
			#var func_script = load(func_script_data[0])
			#var access = UClassDetail.script_get_member_by_value(func_script,)
			print_deb(T.ACCESS_PATH, "UN HANDLED")
	
	# this is similar to operation data. I don't think the enum checks are needed since we are using 2 objects here and already filtered.
	# if needed this can be copied over from above
	if access_script_path == to_find_script_path:
		return UString.dot_join(symbol, to_find_class_path)
	else:
		var access = UClassDetail.script_get_member_by_value(access_script, to_find_script, true, ["const", "enum"])
		if access != null:
			return UString.dot_joinv([symbol, access, to_find_class_path])
	
	return "NO PATH - FUNCTION"


static func reverse_search_for_member(full_script_path:String, to_find:String):
	var script_data = UString.get_script_path_and_suffix(full_script_path)
	var script_path = script_data[0]
	var script = load(script_path)
	var class_access = script_data[1] as String
	var search = null
	if class_access != "": # reverse search from the current class to the script root. is not type safe, but should be fairly alright
		for i in range(class_access.count(".") + 1): 
			print_deb(T.ACCESS_PATH, class_access)
			var class_script = UClassDetail.get_member_info_by_path(script, class_access)
			print_deb(T.ACCESS_PATH, class_script)
			if class_script != null:
				search = UClassDetail.get_member_info_by_path(class_script, to_find, ["const", "enum"], false, false, false)
				if search != null:
					break
			
			class_access = UString.trim_member_access_back(class_access) # keep trimming back to check next inner script
	
	if search == null: # if nothing found check root script
		class_access = ""
		search = UClassDetail.get_member_info_by_path(script, to_find)
	if search != null:
		return class_access
	return null


#endregion

static func _initialize_arg_regex():
	if not is_instance_valid(_arg_regex):
		_arg_regex = RegEx.new()
		_arg_regex.compile("^([a-zA-Z_]\\w*)(?:\\s*:\\s*(?!=)([^=]+?))?(?:\\s*(?::?=)\\s*(.*))?$")


class ParserRef:
	static func set_refs(object:Object, parser:GDScriptParser, class_obj:GDScriptParser.ParserClass=null):
		object.set(&"_parser", weakref(parser))
		object.set(&"_code_edit_parser", weakref(parser.code_edit_parser))
		if is_instance_valid(class_obj):
			object.set(&"_class_obj", weakref(class_obj))
	
	static func get_parser(object:Object) -> GDScriptParser:
		return _get_ref(object, &"_parser")
	
	static func get_code_edit_parser(object:Object) -> CodeEditParser:
		return _get_ref(object, &"_code_edit_parser")
	
	static func get_class_obj(object:Object) -> GDScriptParser.ParserClass:
		return _get_ref(object, &"_class_obj")
	
	static func _get_ref(object, string_name:StringName):
		var ref = object.get(string_name)
		if ref:
			return ref.get_ref()
		return



#! arg_location section:T
static func print_deb(section:String, ...msg:Array):
	if section in _PRINT:
		msg.push_front(section)
		ALibEditor.PrintDebug.print(msg)

const _PRINT = [
	T.ACCESS_PATH, 
	]


class T:
	const ACCESS_PATH = "ENUM ACCESS PATH"
