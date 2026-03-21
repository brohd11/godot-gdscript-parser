
const GDScriptParser = preload("res://addons/addon_lib/brohd/alib_runtime/utils/resource/gdscript/parser/gdscript_parser.gd")
const ParserClass = GDScriptParser.ParserClass
const ParserFunc = GDScriptParser.ParserFunc
const Utils = GDScriptParser.Utils
const Keys = Utils.Keys
const UString = GDScriptParser.UString
const UFile = GDScriptParser.UFile
const UClassDetail = GDScriptParser.UClassDetail

const ENUM_SUFFIX = Keys.ENUM_PATH_SUFFIX

const SUFFIXES = [ENUM_SUFFIX]


const PLUGIN_EXPORTED = false
const PRINT_DEBUG = true # not PLUGIN_EXPORTED

var _parser:WeakRef

func get_access_object(current_script_path:String, type_path:String, access_object:AccessObject, external_object:AccessObject):
	if external_object == null:
		print_deb(T.ACCESS_PATH, "ACCESS")
		return access_object
	
	var access_script_data = UString.get_script_path_and_suffix(access_object.declaration_type)
	var access_script_path = access_script_data[0]
	
	var type_script_data = UString.get_script_path_and_suffix(type_path)
	var type_script_path = type_script_data[0]
	#var arg_front = UString.get_member_access_front(external_object.access_symbol) # not sure about doing this, it does simplify though
	
	 # if access object is current script and type is outside of script, use argument. Then if argument is current, that is fine
	#var func_access_is_current_script = access_script_path.begins_with(current_script_path)
	#if func_access_is_current_script and type_script_path != access_script_path:
		#print_deb(T.ACCESS_PATH, "ARG")
		#return external_object
	#elif UClassDetail.get_global_class_path(arg_front) != "": # if arg uses a global access, use it
		#print_deb(T.ACCESS_PATH, "ARG")
		#return external_object
	#else: # finally, use access object
		#print_deb(T.ACCESS_PATH, "ACCESS")
	return access_object


func find_path_to_type_operation(class_obj:ParserClass, from_access:AccessObject, to_find:String):
	var parser = Utils.ParserRef.get_parser(self)
	var current_script_path = class_obj.main_script_path
	print_deb(T.ACCESS_PATH, "OPERATION", "----------------------------------------")
	print_deb(T.ACCESS_PATH, "TO FIND",to_find)
	
	var access_options = AccessOptions.new()
	get_global_name_and_script_alias(to_find, class_obj, access_options)
	
	var to_find_script_data = UString.get_script_path_and_suffix(to_find)
	var to_find_script_path = to_find_script_data[0] # get script of type to find
	var to_find_script = load(to_find_script_path) as GDScript
	var to_find_class_path = to_find_script_data[1].trim_suffix(ENUM_SUFFIX) # trim suffix here? should not be needed after since we knew it going in
	
	var access_script_data = UString.get_script_path_and_suffix(from_access.access_type)
	var access_script_path = access_script_data[0] # get script of access object resolved type
	var access_script = load(access_script_path) as GDScript
	var access_class_path = access_script_data[1].trim_suffix(ENUM_SUFFIX)
	
	if current_script_path == to_find_script_path:# or current_script_path == access_script_path:
		if class_obj.has_constant_or_class(from_access.declaration_symbol) and from_access.declaration_type == to_find:
			access_options.standard = from_access.declaration_symbol
		else:
			access_options.standard = to_find_class_path
		return access_options
	
	var declaration_script_data = UString.get_script_path_and_suffix(from_access.declaration_type)
	var declaration_script_path = declaration_script_data[0]
	var declaration_class_path = declaration_script_data[1].trim_suffix(ENUM_SUFFIX)
	
	
	print_deb(T.ACCESS_PATH, "DEC",  from_access.declaration_symbol, from_access.declaration_type)
	print_deb(T.ACCESS_PATH, "ACCESS", from_access.access_symbol, from_access.access_type)
	
	
	
	
	var front_dec = UString.get_member_access_front(from_access.declaration_symbol)
	if class_has_const(from_access.declaration_symbol, class_obj):
		if declaration_script_path == to_find_script_path: # declaration and to find are the same, sub declaration symbol and append suffix
			var trimmed_path = to_find_class_path.trim_prefix(declaration_class_path).trim_prefix(".")
			access_options.standard = UString.dot_joinv([from_access.declaration_symbol, trimmed_path])
			print_deb(T.ACCESS_PATH, "HAS CONST AND DEC == TO FIND")
			return access_options
		
		print_deb(T.ACCESS_PATH, "HAS CONST")
		
		var path_to_type = get_member_by_value(declaration_script_data[0], to_find)
		print_deb(T.ACCESS_PATH, "HAS CONST", "PATH TO TPYE", path_to_type)
		if path_to_type != null:
			access_options.standard = UString.dot_joinv([from_access.declaration_symbol, path_to_type])
			return access_options
		
		print_deb(T.ACCESS_PATH, "HAS CONST NO RESOLUTION")
	
	
	var to_find_access_path = get_member_by_value(access_script_path, to_find)
	if to_find_access_path != null:
		print_deb(T.ACCESS_PATH, "to_find_access_path", to_find_access_path)
		
		access_options.standard = UString.dot_joinv([from_access.access_symbol, to_find_access_path])
		return access_options
	else:
		print_deb(T.ACCESS_PATH, "Could not find to find in access script")
	
	
	
	if access_script_path == to_find_script_path:
		var declaration_access = _find_constant_relative_path(access_script_path, from_access.declaration_symbol)
		if declaration_access != null:
			access_options.standard = UString.dot_joinv([from_access.declaration_symbol, declaration_access, from_access.declaration_symbol])
			return access_options
		else:
			print_deb(T.ACCESS_PATH, "ACCESS SCRIPT COULD NOT FIND CLASS ACCESS")
	
	
	if UClassDetail.get_global_class_path(front_dec) != "":
		access_options.standard = from_access.declaration_symbol
		return access_options
	
	print_deb(T.ACCESS_PATH, "END OF OP")
	return access_options


func find_path_to_type_function(class_obj:ParserClass, from_access:AccessObject, external_access:AccessObject, to_find:String, function_object:String):
	if external_access == null or from_access == external_access: # if no valid argument access or is our main object, can just do the operation func
		return find_path_to_type_operation(class_obj, from_access, to_find)
	
	var current_script_path = class_obj.main_script_path
	print_deb(T.ACCESS_PATH, "FUNCTION", "----------------------------------------")
	print_deb(T.ACCESS_PATH, "TO FIND",to_find)
	
	var access_options = AccessOptions.new()
	get_global_name_and_script_alias(to_find, class_obj, access_options)
	
	var function_object_script_data = UString.get_script_path_and_suffix(function_object) # function object is script where the function is
	var function_object_path = function_object_script_data[0]
	#var func_script = load(function_object_path) as GDScript
	
	var to_find_script_data = UString.get_script_path_and_suffix(to_find) # same logic as above
	var to_find_script_path = to_find_script_data[0]
	var to_find_script = load(to_find_script_path) as GDScript
	#var to_find_class_path = to_find_script_data[1].trim_suffix(ENUM_SUFFIX) # trim suffix here? should not be needed after since we knew it going in
	
	print_deb(T.ACCESS_PATH, "DEC",  from_access.declaration_symbol, from_access.declaration_type)
	print_deb(T.ACCESS_PATH, "ACCESS", from_access.access_symbol, from_access.access_type)
	print_deb(T.ACCESS_PATH, "DEC",  external_access.declaration_symbol, external_access.declaration_type)
	print_deb(T.ACCESS_PATH, "ACCESS", external_access.access_symbol, external_access.access_type)
	print_deb(T.ACCESS_PATH, "FUNCTION", function_object)
	
	
	if current_script_path == to_find_script_path or current_script_path == function_object_path:
		if class_has_const(external_access.declaration_symbol, class_obj) and external_access.declaration_type == to_find:
			access_options.standard = external_access.declaration_symbol # in current script, switch out for declaration if possible
			print_deb(T.ACCESS_PATH, "CURRENT SCRIPT EXIT")
			return access_options
		return find_path_to_type_operation(class_obj, external_access, to_find) # or try a simple operation? this is similar to select object from above
	
	var access_script_data = UString.get_script_path_and_suffix(from_access.access_type) # same logic as above
	var access_script_path = access_script_data[0]
	#var access_script = load(access_script_path) as GDScript
	#var access_class_path = access_script_data[1].trim_suffix(ENUM_SUFFIX) # don't need for a search by val
	
	var declaration_script_data = UString.get_script_path_and_suffix(from_access.declaration_type) # same logic as above
	var declaration_script_path = declaration_script_data[0]
	
	if function_object_path != access_script_path: # function external to current script and access object.
		var dec_to_func_path = get_member_by_value(declaration_script_path, function_object_path)
		if dec_to_func_path != null:
			print_deb(T.ACCESS_PATH, "FUNCTION OUT OF ACCESS SCRIPT, FOUND DEC PATH", dec_to_func_path)
			access_options.standard = UString.dot_joinv([from_access.declaration_symbol, dec_to_func_path, external_access.declaration_symbol])
			return access_options
		
		var access_to_func_path = get_member_by_value(access_script_path, function_object_path)
		print_deb(T.ACCESS_PATH, "FUNCTION NOT ACCESS SCRIPT", "PATH TO", access_to_func_path)
		if access_to_func_path != null: # could reach function from access path
			print_deb(T.ACCESS_PATH, "FUNCTION OUT OF ACCESS SCRIPT, BUT FOUND PATH")
			access_options.standard = UString.dot_joinv([from_access.access_symbol, access_to_func_path, external_access.declaration_symbol])
			return access_options
		else: # can not reach this from here, can attempt a global or abort, a valid global would be there already if possible,
			var to_find_global_name = to_find_script.get_global_name()
			if to_find_global_name != "":# this would be to 'personalize' the symbol, overwrite global?
				var class_access = _find_constant_relative_path(function_object, external_access.declaration_symbol)
				access_options.standard = UString.dot_joinv([to_find_global_name, class_access, external_access.declaration_symbol])
			
			return access_options
	
	
	print_deb(T.ACCESS_PATH, "FUNCTION IS ACCESS SCRIPT")
	
	#if access_script_path == to_find_script_path:
	var declaration_access = _find_constant_relative_path(access_script_path, external_access.declaration_symbol)
	if declaration_access != null:
		access_options.standard = UString.dot_joinv([from_access.declaration_symbol, declaration_access, external_access.declaration_symbol])
		return access_options
	else:
		print_deb(T.ACCESS_PATH, "ACCESS SCRIPT COULD NOT FIND CLASS ACCESS")
	
	var front_arg_dec = UString.get_member_access_front(external_access.declaration_symbol)
	if UClassDetail.get_global_class_path(front_arg_dec) != "":
		access_options.standard = external_access.declaration_symbol
	
	print_deb(T.ACCESS_PATH, "END OF FUNC")
	return access_options


func _find_constant_relative_path(full_script_path:String, member_to_find:String):
	var fwd_find = forward_search_for_member(full_script_path, member_to_find)
	var rev_find = reverse_search_for_member(full_script_path, member_to_find)
	print_deb(T.ACCESS_PATH, "FWD SEARCH", full_script_path.get_file(), "FWD FIND", fwd_find, "REV FIND", rev_find, "EQUAL", fwd_find == rev_find)
	return fwd_find


func reverse_search_for_member(full_script_path:String, to_find:String):
	var t = ALibRuntime.Utils.UProfile.TimeFunction.new("REV")
	var script_data = UString.get_script_path_and_suffix(full_script_path)
	var script_path = script_data[0]
	var script = load(script_path)
	var class_access = script_data[1] as String
	var search = null
	if class_access != "": # reverse search from the current class to the script root. is not type safe, but should be fairly alright
		for i in range(class_access.count(".") + 1): 
			var class_script = UClassDetail.get_member_info_by_path(script, class_access)
			if class_script != null:
				search = UClassDetail.get_member_info_by_path(class_script, to_find, ["const", "enum"], false, false, false, false)
				if search != null:
					break
			
			class_access = UString.trim_member_access_back(class_access) # keep trimming back to check next inner script
	
	if search == null: # if nothing found check root script
		class_access = ""
		search = UClassDetail.get_member_info_by_path(script, to_find, ["const", "enum"], false, false, false, false)
	
	t.stop()
	if search != null:
		return class_access
	return null

# this one uses parser, no class detail
func forward_search_for_member(full_script_path:String, to_find:String):
	var t = ALibRuntime.Utils.UProfile.TimeFunction.new("FWD")
	var script_data = UString.get_script_path_and_suffix(full_script_path)
	var script_path = script_data[0]
	var script_parser = _get_parser_for_script(script_path)
	var class_access = script_data[1] as String
	var class_obj = script_parser.get_class_object(class_access) as ParserClass
	var front = UString.get_member_access_front(to_find)
	if front != to_find:
		print_deb(T.ACCESS_PATH, "SEARCH FOR MEMBER FRONT NOT FULL", to_find)
	var constant_data = class_obj.get_constant_or_class(front)
	t.stop()
	if constant_data == null:
		return null
	return constant_data.get(Keys.ACCESS_PATH)
	
	var class_access_parts = UString.split_member_access(class_access)
	class_access_parts.push_front("")
	print("FWD TO FIND ", to_find, "  ", class_access_parts)
	var search_result = null
	var working_path = ""
	for part in class_access_parts:
		working_path = UString.dot_join(working_path, part)
		
		var result = parser_has_path(to_find, script_parser)
		print("HAS PART ", result)
		if result:
			search_result = working_path
			break
	t.stop()
	return search_result

# this one uses parser, no class detail
func _reverse_search_for_member(full_script_path:String, to_find:String):
	var t = ALibRuntime.Utils.UProfile.TimeFunction.new("FWD")
	var script_data = UString.get_script_path_and_suffix(full_script_path)
	var script_path = script_data[0]
	var script_parser = _get_parser_for_script(script_path)
	var class_access = script_data[1] as String
	var class_access_parts = UString.split_member_access(class_access)
	class_access_parts.push_front("")
	print("FWD TO FIND ", to_find, "  ", class_access_parts)
	var search_result = null
	var working_path = ""
	for part in class_access_parts:
		working_path = UString.dot_join(working_path, part)
		
		var result = parser_has_path(to_find, script_parser)
		print("HAS PART ", result)
		if result:
			search_result = working_path
			break
	t.stop()
	return search_result




# make this available to parser? Possibly should return data though of some type, maybe class obj, then you could run class.get_type() on the last part?
func parser_has_path(path:String, parser:GDScriptParser):
	var class_obj = parser.get_class_object() as ParserClass
	var path_parts = UString.split_member_access(path)
	var is_last_part = false
	for i in range(path_parts.size()):
		if i == path_parts.size() - 1:
			is_last_part = true
		var part = path_parts[i]
		var member_info = class_obj.get_member(part)
		print("GET MEMBER::", part,"::", member_info)
		if member_info == null:
			member_info = class_obj.get_inherited_member(part)
			print("GET MEMBER::", member_info)
			if member_info == null:
				return false
		if is_last_part:
			return true
		var member_type = member_info.get(Keys.MEMBER_TYPE)
		if member_type == Keys.MEMBER_TYPE_CLASS:
			print("INNER CLASS::",part)
			class_obj = parser.get_class_object(part)
		elif member_type == Keys.MEMBER_TYPE_CONST:
			var type = class_obj.get_member_type(part)
			if type.begins_with("res://"):
				var remaining_parts = ""
				for ni in range(i + 1, path_parts.size()):
					remaining_parts = UString.dot_join(remaining_parts, path_parts[ni])
				var script_data = UString.get_script_path_and_suffix(type)
				var next_parser = _get_parser_for_script(script_data[0])
				remaining_parts = UString.dot_join(script_data[1], remaining_parts)
				print("RECURSIVE::", remaining_parts, " -> ", script_data[0])
				return next_parser.get_type_lookup()._parser_has_path(remaining_parts, next_parser)
		else:
			return false # think any other should just be false
	return false



func get_member_by_value(script_path:String, full_to_find_path:String):
	print_deb(T.ACCESS_PATH, "FIND BY VAL", script_path, "->", full_to_find_path)
	var to_find_script_data = UString.get_script_path_and_suffix(full_to_find_path)
	var to_find_script_path = to_find_script_data[0]
	var to_find_script = load(to_find_script_path)
	
	var access_parser = _get_parser_for_script(script_path)
	var script = access_parser.get_current_script()
	var parser_access = _find_constant_by_value(full_to_find_path, access_parser.get_class_object())
	var t2 = ALibRuntime.Utils.UProfile.TimeFunction.new("UClassDetail.script_get_member_by_value")
	var uclass_access = UClassDetail.script_get_member_by_value(script, to_find_script, true, ["const", "enum"])
	t2.stop()
	print_deb(T.ACCESS_PATH, "FIND BY VAL", "UCLASS", uclass_access, "PARSER", parser_access, "EQUAL", uclass_access == parser_access)
	
	return parser_access


func _find_constant_by_value(type_to_find:String, initial_class_obj:ParserClass):
	var t = ALibRuntime.Utils.UProfile.TimeFunction.new("_find_constant_by_value")
	var preload_name = initial_class_obj.has_preload(type_to_find)
	if preload_name != null:
		t.stop()
		return UString.dot_join(initial_class_obj.access_path, preload_name)
	
	var search_from_script = initial_class_obj.get_script_resource()
	
	var search_value = type_to_find
	var script_data = UString.get_script_path_and_suffix(search_value)
	var script_path = script_data[0]
	var script_class_path = script_data[1]
	var suffix = ""
	if type_to_find.ends_with(ENUM_SUFFIX):
		if script_class_path.contains("."):
			suffix = UString.get_member_access_back(script_class_path)
			script_class_path = UString.trim_member_access_back(script_class_path)
		else:
			suffix = script_class_path
			script_class_path = ""
		suffix = remove_suffixes(suffix)
	
	print("ACCESS PATH::", "SEARCH, ", script_class_path, " ",suffix)
	
	var search_script = load(script_path)
	if script_class_path != "":
		search_script = UClassDetail.get_member_info_by_path(search_script, script_class_path, ["const"], false, false, false, false)
	
	print("ACCESS PATH::", "SEARCH, ", search_from_script, " ", search_script, " TO FIND ", type_to_find)
	var access = UClassDetail.script_get_member_by_value(search_from_script, search_script, true, ["const", "enum"])
	if access != null:
		var parser = _get_parser_for_script(script_path)
		var class_obj = parser.get_class_object(script_class_path)
		if search_value != type_to_find: # if we modified the search value, check if the type exists where we found it, for enums and such
			if class_obj.has_preload(type_to_find):
				t.stop()
				return UString.dot_join(access, suffix)
		else:
			t.stop()
			return UString.dot_join(access, suffix)
	
	t.stop()
	return


#func _find_constant_by_value(type_to_find: String, initial_class_obj: ParserClass, initial_parser: GDScriptParser, current_access_path: String = ""):
	##print("TO FIND::", type_to_find, "::INITIAL::", initial_class_obj.get_script_class_path())
	#
	## 1. Initialize the queue with our starting data
	#var queue: Array[Dictionary] = []
	#queue.push_back({
		#"class_obj": initial_class_obj,
		#"parser": initial_parser,
		#"access_path": current_access_path
	#})
	#
	## Optional but recommended: Keep track of visited scripts/classes to prevent 
	## infinite loops if scripts cross-reference each other.
	#var visited_classes: Array = [initial_class_obj] 
#
	## 2. Run the Breadth-First Search
	#while not queue.is_empty():
		## Dequeue the first item (FIFO - First In, First Out)
		#var current = queue.pop_front()
		#
		#var class_obj = current["class_obj"]
		#var parser = current["parser"]
		#var access_path = current["access_path"]
		#
		#var preload_scripts = {}
		#
		## --- CHECK CONSTANTS ---
		#for c in class_obj.constants:
			#var type = class_obj.get_member_type(c)
			##print(c, " -> ", type)
			#
			#if type == type_to_find:
				#return UString.dot_join(access_path, class_obj.access_path)
			#elif type.begins_with("res://") and not type.ends_with(ENUM_SUFFIX):
				##print("ADD TO SCRIPT::", type)
				#preload_scripts[c] = type
				#
		## --- QUEUE INNER CLASSES ---
		#for ic in class_obj.inner_classes:
			#var nested_class = parser.get_class_object(ic)
			#
			## Note: Fixed a minor bug here. Your original code checked is_instance_valid(ic) 
			## where `ic` is likely a String. You want to check `nested_class`.
			#if is_instance_valid(nested_class) and not nested_class in visited_classes:
				#visited_classes.append(nested_class)
				#queue.push_back({
					#"class_obj": nested_class,
					#"parser": parser,
					#"access_path": UString.dot_join(access_path, ic)
				#})
				#
		## --- QUEUE PRELOADED SCRIPTS ---
		#for name in preload_scripts.keys():
			#var script_path = preload_scripts[name]
			#var parser_data = _get_parser_and_class_for_script(script_path)
			#
			#if parser_data and is_instance_valid(parser_data.class_obj):
				#var script_parser = parser_data.parser
				#var script_class_obj = parser_data.class_obj
				#
				#if not script_class_obj in visited_classes:
					#visited_classes.append(script_class_obj)
					#queue.push_back({
						#"class_obj": script_class_obj,
						#"parser": script_parser,
						#"access_path": UString.dot_join(access_path, name)
					#})
	#
	## Return null if the queue empties out and nothing was found
	#return null

func class_has_const(symbol:String, class_obj:ParserClass):
	var front_arg_dec = UString.get_member_access_front(symbol)
	var member_data = class_obj.get_member(front_arg_dec)
	if member_data == null:
		member_data = class_obj.get_inherited_member(front_arg_dec)
	if member_data != null:
		var member_type = member_data.get(Keys.MEMBER_TYPE)
		if member_type == Keys.MEMBER_TYPE_CLASS or member_type == Keys.MEMBER_TYPE_CONST:
			return true
	return false


func get_global_name_and_script_alias(to_find:String, class_obj:ParserClass, access_options:AccessOptions):
	var to_find_script_data = UString.get_script_path_and_suffix(to_find)
	var to_find_script = load(to_find_script_data[0]) as GDScript
	var to_find_class_path = to_find_script_data[1]
	if to_find_script.get_global_name() != "":
		access_options.global = remove_suffixes(UString.dot_join(to_find_script.get_global_name(), to_find_class_path))
	var preloaded_name = class_obj.has_preload(to_find)
	if preloaded_name != null:
		access_options.script_alias = remove_suffixes(preloaded_name)
	else:
		if to_find_class_path.contains("."):
			preloaded_name = class_obj.has_preload(UString.trim_member_access_back(to_find))
			if preloaded_name != null:
				var back = UString.get_member_access_back(to_find)
				access_options.script_alias = remove_suffixes(UString.dot_join(preloaded_name, back))


func _clean_path(string:String):
	if string.begins_with("self."):
		string = string.trim_prefix("self.")
	return remove_suffixes(string)

func remove_suffixes(string:String):
	for suffix in SUFFIXES:
		if string.ends_with(suffix):
			string = string.trim_suffix(suffix)
	return string

func _get_parser_for_script(script_path:String):
	var parser = Utils.ParserRef.get_parser(self)
	return parser.get_parser_for_path(script_path)


class AccessOptions:
	var standard:String
	var script_alias:String
	var global:String


class AccessObject:
	var declaration_type:String
	var declaration_symbol:String
	var access_type:String
	var access_symbol:String

#! arg_location section:T
static func print_deb(section:String, ...msg:Array):
	if not PRINT_DEBUG:
		return
	if section in _PRINT:
		msg.push_front(section)
		ALibEditor.PrintDebug.print(msg)

const _PRINT = [
	#T.BUILTIN, 
	T.INHERITED,
	#T.VAR_TO_CONST,
	#T.RESOLVE,
	T.ACCESS_PATH
	]


class T:
	const RESOLVE = "RESOLVE"
	const BUILTIN = "BUILTIN"
	const INHERITED = "INHERITED"
	const VAR_TO_CONST = "VAR TO CONST"
	const ACCESS_PATH = "ACCESS PATH"
