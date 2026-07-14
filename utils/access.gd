
const GDScriptParser = preload("uid://c4465kdwgj042") #! resolve ALibRuntime.Utils.UGDScript.Parser
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


## Find path to 'to_find' from current class. symbol_access is the current script symbol used to access the type. secondary_access is from the script where the
## function or var is defined. Secondary path is that script path.
func find_path_to_type(class_obj:ParserClass, symbol_access:AccessObject, secondary_access:AccessObject, to_find:String, secondary_path:String) -> AccessOptions:
	var result:AccessOptions = _find_path_to_type_hardened(class_obj, symbol_access, secondary_access, to_find, secondary_path)
	
	# old version
	#var result = _find_path_to_type(class_obj, symbol_access, secondary_access, to_find, secondary_path)
	# ensure no suffixes, or self prefix
	result.standard = AccessUtils.clean_path(result.standard)
	result.script_alias = AccessUtils.clean_path(result.script_alias)
	result.global = AccessUtils.clean_path(result.global)
	return result


func _find_path_to_type(class_obj:ParserClass, symbol_access:AccessObject, secondary_access:AccessObject, to_find:String, secondary_path:String):
	if secondary_access == null or symbol_access == secondary_access: # if no valid argument access or is our main object, can just do the operation func
		print_deb(T.ACCESS_PATH, ["FUNCTION -> OPERATION", "secondary not valid"])
		return _find_path_to_type_simple(class_obj, symbol_access, to_find)
	if symbol_access.declaration_symbol == secondary_access.declaration_symbol and symbol_access.declaration_type == secondary_access.declaration_type:
		print_deb(T.ACCESS_PATH, ["FUNCTION -> OPERATION", "current and secondary data is same"])
		return _find_path_to_type_simple(class_obj, symbol_access, to_find)
	
	var current_script_path:String = class_obj.main_script_path
	print_deb(T.ACCESS_PATH, ["FUNCTION", "----------------------------------------"])
	print_deb(T.ACCESS_PATH, ["FROM", current_script_path, "TO FIND",to_find])
	
	print_deb(T.ACCESS_PATH, ["DEC",  symbol_access.declaration_symbol, symbol_access.declaration_type])
	print_deb(T.ACCESS_PATH, ["DEC-SEC",  secondary_access.declaration_symbol, secondary_access.declaration_type])
	print_deb(T.ACCESS_PATH, ["FUNCTION", secondary_path])
	
	var parser:GDScriptParser = Utils.ParserRef.get_parser(self)
	
	symbol_access.clean_symbols()
	secondary_access.clean_symbols()
	secondary_path = secondary_path.trim_suffix(Keys.INS_DELIM)
	
	
	var access_options:AccessOptions = AccessOptions.new()
	# get global name and script alias are easy to run
	get_global_name_and_script_alias(to_find, class_obj, access_options) # TEMP this works well
	
	var symbol_script_data:Array[String] = Utils.type_path_get_script_data(symbol_access.declaration_type) # same logic as above
	#var symbol_script_path = symbol_script_data[0]
	var symbol_class_path:String = symbol_script_data[1]
	
	# trim the declaration to the script symbol only. This is a bit fragile, strictly string based
	var dec_trimmed:String = ""
	if Utils.type_path_get_type(symbol_access.declaration_type, true) == "Enum":
		if symbol_access.declaration_symbol.contains("."):
			dec_trimmed = UString.trim_member_access_back(symbol_access.declaration_symbol)
		
		dec_trimmed = dec_trimmed.trim_suffix(symbol_class_path).trim_suffix(".")
	else:
		dec_trimmed = symbol_access.declaration_symbol.trim_suffix(symbol_class_path).trim_suffix(".")
	
	
	var symbol_access_parser = parser.get_parser_and_class_obj_for_script(symbol_access.declaration_type)
	var secondary_parser = parser.get_parser_and_class_obj_for_script(secondary_path)
	
	# get the front and type of the secondary, if the symbol is found, then it can be appended to the symbol access 
	var sec_front = UString.get_member_access_front(secondary_access.declaration_symbol)
	var sec_front_type = secondary_access.declaration_type
	if secondary_access.declaration_symbol.contains("."):
		sec_front_type = secondary_parser.class_obj.get_member_type(sec_front, true)
	
	# if secondary is using a global path for access just return the path
	if UClassDetail.get_global_class_path(sec_front) != "":
		access_options.standard = secondary_access.declaration_symbol
		return access_options
	
	# check current class obj for secondary dec symbol
	var class_check = class_obj.get_member_data(sec_front, true)
	if class_check:
		var type = class_obj.get_member_type(sec_front, true)
		if type == sec_front_type:
			access_options.standard = secondary_access.declaration_symbol
			return access_options
	
	# if secondary is to_find check if the back is present, helps to get the right scope
	# may make sense to work backwards and track the path? But haven't had issues yet..
	if secondary_access.declaration_type == to_find:
		var secondary_class_obj = secondary_parser.class_obj as ParserClass
		var back = UString.get_member_access_back(secondary_access.declaration_symbol)
		var member_data = secondary_class_obj.get_member_data(back, true)
		if member_data:
			print_deb_err(T.ACCESS_PATH, ["SEC DEC == TO_FIND"])
			var access_path = member_data.get(Keys.ACCESS_PATH)
			access_options.standard = UString.dot_joinv([dec_trimmed, access_path, back])
			return access_options
	
	#^r doesn't seem to be firing, may be able to get rid of
	# same as above but with symbol access
	if symbol_access.declaration_type == to_find:
		var current_access_class_obj = symbol_access_parser.class_obj as ParserClass
		var back = UString.get_member_access_back(symbol_access.declaration_symbol)
		var member_data = current_access_class_obj.get_member_data(back, true)
		if member_data:
			print_deb_err(T.ACCESS_PATH, ["CURRENT DEC == TO_FIND"])
			var access_path = member_data.get(Keys.ACCESS_PATH)
			access_options.standard = UString.dot_joinv([dec_trimmed, access_path, back])
			return access_options
	#^r
	
	var secondary_dec_front = UString.get_member_access_front(secondary_access.declaration_symbol)
	# 
	if symbol_access_parser:
		var symbol_access_class_obj = symbol_access_parser.class_obj as ParserClass
		
		var sec_member_data = symbol_access_class_obj.get_member_data(secondary_dec_front, true)
		if sec_member_data != null:
			var type = symbol_access_class_obj.get_member_type(secondary_dec_front, true)
			if type == sec_front_type:
				print_deb_err(T.ACCESS_PATH, ["IN MY FIRST CHECK"])
				var access_path = sec_member_data.get(Keys.ACCESS_PATH)
				var full_access_path = UString.dot_joinv([dec_trimmed, access_path, secondary_access.declaration_symbol])
				access_options.standard = full_access_path
				return access_options
		
		var pre_check = symbol_access_class_obj.has_preload(to_find)
		if pre_check:
			print_deb_err(T.ACCESS_PATH, ["PRELOAD CHECK"])
			var preload_member_data = symbol_access_class_obj.get_member_data(pre_check, true)
			var access_path = preload_member_data.get(Keys.ACCESS_PATH)
			var full_access_path = UString.dot_joinv([dec_trimmed, access_path, pre_check])
			access_options.standard = full_access_path
			return access_options
	
	
	var secondary_script_data = Utils.type_path_get_script_data(secondary_path)
	var secondary_script_path = secondary_script_data[0]
	
	var symbol_front = UString.get_member_access_front(symbol_access.declaration_symbol)
	var symbol_front_type = symbol_access.declaration_type
	if symbol_access.declaration_symbol.contains("."):
		symbol_front_type = symbol_access_parser.class_obj.get_member_type(symbol_front)
	
	
	if secondary_parser:
		var secondary_class_obj = secondary_parser.class_obj as ParserClass
		var sec_member_data = secondary_class_obj.get_member_data(secondary_dec_front, true)
		if sec_member_data != null:
			var access_path = sec_member_data.get(Keys.ACCESS_PATH)
			
			#^r haven't seen these firing either, may be covered above? This whole branch may be un-needed
			var current_class_member_data = class_obj.get_member_data(symbol_front)
			if current_class_member_data: # this is the current script class obj searching for "current_access", need some better names
				print_deb_err(T.ACCESS_PATH, ["SECONDARY CURRENT CLASS CHECK"])
				#var access_path = current_class_member_data.get(Keys.ACCESS_PATH)
				var type = class_obj.get_member_type(symbol_front)
				if symbol_front_type == type:
					access_options.standard = UString.dot_joinv([dec_trimmed, access_path, secondary_access.declaration_symbol])
					return access_options
			
			var global_name = UClassDetail.get_global_class_name(secondary_script_path)
			if global_name:
				print_deb_err(T.ACCESS_PATH, ["SECONDARY GLOBAL CHECK"])
				var full_access_path = UString.dot_joinv([global_name, access_path, secondary_access.declaration_symbol])
				access_options.standard = full_access_path
				return access_options
			#^r
	
	print_deb_err(T.ACCESS_PATH, ["Un Resolved Access - Find Path To Type"])
	return access_options


## Hardened dual-access finder. Reuses the solid global/script_alias resolution, then resolves
## the 'standard' path via verified fast-paths falling back to an accurate const-by-value search.
## Never blends two overlapping class chains (the source of the duplicate-segment bug).
func _find_path_to_type_hardened(class_obj:ParserClass, symbol_access:AccessObject, secondary_access:AccessObject, to_find:String, secondary_path:String) -> AccessOptions:
	# Same early guards as the original: if there is no distinct secondary, treat it as a simple lookup.
	if secondary_access == null or symbol_access == secondary_access:
		return _find_path_to_type_simple_hardened(class_obj, symbol_access, to_find)
	if symbol_access.declaration_symbol == secondary_access.declaration_symbol and symbol_access.declaration_type == secondary_access.declaration_type:
		return _find_path_to_type_simple_hardened(class_obj, symbol_access, to_find)

	var parser = Utils.ParserRef.get_parser(self)
	symbol_access.clean_symbols()
	secondary_access.clean_symbols()
	secondary_path = secondary_path.trim_suffix(Keys.INS_DELIM)

	print_deb(T.ACCESS_PATH, ["HARDENED FUNCTION", "----------------------------------------"])
	print_deb(T.ACCESS_PATH, ["FROM", class_obj.main_script_path, "TO FIND", to_find])
	print_deb(T.ACCESS_PATH, ["DEC", symbol_access.declaration_symbol, symbol_access.declaration_type])
	print_deb(T.ACCESS_PATH, ["DEC-SEC", secondary_access.declaration_symbol, secondary_access.declaration_type])

	var access_options = AccessOptions.new()
	get_global_name_and_script_alias(to_find, class_obj, access_options) # solid, reused verbatim

	access_options.standard = _resolve_standard_path(class_obj, symbol_access, to_find, parser, secondary_access, secondary_path)
	return access_options


func find_path_to_type_simple(class_obj:ParserClass, access_object:AccessObject, to_find:String) -> AccessOptions:
	var result = _find_path_to_type_simple_hardened(class_obj, access_object, to_find)
	
	# old version
	#var result = _find_path_to_type_simple(class_obj, access_object, to_find)
	# ensure no suffixes, or self prefix
	result.standard = AccessUtils.clean_path(result.standard)
	result.script_alias = AccessUtils.clean_path(result.script_alias)
	result.global = AccessUtils.clean_path(result.global)
	return result

func _find_path_to_type_simple(class_obj:ParserClass, access_object:AccessObject, to_find:String) -> AccessOptions:
	var parser = Utils.ParserRef.get_parser(self)
	print_deb(T.ACCESS_PATH, ["OPERATION", "----------------------------------------"])
	print_deb(T.ACCESS_PATH, ["FROM", class_obj.get_script_class_path(), "TO FIND",to_find])
	print_deb(T.ACCESS_PATH, ["DEC", access_object.declaration_symbol, access_object.declaration_type])
	
	var access_options = AccessOptions.new()
	get_global_name_and_script_alias(to_find, class_obj, access_options)
	print("GLOBAL:", access_options.global)
	print("SCRIPT:", access_options.script_alias)
	var to_find_script_data = Utils.type_path_get_script_data(to_find)
	var to_find_script_path = to_find_script_data[0]
	var to_find_class_path = to_find_script_data[1]
	
	var dec_front = UString.get_member_access_front(access_object.declaration_symbol)
	if UClassDetail.get_global_class_path(dec_front) != "":
		access_options.standard = access_object.declaration_symbol
		return access_options
	
	var to_find_is_current_script = class_obj.main_script_path == to_find_script_path
	
	if dec_front == "self":
		if to_find_is_current_script:
			access_options.standard = to_find.trim_prefix(class_obj.get_script_class_path())
			if access_options.standard == "" and to_find_class_path != "":
				# means we are in an inner class, return the name
				access_options.standard = to_find_class_path.get_file()
			return access_options
	
	if class_obj.inherits_script(UString.dot_join(to_find_script_path, to_find_class_path)):
		if class_obj.get_member_data(dec_front, true) != null:
			print_deb(T.ACCESS_PATH, ["INH EXIT"])
			access_options.standard = access_object.declaration_symbol
			return access_options
		
		print_deb(T.ACCESS_PATH, ["INHERITED"])
	
	
	var dec_front_type = access_object.declaration_type
	if access_object.declaration_symbol.contains("."):
		dec_front_type = class_obj.get_member_type(dec_front, true)

	var class_obj_to_check = [class_obj]
	
	var current_access_parser = parser.get_parser_and_class_obj_for_script(access_object.declaration_type)
	if current_access_parser:
		class_obj_to_check.append(current_access_parser.class_obj)
	
	for c_obj in class_obj_to_check:
		var dec_front_member_data = c_obj.get_member_data(dec_front, true)
		if dec_front_member_data != null:
			var type = c_obj.get_member_type(dec_front)
			if type != dec_front_type: # not sure about this...
				continue
			var access_path = dec_front_member_data.get(Keys.ACCESS_PATH)
			if to_find_is_current_script:
				access_path = access_path.trim_prefix(class_obj.access_path)
			var full_access_path = UString.dot_joinv([access_path, access_object.declaration_symbol])
			print_deb_err(T.ACCESS_PATH, ["IN MY FIRST CHECK::", full_access_path])
			access_options.standard = full_access_path
			return access_options
	
	
	#^ this works well, but it is slow and a last resort.
	#^ maybe the caller can call it from outside if needed...
	#var search = find_constant_by_value(to_find, class_obj)
	#if search != "":
		#print("SEARCH::", search)
		#access_options.standard = search
		#return access_options
	
	return access_options


## Hardened single-access finder. Same shape as the dual version with no secondary symbol.
func _find_path_to_type_simple_hardened(class_obj:ParserClass, access_object:AccessObject, to_find:String) -> AccessOptions:
	var parser = Utils.ParserRef.get_parser(self)
	print_deb(T.ACCESS_PATH, ["HARDENED OPERATION", "----------------------------------------"])
	print_deb(T.ACCESS_PATH, ["FROM", class_obj.get_script_class_path(), "TO FIND", to_find])
	print_deb(T.ACCESS_PATH, ["DEC", access_object.declaration_symbol, access_object.declaration_type])

	var access_options = AccessOptions.new()
	get_global_name_and_script_alias(to_find, class_obj, access_options) # solid, reused verbatim

	access_options.standard = _resolve_standard_path(class_obj, access_object, to_find, parser)
	return access_options


## Resolve the 'standard' (as-typed) access path to 'to_find'. Tries cheap, type-checked
## candidates first, round-trip verifying each, then falls back to the accurate const-by-value
## search. Returns "" when nothing verifies so the caller can use script_alias/global instead.
## 'to_find' may be an enum (ends with ENUM_SUFFIX) or a bare inner class (no member/suffix).
func _resolve_standard_path(class_obj:ParserClass, access_object:AccessObject, to_find:String, parser, secondary_access:AccessObject=null, secondary_path:String="") -> String:
	var candidates = _gather_standard_candidates(class_obj, access_object, to_find, parser, secondary_access, secondary_path)
	for candidate in candidates:
		if candidate == "":
			continue
		if _standard_candidate_valid(candidate, to_find, class_obj, parser):
			print_deb(T.ACCESS_PATH, ["STANDARD (fast-path)", candidate])
			return candidate

	# Accurate but slower fallback. has_preload matches on the full type path, so the returned
	# const-name chain is canonical by construction (no chain blending, no duplicate segments).
	var search = find_constant_by_value(to_find, class_obj)
	if search != "":
		print_deb(T.ACCESS_PATH, ["STANDARD (const search)", search])
		return search

	print_deb_err(T.ACCESS_PATH, ["STANDARD UNRESOLVED", to_find])
	return ""


## Collect ordered, cheap 'standard' candidates. Each is a single class chain built from one
## ACCESS_PATH source - never a blend of two overlapping chains.
func _gather_standard_candidates(class_obj:ParserClass, access_object:AccessObject, to_find:String, parser, secondary_access:AccessObject, secondary_path:String) -> Array:
	var candidates:Array = []

	var to_find_script_data = Utils.type_path_get_script_data(to_find)
	var to_find_script_path = to_find_script_data[0]
	var to_find_class_path = to_find_script_data[1]
	var to_find_is_current_script = class_obj.main_script_path == to_find_script_path

	var dec_front = UString.get_member_access_front(access_object.declaration_symbol)

	# 0. As-typed verbatim - when the declaration symbol already spells a complete, valid path to
	#    to_find (e.g. "AddonData.AlertType"), prefer it. This both matches what the user typed and
	#    avoids blending it with a member ACCESS_PATH that already contains the same class chain
	#    (the source of the duplicate-segment bug). Verification below rejects it when incomplete.
	candidates.append(access_object.declaration_symbol)

	# 1. Global class prefix - the front is an autoload/global class, symbol is usable verbatim.
	if UClassDetail.get_global_class_path(dec_front) != "":
		candidates.append(access_object.declaration_symbol)

	# 2. self / same-script - reference the enum or inner class relative to the current class.
	if dec_front == "self" and to_find_is_current_script:
		var same_script = to_find.trim_prefix(class_obj.get_script_class_path())
		if same_script == "" and to_find_class_path != "":
			same_script = to_find_class_path.get_file() # inner class, return its name
		candidates.append(same_script)

	# 3. Inherited - the front resolves through an inherited script that owns to_find.
	if class_obj.inherits_script(UString.dot_join(to_find_script_path, to_find_class_path)):
		if class_obj.get_member_data(dec_front, true) != null:
			candidates.append(access_object.declaration_symbol)

	# 4. Directly-typed member - the front is a const/class/enum member of the current class (or
	#    of the class the access object was declared in), whose type matches. Build from that
	#    single member's ACCESS_PATH.
	var dec_front_type = access_object.declaration_type
	if access_object.declaration_symbol.contains("."):
		dec_front_type = class_obj.get_member_type(dec_front, true)

	var class_objs_to_check := [class_obj]
	var access_parser = parser.get_parser_and_class_obj_for_script(access_object.declaration_type)
	if access_parser:
		class_objs_to_check.append(access_parser.class_obj)

	for c_obj in class_objs_to_check:
		if c_obj == null:
			continue
		var member_data = c_obj.get_member_data(dec_front, true)
		if member_data == null:
			continue
		if c_obj.get_member_type(dec_front) != dec_front_type:
			continue
		var access_path = member_data.get(Keys.ACCESS_PATH)
		if to_find_is_current_script:
			access_path = access_path.trim_prefix(class_obj.access_path)
		candidates.append(UString.dot_joinv([access_path, access_object.declaration_symbol]))

	# 5. Dual-access alias - the type comes from a function arg/return defined in another script, so
	#    the secondary access object carries the member path as written there (e.g. "MyEnum",
	#    "T.TimeScale", "NestedClassBase.AnotherNest.NestedNum"). On its own that path doesn't resolve
	#    from the caller, so prefix it with how the caller reached the object's class and let
	#    verification pick the one that truly resolves to to_find (which also disambiguates same-named
	#    inner classes, since resolution runs in the caller's scope).
	if secondary_access != null:
		var sec_sym = secondary_access.declaration_symbol
		var sym_front = UString.get_member_access_front(access_object.declaration_symbol)
		# The candidate order turns on whether the secondary symbol is usable VERBATIM from the caller.
		# That is a reachability question, not a declaration one: an inherited member's arg is spelled in
		# the ancestor's scope, yet a caller that inherits that script can still write it as-typed.
		var secondary_script = Utils.type_path_get_script_data(secondary_path)[0]
		var secondary_in_caller_script = class_obj.main_script_path == secondary_script \
			or class_obj.inherits_script(secondary_script)

		if secondary_in_caller_script:
			# Reachable as-typed: the secondary symbol is written in a scope the caller owns or inherits.
			# Prefer the verbatim secondary; the object-prefixed forms follow only for a within-object
			# member that verbatim can't reach.
			candidates.append(sec_sym)                                       # verbatim first
			if sym_front != access_object.declaration_symbol:
				candidates.append(UString.dot_join(sym_front, sec_sym))     # front prefix (outer-scope members)
			candidates.append(UString.dot_join(access_object.declaration_symbol, sec_sym))  # full-symbol prefix
		else:
			# Out of reach: the arg is written in a foreign script's scope the caller neither owns nor
			# inherits, so it must be reached through the object's path. Front prefix (reaches the
			# object's class at script scope) is
			# tried before the full-symbol prefix so a within-class member falls through to it. The bare
			# verbatim secondary comes LAST - a bare identifier is almost never a valid standalone path
			# from another script's scope, so it only wins when it is already a caller-usable path (a
			# global/preload alias) and the prefixed forms fail verification.
			if sym_front != access_object.declaration_symbol:
				candidates.append(UString.dot_join(sym_front, sec_sym))     # front prefix (outer-scope members)
			candidates.append(UString.dot_join(access_object.declaration_symbol, sec_sym))  # full-symbol prefix
			candidates.append(sec_sym)                                       # secondary verbatim (last resort)

	return candidates


## Verify a candidate path resolves back to 'to_find' from within class_obj's scope.
func _standard_candidate_valid(candidate:String, to_find:String, class_obj:ParserClass, parser) -> bool:
	if candidate == "":
		return false
	var resolved = parser.resolve_expression_to_type(candidate, class_obj.declaration_line)
	return _normalize_type(resolved) == _normalize_type(to_find)


func _normalize_type(type_path:String) -> String:
	return type_path.trim_suffix(Keys.INS_DELIM)


func get_global_name_and_script_alias(to_find:String, class_obj:ParserClass, access_options:AccessOptions):
	var to_find_script_data = GDScriptParser.Utils.type_path_get_script_data(to_find)
	var to_find_script_path = to_find_script_data[0]
	var to_find_class_path = to_find_script_data[1]
	var member_name = Utils.type_path_get_member(to_find)
	var global_name = UClassDetail.get_global_class_name(to_find_script_path)
	if global_name != "":
		access_options.global = AccessUtils.remove_suffixes(UString.dot_joinv([global_name, to_find_class_path, member_name]))
	if access_options.script_alias != "":
		return # early exit if it has been changed, this can be expensive, not sure if this needed now?
	
	var rev_search = reverse_path_chain_search(to_find, class_obj)
	if rev_search != "":
		print_deb(T.ACCESS_PATH, ["SCRIPT ALIAS", "->", rev_search])
		access_options.script_alias = rev_search
		return


func reverse_path_chain_search(to_find:String, class_obj:ParserClass):
	var script_data = Utils.type_path_get_script_data(to_find)
	var script_path = script_data[0]
	var script_access_path = script_data[1]
	var working_script_access_path = script_access_path
	#if to_find.ends_with(ENUM_SUFFIX):
		#script_access_path = UString.dot_join(script_access_path, Utils.type_path_get_member(to_find))
	
	var pc = class_obj.has_preload(to_find)
	if pc != null:
		return pc
	
	var checked_access = ""
	for i in range(script_access_path.count(".") + 1):
		var search_path = UString.dot_join(script_path,working_script_access_path)
		var back = working_script_access_path # i think this would be right vs an empty string
		if working_script_access_path.contains("."):
			back = UString.get_member_access_back(working_script_access_path)
			working_script_access_path = UString.trim_member_access_back(working_script_access_path)
		else:
			working_script_access_path = ""
		
		print_deb(T.ACCESS_PATH, ["WorkingAcess", working_script_access_path])
		print_deb(T.ACCESS_PATH, ["CheckedAccess", checked_access])
		print_deb(T.ACCESS_PATH, ["SEARCHING FOR", search_path])
		var check = class_obj.has_preload(search_path)
		if check != null:
			print_deb(T.ACCESS_PATH, ["FOUND", check, working_script_access_path])
			#if to_find.ends_with(ENUM_SUFFIX):
				#working_script_access_path = UString.dot_join(working_script_access_path, Utils.type_path_get_member(to_find))
			#var return_val = UString.dot_join(check, working_script_access_path)
			
			if to_find.ends_with(ENUM_SUFFIX):
				checked_access = UString.dot_join(checked_access, Utils.type_path_get_member(to_find))
			var return_val = UString.dot_join(check, checked_access)
			print_deb(T.ACCESS_PATH, ["FINAL", return_val])
			return return_val
		
		checked_access = UString.dot_join(back, checked_access)
	
	if to_find.begins_with(class_obj.main_script_path):
		var to_find_script_data = Utils.type_path_get_script_data(to_find)
		var to_find_member = Utils.type_path_get_member(to_find)
		var to_find_access = to_find_script_data[1]
		
		var class_script_data = Utils.type_path_get_script_data(class_obj.get_script_class_path())
		var class_access = class_script_data[1]
		var actual_access = to_find_access
		if to_find_access.begins_with(class_access):
			actual_access = to_find_access.trim_prefix(class_access)
		return UString.dot_join(actual_access, to_find_member)
		
	
	return ""

func find_constant_by_value(type_to_find:String, initial_class_obj:ParserClass):
	#return _find_constant_by_value(type_to_find, initial_class_obj)
	return _find_constant_by_value_bf(type_to_find, initial_class_obj)

func _find_constant_by_value(type_to_find:String, initial_class_obj:ParserClass, current_access:="", recursions=0):
	var t = GDScriptParser.TF.new("_find_constant_by_value")
	if recursions > 3:
		return ""
	
	var gdscript_constants = initial_class_obj.get_gdscript_constants(true)
	for key in gdscript_constants.keys():
		var val = gdscript_constants[key]
		if val == type_to_find:
			var member_data = initial_class_obj.get_member_data(key, true)
			var access_path = member_data.get(Keys.ACCESS_PATH)
			return UString.dot_joinv([current_access, access_path, key])
		elif type_to_find.begins_with(val):
			var stripped = type_to_find.trim_prefix(val)
			if type_to_find.ends_with(ENUM_SUFFIX):
				var member = Utils.type_path_get_member(type_to_find)
				var non_member = Utils.type_path_get_non_member(type_to_find)
				stripped = UString.dot_join(non_member, member)
			return UString.dot_joinv([current_access, key, stripped])
	
	var parser = Utils.ParserRef.get_parser(self)
	
	for key in gdscript_constants.keys():
		if key.ends_with(ENUM_SUFFIX):
			continue
		var next_parser = parser.get_parser_and_class_obj_for_script(gdscript_constants[key])
		if not next_parser:
			continue
		var next_access = UString.dot_join(current_access, key)
		var rec_check = _find_constant_by_value(type_to_find, next_parser.class_obj, next_access, recursions + 1)
		if rec_check != "":
			return rec_check
	
	t.stop()
	return ""

# maybe add a depth param to this? check '.' count and abort if too many slices
# this works good, but it can be slowww
func _find_constant_by_value_bf(type_to_find:String, initial_class_obj:ParserClass):
	var t = GDScriptParser.TF.new("_find_const_bf")
	var parser = Utils.ParserRef.get_parser(self)
	
	var checked = {}
	var queue = [{"class_obj":initial_class_obj, "access": ""}]
	while not queue.is_empty():
		var class_data = queue.pop_front()
		var class_obj = class_data.get("class_obj") as GDScriptParser.ParserClass
		var class_path = class_obj.get_script_class_path()
		if checked.has(class_path):
			continue
		checked[class_path] = true
		var access = class_data.get("access")
		var pc = class_obj.has_preload(type_to_find)
		if pc:
			t.stop()
			return UString.dot_join(access, pc)
		
		var gdscript_constants = class_obj.get_gdscript_constants(true)
		for key in gdscript_constants.keys():
			var val = gdscript_constants[key]
			if val.ends_with(ENUM_SUFFIX):
				continue
			if checked.has(val):
				print_deb(T.FIND_BY_VAL, ["ALREADY CHECKED", class_path, val])
				continue
			var next_parser = parser.get_parser_and_class_obj_for_script(gdscript_constants[key])
			if not next_parser:
				continue
			var next_class = next_parser.class_obj as GDScriptParser.ParserClass
			if checked.has(next_class.get_script_class_path()):
				print_deb(T.FIND_BY_VAL, ["SECOND CHECK, IS THIS NEEDED", val])
				continue
			queue.append({
				"class_obj": next_class,
				"access": UString.dot_join(access, key)
			})
	t.stop()
	return ""


class AccessOptions:
	var standard:String
	var script_alias:String
	var global:String


class AccessObject:
	var declaration_type:String
	var declaration_symbol:String
	
	func clean_symbols():
		declaration_type = declaration_type.trim_suffix(Keys.INS_DELIM)
		declaration_symbol = AccessUtils.clean_path(declaration_symbol)
	
class AccessUtils:
	
	static func clean_path(string:String):
		string = string.trim_prefix("self").trim_suffix("self").trim_prefix(".").trim_suffix(".")
		if string.find(".new(") > -1:
			string = string.substr(0, string.find(".new("))
		string = string.trim_suffix(Keys.INS_DELIM)
		return remove_suffixes(string)
	
	static func remove_suffixes(string:String):
		for suffix in SUFFIXES:
			if string.ends_with(suffix):
				string = string.trim_suffix(suffix)
		string = string.trim_suffix(Keys.INS_DELIM)
		return string


const PrintDebug = preload("uid://d1ki8cxxh7lvb") #! resolve ALibEditor.PrintDebug
#! arg_location section:T
static func print_deb(section:String, msg:Array):
	if not PRINT_DEBUG:
		return
	if section in _PRINT:
		msg.push_front(section)
		PrintDebug.print(msg)

#! arg_location section:T
static func print_deb_err(section:String, msg:Array):
	if not PRINT_DEBUG:
		return
	if section in _PRINT:
		msg.push_front(section)
		PrintDebug.print_err(msg)

const _PRINT = [
	#T.ACCESS_PATH,
	#T.FIND_BY_VAL,
	]


class T:
	const ACCESS_PATH = "ACCESS PATH"
	const FIND_BY_VAL = "FIND_BY_VAL"
	pass
