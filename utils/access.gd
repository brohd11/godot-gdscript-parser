
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


## Find path to 'to_find' from current class. current_access is the current_script symbol used to access the type. secondary_access is from the script where the
## function or var is defined. Secondary path is that script path.
func find_path_to_type(class_obj:ParserClass, current_access:AccessObject, secondary_access:AccessObject, to_find:String, secondary_path:String):
	var result = _find_path_to_type(class_obj, current_access, secondary_access, to_find, secondary_path)
	# ensure no suffixes, or self prefix
	result.standard = AccessUtils.clean_path(result.standard)
	result.script_alias = AccessUtils.clean_path(result.script_alias)
	result.global = AccessUtils.clean_path(result.global)
	return result

func _find_path_to_type(class_obj:ParserClass, current_access:AccessObject, secondary_access:AccessObject, to_find:String, secondary_path:String):
	if secondary_access == null or current_access == secondary_access: # if no valid argument access or is our main object, can just do the operation func
		return _find_path_to_type_simple(class_obj, current_access, to_find)
	
	var current_script_path = class_obj.main_script_path
	print_deb(T.ACCESS_PATH, "FUNCTION", "----------------------------------------")
	print_deb(T.ACCESS_PATH,"FROM", current_script_path, "TO FIND",to_find)
	
	print_deb(T.ACCESS_PATH, "DEC",  current_access.declaration_symbol, current_access.declaration_type)
	print_deb(T.ACCESS_PATH, "ACCESS", current_access.access_symbol, current_access.access_type)
	print_deb(T.ACCESS_PATH, "DEC-SEC",  secondary_access.declaration_symbol, secondary_access.declaration_type)
	print_deb(T.ACCESS_PATH, "ACCESS-SEC", secondary_access.access_symbol, secondary_access.access_type)
	print_deb(T.ACCESS_PATH, "FUNCTION", secondary_path)
	
	current_access.clean_symbols()
	secondary_access.clean_symbols()
	
	var access_options = AccessOptions.new()
	# get global name and script alias are easy to run
	get_global_name_and_script_alias(to_find, class_obj, access_options)
	
	# script where func or var is, this may or may not be the current script
	#var secondary_script_data = UString.get_script_path_and_suffix(secondary_path)
	var secondary_script_data = Utils.type_path_get_script_data(secondary_path)
	var secondary_script_path = secondary_script_data[0]
	
	#var to_find_script_data = UString.get_script_path_and_suffix(to_find) # same logic as above
	var to_find_script_data = Utils.type_path_get_script_data(to_find) # same logic as above
	var to_find_script_path = to_find_script_data[0]
	var to_find_script = load(to_find_script_path) as GDScript
	var to_find_class_path = to_find_script_data[1].trim_suffix(ENUM_SUFFIX) # trim suffix here? should not be needed after since we knew it going in
	print("TO FIND CLASS::FUNC::", to_find_class_path)
	#if to_find.ends_with(ENUM_SUFFIX):
		#to_find_class_path = UString.dot_join(to_find_class_path, Utils.type_path_get_member(to_find))
		#print("TO FIND CLASS::FUNC::", to_find_class_path)
	
	
	
	#var access_script_data = UString.get_script_path_and_suffix(current_access.access_type) # same logic as above
	var access_script_data = Utils.type_path_get_script_data(current_access.access_type) # same logic as above
	if access_script_data.is_empty(): # should not happen any more, any object that does not have script will become 'self', however this is valid
		return _find_path_to_type_simple(class_obj, secondary_access, to_find) # since the function would still be similar to how this would be handle 
	
	var access_script_path = access_script_data[0]
	#var access_script = load(access_script_path) as GDScript
	#var access_class_path = access_script_data[1].trim_suffix(ENUM_SUFFIX) # don't need for a search by val
	
	#var declaration_script_data = UString.get_script_path_and_suffix(current_access.declaration_type) # same logic as above
	var declaration_script_data = Utils.type_path_get_script_data(current_access.declaration_type) # same logic as above
	var declaration_script_path = declaration_script_data[0]
	var declaration_class_path = declaration_script_data[1]
	
	var parser = Utils.ParserRef.get_parser(self)
	
	# TEST #^ this seems to better check for  inheritance, but it does negatively affect some of the name finding.
	#^ Secondary access may not be used in certain situations ie. e:MyEnum in the test_comp.gd inner classes portion
	#^ that being said, that example is not resolving fully anyway, so it is a side grade maybe. it should give MyEnum but gives: IC.MyEnum
	#var to_find_has_suffix = to_find.ends_with(ENUM_SUFFIX)
	#var inherit_check_path = to_find
	#if to_find_has_suffix:
		#inherit_check_path = UString.trim_member_access_back(inherit_check_path)
	#var inherits = parser.script_inherits(class_obj.get_script_class_path(), inherit_check_path)
	#print_deb(T.ACCESS_PATH, class_obj.get_script_class_path() ,"INHERITS", inherit_check_path, inherits)
	#if not inherits:
		#inherits = parser.script_inherits(class_obj.get_script_class_path(), to_find_script_path)
	#print_deb(T.ACCESS_PATH, class_obj.get_script_class_path() ,"INHERITS CHECK 2", to_find_script_path, inherits)
	
	#^r ORIGINAL METHOD
	#var inherits = parser.script_inherits(current_script_path, to_find_script_path)
	# should this factor in the inner classes, probably so...
	var inherits = parser.script_inherits(class_obj.get_script_class_path(), Utils.type_path_get_non_member(to_find))
	#print("INHERITES::", inherits, "::",class_obj.get_script_class_path(),"::", Utils.type_path_get_non_member(to_find) )
	
	# if current script is relevant, can simplify process. if to find is in current or external is current
	if current_script_path == to_find_script_path or current_script_path == secondary_script_path or inherits:
		# if current script has the declaration symbol, we are good. This function automatically splits member access parts
		if class_has_const(secondary_access.declaration_symbol, class_obj) and secondary_access.declaration_type == to_find:
			access_options.standard = secondary_access.declaration_symbol
			return access_options
		elif class_has_const(current_access.access_symbol, class_obj):
			# check direct for to find in access script, this doesn't seem to be affecting any thing negatively
			# how does this affect the below search?
			print("HERE::",access_script_path,"::", to_find)
			var to_find_search = get_member_by_value(access_script_path, to_find)
			if to_find_search != null:
				print("HERE::", to_find_search)
				access_options.standard = to_find_search
				return access_options
			# if it has the access symbol, can check for a path to declaration symbol
			var search = get_member_by_value(access_script_path, secondary_access.declaration_type)
			print_deb(T.ACCESS_PATH, "HAS ACCESS", "SEARCH", search)
			if search != null: # if it does, can safely use the path, otherwise defer to simple logic
				access_options.standard = UString.dot_join(current_access.access_symbol, secondary_access.declaration_symbol)
				return access_options
		
		print_deb(T.ACCESS_PATH, "FUNC -> OPERATION") # possibly this should be only for script == external object? to find seems to work fine though
		return _find_path_to_type_simple(class_obj, secondary_access, to_find) # since we are in the external object it should be safe to use it 
	
	# new check, if declaration type is to_find type, should be simple find procedure
	# this is needed for when a const is a global chain to preload, not when an explicit preload
	if declaration_script_path == to_find_script_path:
		var to_find_search = get_member_by_value(declaration_script_path, to_find)
		if to_find_search != null:
			print_deb(T.ACCESS_PATH, "BREAKPOINT_0", to_find_search)
			access_options.standard = UString.dot_joinv([current_access.declaration_symbol, secondary_access.declaration_symbol, to_find_search])
			#access_options.standard = UString.dot_join(current_access.declaration_symbol, secondary_access.declaration_symbol)
			return access_options
	
	
	# secondary external to current script and primary access object.
	if secondary_script_path != access_script_path:
		# attempt to find a path from the declaration in current script to the secondary script
		var dec_to_sec_path = get_member_by_value(declaration_script_path, secondary_script_path)
		if dec_to_sec_path != null: # if found, can extend the path from declaration symbol to the secondary symbol
			print_deb(T.ACCESS_PATH, "FUNCTION OUT OF ACCESS SCRIPT, FOUND DEC PATH", dec_to_sec_path)
			access_options.standard = UString.dot_joinv([current_access.declaration_symbol, dec_to_sec_path, secondary_access.declaration_symbol])
			return access_options
		
		
		
		# attempt the same with the access symbol
		var access_to_sec_path = get_member_by_value(access_script_path, secondary_script_path)
		print_deb(T.ACCESS_PATH, "SECONDARY NOT ACCESS SCRIPT", "PATH TO", access_to_sec_path)
		if access_to_sec_path != null: # if found, can extend the path from access symbol to the secondary symbol
			print_deb(T.ACCESS_PATH, "SECONDARY OUT OF ACCESS SCRIPT, BUT FOUND PATH")
			var class_access = _find_constant_relative_path(secondary_path, secondary_access.declaration_symbol)
			if class_access != null:
				access_options.standard = UString.dot_joinv([current_access.access_symbol, access_to_sec_path, class_access, secondary_access.declaration_symbol])
			return access_options
		else: # can not reach this from here, can attempt a global or abort, a valid global would be there already if possible
			var to_find_global_name = to_find_script.get_global_name()
			if to_find_global_name != "": # if yes, set it, if not, there is not much left we can do. return the options without a standard path
				var class_access = _find_constant_relative_path(secondary_path, secondary_access.declaration_symbol)
				if class_access != null:
					access_options.standard = UString.dot_joinv([to_find_global_name, class_access, secondary_access.declaration_symbol])
			
			print_deb(T.ACCESS_PATH, "SECONDARY OUT OF ACCESS SCRIPT, NO PATH", access_options.standard)
			return access_options
	
	
	print_deb(T.ACCESS_PATH, "SECONDARY IS ACCESS SCRIPT")
	# access script is the secondary script at this point
	# check id the declaration exists in the current file and at what scope. inner classes can use const in the root for example
	var declaration_access = _find_constant_relative_path(access_script_path, secondary_access.declaration_symbol)
	print_deb(T.ACCESS_PATH, "DECLARATION ACCESS", declaration_access)
	if declaration_access != null: # if found, we can extend access to the declaration. #^r should this be from the secondary access to dec? Seems to work as is
		access_options.standard = UString.dot_joinv([current_access.declaration_symbol, declaration_access, secondary_access.declaration_symbol])
		return access_options
	else:
		print_deb(T.ACCESS_PATH, "ACCESS SCRIPT COULD NOT FIND CLASS ACCESS")
	
	# if declaration has global name, use it
	var front_dec = UString.get_member_access_front(secondary_access.declaration_symbol)
	if UClassDetail.get_global_class_path(front_dec) != "":
		print_deb(T.ACCESS_PATH, "ARG IS GLOBAL", front_dec)
		var declaration_suffix = "" # if the declation script is to_find or inherits, trim the class access in case of inner classes
		if to_find_script_path.begins_with(declaration_script_path) or parser.script_inherits(declaration_script_path, to_find_script_path):
			declaration_suffix = AccessUtils.remove_suffixes(to_find_class_path.trim_prefix(declaration_class_path).trim_prefix("."))
			print_deb(T.ACCESS_PATH, "DEC SUFFIX", declaration_suffix)
		
		access_options.standard = UString.dot_joinv([secondary_access.declaration_symbol, declaration_suffix])
		return access_options
	
	# last check, search class and it's preloads for to_find. This is a recursive search
	var access_to_find_path = get_member_by_value(access_script_path, to_find)
	if access_to_find_path != null:
		print_deb(T.ACCESS_PATH, "FINAL GET BY VAL", access_to_find_path)
		if access_to_find_path.begins_with(current_access.declaration_symbol):
			print_deb(T.ACCESS_PATH, "FINAL GET BY VAL::BEGINS WITH DEC", access_to_find_path)
			# this is a naive trim. No guarentee that it is the correct path.
			access_to_find_path = access_to_find_path.trim_prefix(current_access.declaration_symbol).trim_prefix(".")
		
		access_options.standard = UString.dot_joinv([current_access.declaration_symbol, access_to_find_path]) # ORIGINAL
		#TEST # is this the correct way?
		#access_options.standard = access_to_find_path
		#TEST
		return access_options
	
	# nothing found, return no standard
	print_deb(T.ACCESS_PATH, "END OF FUNC")
	return access_options

func find_path_to_type_simple(class_obj:ParserClass, access_object:AccessObject, to_find:String):
	var result = _find_path_to_type_simple(class_obj, access_object, to_find)
	# ensure no suffixes, or self prefix
	result.standard = AccessUtils.clean_path(result.standard)
	result.script_alias = AccessUtils.clean_path(result.script_alias)
	result.global = AccessUtils.clean_path(result.global)
	return result

func _find_path_to_type_simple(class_obj:ParserClass, access_object:AccessObject, to_find:String):
	var parser = Utils.ParserRef.get_parser(self)
	var current_script_path = class_obj.main_script_path
	print_deb(T.ACCESS_PATH, "OPERATION", "----------------------------------------")
	print_deb(T.ACCESS_PATH,"FROM", class_obj.get_script_class_path(), "TO FIND",to_find)
	
	var access_options = AccessOptions.new()
	get_global_name_and_script_alias(to_find, class_obj, access_options)
	
	#var to_find_script_data = UString.get_script_path_and_suffix(to_find)
	var to_find_script_data = Utils.type_path_get_script_data(to_find)
	var to_find_script_path = to_find_script_data[0]
	#var to_find_script = load(to_find_script_path) as GDScript
	var to_find_class_path = to_find_script_data[1].trim_suffix(ENUM_SUFFIX) # trim suffix here? should not be needed after since we knew it going in
	print("TO FIND CLASS::", to_find_class_path)
	#if to_find.ends_with(ENUM_SUFFIX):
		#to_find_class_path = UString.dot_join(to_find_class_path, Utils.type_path_get_member(to_find))
		#print("TO FIND CLASS::", to_find_class_path)
	
	#var access_script_data = UString.get_script_path_and_suffix(access_object.access_type)
	var access_script_data = Utils.type_path_get_script_data(access_object.access_type)
	var access_script_path = access_script_data[0] # get script of access object resolved type
	#var access_script = load(access_script_path) as GDScript
	#var access_class_path = access_script_data[1].trim_suffix(ENUM_SUFFIX)
	
	print_deb(T.ACCESS_PATH, "DEC",  access_object.declaration_symbol, access_object.declaration_type)
	print_deb(T.ACCESS_PATH, "ACCESS", access_object.access_symbol, access_object.access_type)
	
	access_object.clean_symbols()
	
	# TEST #^ note: see above func
	#var to_find_has_suffix = to_find.ends_with(ENUM_SUFFIX)
	#var inherit_check_path = to_find
	#if to_find_has_suffix:
		#inherit_check_path = UString.trim_member_access_back(inherit_check_path)
	#var inherits = parser.script_inherits(class_obj.get_script_class_path(), inherit_check_path)
	#print_deb(T.ACCESS_PATH, class_obj.get_script_class_path() ,"INHERITS", inherit_check_path, inherits)
	#if not inherits:
		#inherits = parser.script_inherits(class_obj.get_script_class_path(), to_find_script_path)
	#print_deb(T.ACCESS_PATH, class_obj.get_script_class_path() ,"INHERITS CHECK 2", to_find_script_path, inherits)
	
	
	
	#^r ORIGINAL METHOD
	#var inherits = parser.script_inherits(current_script_path, to_find_script_path)
	var inherits = parser.script_inherits(class_obj.get_script_class_path(), Utils.type_path_get_non_member(to_find))
	
	# if current script is to find or inherits, should be simple to get access
	if current_script_path == to_find_script_path or inherits:# or current_script_path == access_script_path:
		# if it has the declaration symbol, use it. This would be if it has been redefined in another const
		if class_has_const(access_object.declaration_symbol, class_obj) and access_object.declaration_type == to_find:
			access_options.standard = access_object.declaration_symbol
		else: # if not just use the script class path
			access_options.standard = to_find_class_path
		return access_options
	
	#var declaration_script_data = UString.get_script_path_and_suffix(access_object.declaration_type)
	var declaration_script_data = Utils.type_path_get_script_data(access_object.declaration_type)
	var declaration_script_path = declaration_script_data[0]
	var declaration_class_path = declaration_script_data[1].trim_suffix(ENUM_SUFFIX)
	
	# to find not in current script, need to use access object
	if class_has_const(access_object.declaration_symbol, class_obj):
		# if class has declaration symbol, check if declaration is to_find
		if declaration_script_path == to_find_script_path: # trim class path in case we are in inner class
			var trimmed_path = to_find_class_path.trim_prefix(declaration_class_path).trim_prefix(".")
			access_options.standard = UString.dot_joinv([access_object.declaration_symbol, trimmed_path])
			print_deb(T.ACCESS_PATH, "HAS CONST AND DEC == TO FIND")
			return access_options
		
		print_deb(T.ACCESS_PATH, "HAS CONST")
		# attempt to find it within the declaration script
		var path_to_type = get_member_by_value(declaration_script_data[0], to_find)
		print_deb(T.ACCESS_PATH, "HAS CONST", "PATH TO TPYE", path_to_type)
		if path_to_type != null: # if found, return dec to path found
			access_options.standard = UString.dot_joinv([access_object.declaration_symbol, path_to_type])
			return access_options
		
		print_deb(T.ACCESS_PATH, "HAS CONST NO RESOLUTION")
	
	# attempt another search from the access script
	var to_find_access_path = get_member_by_value(access_script_path, to_find)
	if to_find_access_path != null:
		print_deb(T.ACCESS_PATH, "TO FIND IN ACCESS PATH", to_find_access_path)
		access_options.standard = UString.dot_joinv([access_object.access_symbol, to_find_access_path])
		return access_options
	else:
		print_deb(T.ACCESS_PATH, "COULD NOT FIND TO FIND IN ACCESS SCRIPT")
	
	
	
	if access_script_path == to_find_script_path:
		# if access script is the to find, make sure access path is correct
		var declaration_access = _find_constant_relative_path(access_script_path, access_object.declaration_symbol)
		if declaration_access != null:
			#^r not sure about this, why is declaration twice? Thinking this doesn't trigger much
			#^r on that note, this seems like it would make sense above the search from the access script.
			#^r perhaps that is why this never triggers? it is already being caught above
			printerr("access.gd - ln:214 - ACCESS == TO FIND, DOES THIS TRIGGER")
			access_options.standard = UString.dot_joinv([access_object.declaration_symbol, declaration_access, access_object.declaration_symbol])
			return access_options
		else:
			print_deb(T.ACCESS_PATH, "ACCESS SCRIPT COULD NOT FIND CLASS ACCESS")
		
		# attempt to find a global name
		var front_dec = UString.get_member_access_front(access_object.declaration_symbol)
		if UClassDetail.get_global_class_path(front_dec) != "": # this can fail easily
			access_options.standard = access_object.declaration_symbol
			return access_options
	
	# nothing found, return without standard path
	print_deb(T.ACCESS_PATH, "END OF OP")
	return access_options



func _find_constant_relative_path(full_script_path:String, member_to_find:String):
	var parser_find = parser_search_for_member(full_script_path, member_to_find)
	var rev_find = reverse_search_for_member(full_script_path, member_to_find)
	print_deb(T.ACCESS_PATH, "FWD SEARCH",member_to_find, "IN", full_script_path.get_file(), "PARSER FIND", parser_find, "REV FIND", rev_find, "EQUAL", parser_find == rev_find)
	return parser_find


func reverse_search_for_member(full_script_path:String, to_find:String):
	var t = ALibRuntime.Utils.UProfile.TimeFunction.new("REV")
	#var script_data = UString.get_script_path_and_suffix(full_script_path)
	var script_data = Utils.type_path_get_script_data(full_script_path)
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

# this one uses parser, access path is cached
func parser_search_for_member(full_script_path:String, to_find:String):
	#var script_data = UString.get_script_path_and_suffix(full_script_path)
	var script_data = Utils.type_path_get_script_data(full_script_path)
	var script_path = script_data[0]
	var script_parser = _get_parser_for_script(script_path)
	var class_access = script_data[1] as String
	var class_obj = script_parser.get_class_object(class_access) as ParserClass
	var front = UString.get_member_access_front(to_find)
	if front != to_find:
		print_deb(T.ACCESS_PATH, "SEARCH FOR MEMBER FRONT NOT FULL", to_find)
	var constant_data = class_obj.get_constant_or_class(front)
	if constant_data == null:
		constant_data = class_obj.get_inherited_member(front)
	if constant_data == null:
		return null
	return constant_data.get(Keys.ACCESS_PATH)


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
			if Utils.is_absolute_path(type):
			#if type.begins_with("res://"):
				var remaining_parts = ""
				for ni in range(i + 1, path_parts.size()):
					remaining_parts = UString.dot_join(remaining_parts, path_parts[ni])
				#var script_data = UString.get_script_path_and_suffix(type)
				var script_data = Utils.type_path_get_script_data(type)
				var next_parser = _get_parser_for_script(script_data[0])
				remaining_parts = UString.dot_join(script_data[1], remaining_parts)
				print("RECURSIVE::", remaining_parts, " -> ", script_data[0])
				return next_parser.get_type_lookup()._parser_has_path(remaining_parts, next_parser)
		else:
			return false # think any other should just be false
	return false



func get_member_by_value(script_path:String, full_to_find_path:String):
	print_deb(T.ACCESS_PATH, "FIND BY VAL", script_path, "->", full_to_find_path)
	#var to_find_script_data = UString.get_script_path_and_suffix(full_to_find_path)
	var to_find_script_data = Utils.type_path_get_script_data(full_to_find_path)
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
		t.stop("_find_constant_by_value - found pre::" + preload_name)
		return UString.dot_join(initial_class_obj.access_path, preload_name)
	
	var search_from_script = initial_class_obj.get_script_resource()
	
	var search_value = type_to_find
	
	#var script_data = UString.get_script_path_and_suffix(search_value)
	var script_data = GDScriptParser.Utils.type_path_get_script_data(search_value)
	var script_path = script_data[0]
	var script_class_path = script_data[1]
	var suffix = ""
	if type_to_find.ends_with(ENUM_SUFFIX):
		suffix = Utils.type_path_get_member(type_to_find)
	
	print_deb(T.ACCESS_PATH, "SEARCH", script_class_path, suffix)
	
	var search_script = load(script_path)
	if script_class_path != "":
		search_script = UClassDetail.get_member_info_by_path(search_script, script_class_path, ["const"], false, false, false, false)
	
	print_deb(T.ACCESS_PATH, "SEARCH, ", search_from_script, search_script, "TO FIND", type_to_find)
	var access = UClassDetail.script_get_member_by_value(search_from_script, search_script, true, ["const", "enum"])
	if access != null:
		var parser = _get_parser_for_script(script_path)
		var class_obj = parser.get_class_object(script_class_path)
		if search_value != type_to_find: # if we modified the search value, check if the type exists where we found it, for enums and such
			if class_obj.has_preload(type_to_find):
				t.stop("_find_constant_by_value - search val == type")
				return UString.dot_join(access, suffix)
		else:
			t.stop("_find_constant_by_value - search val != type")
			return UString.dot_join(access, suffix)
	
	t.stop("_find_constant_by_value - fail")
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
	
	
	for i in range(script_access_path.count(".") + 1):
		var search_path = UString.dot_join(script_path,working_script_access_path)
		if working_script_access_path.contains("."):
			working_script_access_path = UString.trim_member_access_back(working_script_access_path)
		else:
			working_script_access_path = ""
		print("CHECKING::", search_path)
		var check = class_obj.has_preload(search_path)
		if check != null:
			print("FOUND::", check, "::", working_script_access_path)
			if to_find.ends_with(ENUM_SUFFIX):
				working_script_access_path = UString.dot_join(working_script_access_path, Utils.type_path_get_member(to_find))
			var return_val = UString.dot_join(check, working_script_access_path)
			print("FINAL::", return_val)
			return return_val
		#if working_script_access_path.contains("."):
			#working_script_access_path = UString.trim_member_access_back(working_script_access_path)
		#else:
			#working_script_access_path = ""
	return ""

func class_has_const(symbol:String, class_obj:ParserClass):
	var front_arg_dec = UString.get_member_access_front(symbol)
	var member_data = class_obj.get_member(front_arg_dec)
	if member_data == null:
		member_data = class_obj.get_inherited_member(front_arg_dec)
	if member_data != null:
		var member_type = member_data.get(Keys.MEMBER_TYPE)
		if Utils.member_is_const_class_enum(member_type):
			return true
	return false


func get_global_name_and_script_alias(to_find:String, class_obj:ParserClass, access_options:AccessOptions):
	var to_find_script_data = GDScriptParser.Utils.type_path_get_script_data(to_find)
	var to_find_script = load(to_find_script_data[0]) as GDScript
	var to_find_class_path = to_find_script_data[1]
	var member_name = Utils.type_path_get_member(to_find)
	
	if to_find_script.get_global_name() != "":
		access_options.global = AccessUtils.remove_suffixes(UString.dot_joinv([to_find_script.get_global_name(), to_find_class_path, member_name]))
	if access_options.script_alias != "":
		return # early exit if it has been changed, this can be expensive, not sure if this needed now?
	
	var rev_search = reverse_path_chain_search(to_find, class_obj)
	if rev_search != "":
		print_deb(T.ACCESS_PATH, "reverse_path_chain_search", "->", rev_search)
		access_options.script_alias = rev_search
		return
	
	#^ think the above super sedes this
	#var preloaded_name = class_obj.has_preload(to_find)
	#if preloaded_name != null:
		#access_options.script_alias = remove_suffixes(preloaded_name)
	#else: # if the type is not directly found, check if the script or class can be found
		#if to_find_class_path.contains("."): #^r this should maybe be an empty string check, as it is, only inner classes will be checked for, not the script
			##preloaded_name = class_obj.has_preload(UString.trim_member_access_back(to_find))
			#preloaded_name = class_obj.has_preload(to_find)
			#if preloaded_name != null:
				#access_options.script_alias = remove_suffixes(UString.dot_join(preloaded_name, member_name))
				##var back = UString.get_member_access_back(to_find)
				##access_options.script_alias = remove_suffixes(UString.dot_join(preloaded_name, back))



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
	var declaration_access_path:String
	var access_type:String
	var access_symbol:String
	
	func clean_symbols():
		declaration_symbol = AccessUtils.clean_path(declaration_symbol)
		access_symbol = AccessUtils.clean_path(access_symbol)
	
class AccessUtils:
	
	static func clean_path(string:String):
		string = string.trim_prefix("self").trim_suffix("self").trim_prefix(".").trim_suffix(".")
		if string.find(".new(") > -1:
			string = string.substr(0, string.find(".new("))
		return remove_suffixes(string)
	
	static func remove_suffixes(string:String):
		for suffix in SUFFIXES:
			if string.ends_with(suffix):
				string = string.trim_suffix(suffix)
		return string

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

#func t():
	#print_deb(T.ACCESS_PATH)


class T:
	const RESOLVE = "RESOLVE"
	const BUILTIN = "BUILTIN"
	const INHERITED = "INHERITED"
	const VAR_TO_CONST = "VAR TO CONST"
	const ACCESS_PATH = "ACCESS PATH"
