
const GlobalChecker = preload("res://addons/addon_lib/brohd/alib_runtime/misc/global_checker.gd")
const VariantChecker = preload("res://addons/addon_lib/brohd/alib_runtime/misc/variant_checker.gd")


const GDScriptParser = preload("res://addons/addon_lib/brohd/alib_runtime/utils/resource/gdscript/parser/gdscript_parser.gd")
const ParserClass = GDScriptParser.ParserClass
const ParserFunc = GDScriptParser.ParserFunc
const Utils = GDScriptParser.Utils
const Keys = Utils.Keys
const UString = GDScriptParser.UString
const UFile = GDScriptParser.UFile
const UClassDetail = GDScriptParser.UClassDetail

const PLUGIN_EXPORTED = false
const PRINT_DEBUG = true # not PLUGIN_EXPORTED


var _parser:WeakRef
var code_edit:CodeEdit

var create_non_script_parsers:=true
#var _resolve_to_script:=false


func _get_parser() -> GDScriptParser:
	return _parser.get_ref()

func _get_code_edit_parser() -> GDScriptParser.CodeEditParser:
	return _get_parser().code_edit_parser

func _get_parser_main_script():
	return Utils.ParserRef.get_parser(self).get_current_script()



#region Var Lookup

func get_function_data(identifier, class_obj:ParserClass, _line:int=-1):
	var stripped_identifier = identifier
	if identifier.find(".") == -1:
		if identifier.find("(") > -1:
			stripped_identifier = identifier.substr(0, identifier.find("("))
		var func_obj = class_obj.get_function(identifier) as ParserFunc
		if is_instance_valid(func_obj):
			return func_obj.get_function_data()
		var inherited_script = _find_member_inheriting_script(stripped_identifier, class_obj.script_resource)
		if inherited_script != "": # this needs to account for inner classes
			var script = load(inherited_script)
			var parser = _get_parser_for_script(script)
			return parser.get_function_data(identifier)
	else:
		var string_map = UString.get_string_map(identifier)
		var access = UString.trim_member_access_back(identifier, string_map)
		var method_name = UString.get_member_access_back(identifier, string_map)
		var calling_script = get_chain_type(access, class_obj, {})
		if calling_script != "": # need to account for access path?
			var script_data = UString.get_script_path_and_suffix(calling_script)
			var script = load(script_data[0])
			var parser = _get_parser_for_script(script)
			var nested_class_obj = parser.get_class_object(script_data[1])
			var func_data = get_function_data(method_name, nested_class_obj)
			var func_args = func_data.get(Keys.FUNC_ARGS)
			for name in func_args.keys():
				var arg_data = func_args[name]
				var type = arg_data.get(Keys.TYPE, "")
				if type == "" or _valid_identifier(type):
					continue
				arg_data[Keys.TYPE_RESOLVED] = parser.get_identifier_type(type)
			print("FUNC DATA::", func_data)
			return func_data
		
	
	return {}



func resolve_identifier_to_global(identifier:String, class_obj:ParserClass, line:int=-1):
	if _valid_identifier(identifier, true):
		return identifier
	if line == -1:
		line = class_obj.line_indexes[0]
	
	var t= ALibRuntime.Utils.UProfile.TimeFunction.new("NEW LOOKUP")
	
	if identifier == "self":
		return class_obj.get_script_resource().resource_path
	elif identifier.begins_with("self"):
		identifier = identifier.trim_prefix("self").trim_prefix(".")
	
	var local_vars:Dictionary = {}
	var function_name = class_obj.get_function_at_line(line)
	if function_name != Keys.CLASS_BODY:
		var func_obj:ParserFunc = class_obj.get_function(function_name)
		if is_instance_valid(func_obj):
			local_vars = func_obj.get_in_scope_local_vars(line)
			#print("LOCAL vars: ", local_vars.keys())
	
	var result = get_chain_type(identifier, class_obj, local_vars, true)
	t.stop()
	return result
	


## Get var type of member string. Break into parts then process if needed.
## ie. my_class.some_var.my_func() will have [method _get_var_type] ran on the first part, "my_class".
## The rest will be added to the string and checked that it has property info.

func get_indentifier_type(identifier:String, class_obj:ParserClass, line:int=-1):
	if _valid_identifier(identifier):
		return identifier
	
	if line == -1:
		line = class_obj.line_indexes[0]
	
	var t= ALibRuntime.Utils.UProfile.TimeFunction.new("NEW LOOKUP")
	
	if identifier == "self":
		return class_obj.get_script_resource().resource_path
	elif identifier.begins_with("self"):
		identifier = identifier.trim_prefix("self").trim_prefix(".")
	
	var local_vars:Dictionary = {}
	var function_name = class_obj.get_function_at_line(line)
	if function_name != Keys.CLASS_BODY:
		var func_obj:ParserFunc = class_obj.get_function(function_name)
		if is_instance_valid(func_obj):
			local_vars = func_obj.get_in_scope_local_vars(line)
			#print("LOCAL vars: ", local_vars.keys())
	
	var result = get_chain_type(identifier, class_obj, local_vars)
	t.stop()
	return result

#^r NOTE:: REMOVED LINE_INDEX ARG FROM THIS, SEEMS TO DO NOTHING
func get_chain_type(expression: String, initial_class_obj: ParserClass, local_vars:Dictionary, allow_global:=false, recursions:int=0) -> String:
	if recursions >= 10:
		return expression
	
	var parser = _get_parser()
	var main_script = parser.get_current_script()
	var main_script_path = main_script.resource_path
	
	if expression == "self": # if self, we can just return the path to the class
		return UString.dot_join(main_script_path, initial_class_obj.access_path)
	elif expression.begins_with("self"):
		expression = expression.trim_prefix("self").trim_prefix(".")
	
	var string_map = parser.get_string_map(expression)
	var parts: Array = UString.split_member_access(expression, string_map)
	
	var current_type_path = "" # main_script_path # this can't be the current path because it defaults to that, need workaround
	
	var current_script_path = main_script_path
	var current_script = main_script # GDScript Resource
	var current_part_in_script = true
	
	var current_class_obj:ParserClass = initial_class_obj
	print("START:%s - %s ----------" % [recursions, expression])
	print(parts)
	#return current_type_path
	var count = 0
	while parts.size() > 0 and count < 10:
		count += 1
		var current_part: String = parts.pop_front()
		var is_func = current_part.find("(") != -1
		var identifier = current_part.split("(", false, 1)[0] if is_func else current_part
		var resolved_type = ""
		print("CYCLE &*&*&*&*&*&*&*&")
		#^ --- IN SCRIPT ---
		print("CHECK::", identifier)
		if current_part_in_script:
			prints("IN_SCRIPT::",identifier, current_class_obj.access_path, " in ", main_script_path)
			print(local_vars)
			if member_in_class_or_local_vars(identifier, current_class_obj, local_vars):
				print("CLASS OR LOCAL")
				resolved_type = _process_in_script_data(identifier, current_class_obj, local_vars)
			else:# pass through current part so that you can get full context
				print("NON SCRIPT") # why am i not passing the stripped func? for args think, think dictionary.get() to infer default
				resolved_type = _process_non_script_class_member(current_part, current_type_path, current_class_obj, local_vars)
			
			
			# 3. Check Globals / Autoloads (if applicable)
			if resolved_type == "":
				print("ATTEMPT GLOBAL::", identifier)
				resolved_type = UClassDetail.get_global_class_path(identifier) # YOUR IMPLEMENTATION
			
			print("BASE ID: ", resolved_type)
			print(".".join(parts))
		else: #^ --- OUTSIDE SCRIPT ---
			if current_type_path.begins_with("res://"):
				resolved_type = _process_external_identifier(identifier, current_script)
				
				print("OUTSIDE ", resolved_type)
				
			else: # --- BUILT-IN C++ TYPE (Node3D, Array, etc) --- It doesn't have a res:// path, so it's likely a native Godot class.
				print("OUTSIDE BUILT IN::", identifier)
				resolved_type = _process_built_in_type_method(current_part, current_type_path, current_class_obj, local_vars)
		
		
		# ==========================================
		# PHASE 3: HANDLE THE RESULT
		
		if resolved_type is not String:
			resolved_type = ""
		# If we hit a dead end (untyped var, unknown function)
		if resolved_type == "":
			return ""
			#var remainder = ".".join(parts) # Join whatever is left
			#var dead_end_path = current_part if remainder == "" else current_part + "." + remainder
			#return dead_end_path if current_type_path == "" else current_type_path + "." + dead_end_path
		
		# RECURSION CHECK: Did the variable return a literal expression instead of a parsed type?
		# e.g., local_vars["my_var"] resulted in the string "SomeClass.get_instance()"
		# We must resolve that expression into a true path before continuing!
		
		
		if _is_unresolved_expression(resolved_type, allow_global): 
			# Pass the initial context because expressions are evaluated where they were declared!
			var recursive = get_chain_type(resolved_type, initial_class_obj, local_vars, allow_global, recursions + 1)
			if recursive != resolved_type:
				print("RECURSE::", resolved_type)
				resolved_type = recursive
				print("RECURSE RESOLVED TYPE::", resolved_type)
			else:
				print("RECUR == INPUT: ", resolved_type)
				return ""
		else:
			print("RESOLVED_EXPRESSION::", resolved_type)
		#resolved_string = UString.dot_join(resolved_string, resolved_type)
		
		if resolved_type.begins_with("res://"):
			var script_data = get_script_path_and_suffix(resolved_type)
			if resolved_type.begins_with(main_script_path):
				current_script_path = main_script_path
				current_script = main_script
				var access_path = script_data[1]
				var new_class_obj = parser.get_class_object(access_path)
				prints("SWITCH OBJ:", script_data, current_class_obj, " -> ", new_class_obj)
				current_class_obj = new_class_obj
				#print(current_class_obj)
				current_part_in_script = true
				if new_class_obj == null:
					if access_path.ends_with(Keys.ENUM_PATH_SUFFIX):
						return resolved_type
					else:
						print("UNHANDLED CLASS OBJECT::", resolved_type)
					
				
			else:
				current_script_path = script_data[0]
				current_script = load(current_script_path)
				current_part_in_script = false
		
		#elif _resolve_to_script:
			##var final_string = current_class_obj.script_access_path + "." + resolved_type
			#var final_string = UString.dot_join(current_script_path, current_class_obj.script_access_path)
			#final_string = UString.dot_join(final_string, resolved_type)
			##var remainder = ".".join(parts)
			##var dead_end_path = UString.dot_join(current_part, remainder)
			##var final_string = UString.dot_join(current_type_path, dead_end_path)
			##print("RESOLVE TO SCRIPT RETURN::", final_string)
			#return final_string
		
		if allow_global and _valid_identifier(resolved_type, allow_global):
			return UString.dot_join(resolved_type, ".".join(parts))
		
		
		
		var old_path = current_type_path
		current_type_path = resolved_type
		print("SET PATH %s -> %s" % [old_path, resolved_type])
		print(".".join(parts))
		
		#var remainder = ".".join(parts) # Join whatever is left
		#var dead_end_path = ""
		#if remainder == "":
			#dead_end_path = current_part
		#else:
			#dead_end_path = current_part + "." + remainder
		#if current_type_path != "":
			#dead_end_path = current_type_path + "." + dead_end_path
		#return dead_end_path
		
	
	print("RETURN:", str(recursions), " ==== ", current_type_path)
	#print("RES STRING ==== ", resolved_string)
	return current_type_path

func _is_unresolved_expression(identifier:String, allow_global:=false):
	if identifier.begins_with("res://"):
		return false
	elif _valid_identifier(identifier, allow_global):
		return false
	elif identifier.find(".") > -1:
			return true
	
	return true

func _valid_identifier(identifier:String, allow_global:=false):
	if _is_class_name_valid(identifier, allow_global): # don't allow global so they are resolved to script.
		return true
	if VariantChecker.check_type(identifier):
		return true
	if GlobalChecker.is_valid(identifier):
		return true
	
	return false


func _process_in_script_data(member_name:String, class_obj:ParserClass, local_vars:Dictionary):
	var count = 0
	var result = member_name
	while member_in_class_or_local_vars(result, class_obj, local_vars):
		count += 1
		if count > 50:
			print("COUNTED OUT")
			break
		var next_result = _check_member_data(result, class_obj, local_vars)
		if next_result == null:
			break
		if result == next_result:
			break
		result = next_result
	
	return result
	
func _check_member_data(member_name:String, class_obj:ParserClass, local_vars:Dictionary):
	var member_data = local_vars.get(member_name)
	if member_data == null:
		member_data = class_obj.get_member(member_name)
	print(member_data)
	
	if member_data == null:
		print("MEMBER NULL, WHAT TO DO???: ", member_name)
		#return _simple_type_check(member_name)
	
	
	var type_declaration = ""
	
	var member_type = member_data.get(Keys.MEMBER_TYPE)
	var line_index = member_data.get(Keys.LINE_INDEX)
	if member_type == Keys.MEMBER_TYPE_CLASS:
		return member_data.get(Keys.TYPE)
	elif member_data is ParserFunc:
		type_declaration = _get_func_return_type(member_name, class_obj)
		print("GET FUNC: ", type_declaration)
	elif member_type == Keys.MEMBER_TYPE_FUNC_ARG:
		type_declaration = member_data.get(Keys.TYPE)
	#elif member_type == Keys.MEMBER_TYPE_CONST:
		#if member_data.get(Keys.TYPE) == "": # stops crazy recursion
			#return ""
		#var resolved = _resolve_constant(member_name, class_obj)
		#print("CONST RESULT ", resolved)
		#return resolved
	else:
		var column = member_data.get(Keys.COLUMN_INDEX, 0)
		print("COLUMN ", column)
		type_declaration = _get_script_member_type(line_index, column)
		
		
	
	
	var type_check = _simple_type_check(type_declaration)
	if type_check != "":
		print("TYPE CHECK SUCCESS: ", type_check)
		return type_check
	
	print("FUNC OR VAR: ", type_declaration)
	
	
	#member_data=
	
	return type_declaration



func _process_non_script_class_member(identifier:String, current_type_path:String, class_obj:ParserClass, local_vars:Dictionary):
	prints(current_type_path, identifier)
	if identifier.begins_with("new(") or identifier == "new":
		return current_type_path
	
	var stripped_identifier = identifier
	if identifier.find("(") > -1:
		stripped_identifier = identifier.get_slice("(", 0)
	
	
	if class_obj.has_inherited_member(stripped_identifier):
		print("IS INHER")
		return _get_inherited_member_type(stripped_identifier, class_obj)
	
	return _process_built_in_type_method(identifier, current_type_path, class_obj, local_vars)

func _process_built_in_type_method(identifier:String, current_type_path:String, class_obj:ParserClass, local_vars:Dictionary):
	var type_to_check = ""
	if current_type_path == &"Dictionary":
		if identifier.begins_with("get"):
			var args = identifier.get_slice("(", 1)
			print(identifier, args)
			args = args.substr(0, args.rfind(")"))
			if args.find(",") == -1:
				return identifier
			var default = args.get_slice(",", 1).strip_edges()
			if member_in_class_or_local_vars(default, class_obj, local_vars):
				return _process_in_script_data(default, class_obj, local_vars)
			type_to_check = default
	
	if type_to_check == "":
		return ""
	
	var check = _simple_type_check(type_to_check)
	if check != "":
		return check
	
	return type_to_check




func _process_external_identifier(identifier:String, script:GDScript):
	#var member_info = get_script_member_info_by_path(script, identifier)
	#if member_info != null:
		#return _property_info_to_type_no_class(member_info)
	
	
	var t = ALibRuntime.Utils.UProfile.TimeFunction.new("OUTSIDE PARSER")
	var parser = GDScriptParser.new()
	parser.set_current_script(script)
	parser.set_source_code(script.source_code)
	parser.parse()
	var type = parser.get_identifier_type(identifier)
	t.stop()
	
	return type


## Get func return from script editor text.
func _get_func_return_type(method_name:String, class_obj:ParserClass):
	var global_check = GlobalChecker.get_global_return_type(method_name)
	if global_check != null:
		return global_check
	print("GET FUNC: ", method_name, " ", class_obj.functions.has(method_name))
	
	var type = ""
	if class_obj.functions.has(method_name):
		var func_obj = class_obj.get_function(method_name) as ParserFunc
		type = func_obj.get_return_type()
	else:
		type = _get_inherited_member_type(method_name, class_obj)
	
	if type == "":
		return ""
	#var check = _simple_type_check(type)
	#if check != "":
		#return check
	return type






func _simple_type_check(type_hint:String):
	
	if type_hint.find(" as ") > -1:
		type_hint = type_hint.get_slice(" as ", 1)
		if type_hint.find("#") > -1:
			type_hint = type_hint.get_slice("#", 0)
		type_hint = type_hint.strip_edges()
		
	
	
	if type_hint.find(".new(") > -1:
		type_hint = type_hint.substr(0, type_hint.find(".new(")) # was rfind, prob should be find?
		if _is_class_name_valid(type_hint):
			return type_hint
	
	
	if VariantChecker.check_type(type_hint):
		return type_hint
	if type_hint.begins_with("res://"):
		return type_hint
	if type_hint.begins_with("uid:"):
		return UFile.uid_to_path(type_hint)
	
	if type_hint == "true" or type_hint == "false":
		return "bool"
	elif type_hint.is_valid_int():
		return "int"
	elif type_hint.is_valid_float():
		return "float"
	elif type_hint.begins_with("["):
		return "Array"
	elif type_hint.begins_with("{"):
		return "Dictionary"
	elif type_hint.begins_with("&"):
		return "StringName"
	elif type_hint.begins_with("^"):
		return "NodePath"
	elif type_hint.begins_with('"') or type_hint.begins_with("'"):
		return "String"
	
	if _is_class_name_valid(type_hint):
		return type_hint
	
	return ""


## Get property info of inherited var, return type as string.
func _get_inherited_member_type(var_name:String, class_obj:ParserClass):
	var script = class_obj.get_script_resource()
	if not is_instance_valid(script):
		if PRINT_DEBUG:
			printerr("GET INHERITED INNER CLASS: ", script)
		return ""
	
	
	
	
	#TEST
	print("GET INHERITED ", script.get_base_script())
	var base_script = script.get_base_script()
	if is_instance_valid(base_script):
		return _process_external_identifier(var_name, base_script)
	
	
	#TEST
	
	var member_info = class_obj.get_inherited_member(var_name)
	if member_info == null:
		return ""
	var type = _property_info_to_type_no_class(member_info)#, class_obj)
	if type == "":
		return ""
	return type



func _find_member_inheriting_script(identifier:String, script:GDScript):
	var last_script = script
	if get_script_member_info_by_path(script, identifier) == null:
		return ""
		
	var current_script = script.get_base_script()
	while current_script != null:
		if get_script_member_info_by_path(current_script, identifier) == null:
			break
		last_script = current_script
		current_script = current_script.get_base_script()
	
	return last_script.resource_path




func _get_parser_for_script(script:GDScript):
	var parser = GDScriptParser.new()
	parser.set_current_script(script)
	parser.set_source_code(script.source_code)
	parser.parse()
	return parser








#endregion








class Test:
	
	static func some_func() -> String:
		return ""
	
	func get_ins() -> Nest:
		return Nest.new()
	const U=Utils
	func a_string() -> StringName:
		return &""
	class Nest extends U:
		var my_var:Test
		func get_some() -> int:
			return 1
		func my_dict() -> Dictionary:
			
			return {}
		
		func my_recur() -> String:
			return my_recur()
		
	
	
	func test():
		
		var g = get_ins()
		
		var m = g.my_dict()


func test():
	
	var t= Test.new()
	var n = t.get_ins()
	
	#if n.my_var.U.get_class_name_in_line("") == 
	
	








#^ these may be obsoleted

#func resolve_full_const_type(var_name, class_obj:ParserClass):
	##if not class_obj.has_constant_or_class(var_name):
		##return null
	#var type = _resolve_constant(var_name, class_obj)
	#print("RESOLVED TYPE: ", type)
	#return type


#func _resolve_constant(var_name: String, class_obj: ParserClass) -> String:
	#var parser = _get_parser()
	#var parser_main_script_path = parser._script_path
	#
	## Treat the identifier as a queue of parts to resolve.
	## e.g., "SC.Class.Another" -> ["SC", "Class", "Another"]
	#var parts: Array = Array(var_name.split("."))
	#
	#var resolved_path: String = ""
	#var working_class_obj: ParserClass = class_obj
	#var visited_aliases: Dictionary = {}
#
	## Keep processing as long as we have parts in our chain
	#while parts.size() > 0:
		#var current_part = parts[0]
		#
		## If the current class object doesn't know what this part is, 
		## we've gone as deep as we can statically resolve. Break the loop.
		#if not working_class_obj.has_constant_or_class(current_part):
			#break
		#
		## Cycle Detection (Class Instance + Alias Name ensures we don't falsely flag identical names in different classes)
		#var cycle_key = str(working_class_obj) + "::" + current_part
		#if visited_aliases.has(cycle_key):
			#if PRINT_DEBUG:
				#printerr("Cycle detected in constant resolution! Alias '", current_part, "' is part of a loop.")
			#resolved_path += "[CYCLE_ERROR:" + current_part + "]"
			#parts.pop_front()
			#break
		#
		#visited_aliases[cycle_key] = true
		#
		#var data = working_class_obj.get_constant_or_class(current_part)
		##print("RESOLVEDATA ", data)
		#
		#
		#var full_definition: String = data.get(Keys.TYPE, "")
		#
		## CASE 1: It's a preload/script path (e.g., "res://another.gd")
		#if full_definition.begins_with("res://"):
			#var script_path_data = get_script_path_and_suffix(full_definition)
			#var path = script_path_data[0]
			#var suffix = script_path_data[1]
			#
			#resolved_path = full_definition
			## Consume this part
			#parts.pop_front()
			#
			#if path == parser_main_script_path:
				#resolved_path = path # Just the res:// path for now
				#var inner_class_name = parser.get_class_at_line(0)
				#working_class_obj = parser.get_class_object(inner_class_name)
				#
				## If the preload definition itself had a suffix (e.g. res://script.gd.Inner),
				## we must prepend that suffix to our queue so the while-loop processes it!
				#if suffix != "":
					#var suffix_parts = Array(suffix.split(".", false))
					#var new_queue = suffix_parts
					#new_queue.append_array(parts)
					#parts = new_queue
					#
			#else: 
				## At this point it is out of script, so rely on GDScript Resource
				#var script = load(path) 
				#
				## CRITICAL: Combine the preload's suffix AND the remaining queue parts
				#var remaining_chain_parts = []
				#if suffix != "":
					#remaining_chain_parts.append(suffix)
				#if parts.size() > 0:
					#remaining_chain_parts.append(".".join(parts))
					#
				#var full_remaining_chain = ".".join(remaining_chain_parts)
				#
				#if full_remaining_chain == "":
					#return path
				#var member_info = get_script_member_info_by_path(script, full_remaining_chain)
				#print("OUT OF SCRIPT DATA: ", script.resource_path, " -> ", full_remaining_chain)
				## Return the final resulting string
				#return _property_info_to_type_no_class(member_info)
			#
			#
			#
		## CASE 2: It is the inner class itself (definition is the same as the name)
		#elif full_definition == current_part or full_definition == "":
			#resolved_path = UString.dot_join(resolved_path, current_part)
			#parts.pop_front() # Consume this part
			#
			## Move our context deep into the inner class
			#var idx = data.get(Keys.LINE_INDEX)
			#var inner_class_name = parser.get_class_at_line(idx)
			#working_class_obj = parser.get_class_object(inner_class_name)
			#
		## CASE 3: It is an Alias/Constant (e.g., const SC = SubClass.Sub)
		#else:
			#parts.pop_front() # Remove 'SC'
			#
			## Split "SubClass.Sub" into ["SubClass", "Sub"]
			#var alias_parts: Array = Array(full_definition.split("."))
			#
			## Prepend the alias definition to the front of our remaining queue
			## So ["Class", "Another"] becomes ["SubClass", "Sub", "Class", "Another"]
			#var new_queue: Array = []
			#new_queue.append_array(alias_parts)
			#new_queue.append_array(parts)
			#parts = new_queue
			#
			## Notice we DO NOT change working_class_obj here, because the alias
			## needs to be resolved starting from the current class context!
#
	## If there are leftover parts we couldn't resolve natively (e.g. standard Godot properties),
	## we just append them to whatever path we successfully built.
	#if parts.size() > 0:
		#var remainder = ".".join(parts)
		#resolved_path = UString.dot_join(resolved_path, remainder)
#
	#return resolved_path


#^ not sure that this is really needed
#func resolve_static_path(script:GDScript, member_path:String):
	#if member_path.begins_with("res://"):
		#var path_data = get_script_path_and_suffix(member_path)
		#script = load(path_data[0])
		#member_path = path_data[1]
	#
	#var parts = UString.split_member_access(member_path) as Array
	#var current_script = script
	#var working_path = ""
	#while not parts.is_empty():
		#var p = parts.pop_front()
		#var to_check = p
		#if to_check.find("(") > -1:
			#to_check = to_check.substr(0, to_check.find("("))
		#
		#var member_info = UClassDetail.get_member_info_by_path(current_script, to_check)
		#if member_info is GDScript:
			#current_script = member_info
			#working_path = UString.dot_join(working_path, p)
		#elif member_info == null:
			#working_path = UString.dot_join(working_path, ".".join(parts))
			#break
		#else:
			#var type = _property_info_to_type_no_class(member_info)
			#if type != "":
				#return type
			#else:
				#working_path = UString.dot_join(working_path, p)
			#break
	#
	#return working_path



#^ HELPER FUNCS


## Get script member info, ignores Godot Native class inheritance properties.
func get_script_member_info_by_path(script:GDScript, member_path:String, member_hints:=UClassDetail._MEMBER_ARGS, check_global:=true):
	return UClassDetail.get_member_info_by_path(script, member_path, member_hints, false, false, false, check_global)


static func get_script_path_and_suffix(script_path:String):
	if not script_path.begins_with("res://"):
		return []
	var path = script_path
	var suffix = ""
	var gd_idx = script_path.find(".gd.")
	if gd_idx > -1:
		path = script_path.substr(0, gd_idx + 3)
		suffix = script_path.substr(gd_idx + 4)
	return [path, suffix]

## Get a class_name from property info and convert to a type if possible.
## If method data, uses return data.
func property_info_to_type(property_info, class_obj:ParserClass) -> String:
	var type = _property_info_to_type(property_info, class_obj)
	return type

func _property_info_to_type(property_info, class_obj:ParserClass) -> String:
	if property_info is Dictionary:
		if property_info.has("return"):
			property_info = property_info.get("return", {})
		
		if property_info.has("class_name"):
			var _class_name = property_info.get("class_name")
			if _class_name == "":
				var type = property_info.get("type")
				return type_string(type)
			
			if not _class_name.begins_with("res://"):
				return _class_name
			
			var class_path = _class_name
			var const_name = class_obj.has_preload(class_path)
			if const_name:
				return const_name
			
			#var class_path = _class_name #^ old version
			#var access_name = ""
			##if _class_name.find(".gd.") > -1: #^ maybe able comment this with preload map modified
				##class_path = _class_name.substr(0, _class_name.find(".gd.") + 3) # + 3 to keep ext
				##access_name = _class_name.substr(_class_name.find(".gd.") + 4) # + 4 to omit ext
			#var const_name = preload_map.get(class_path)
			#if const_name:
				#if access_name == "":
					#return const_name
				#else:
					#return const_name + "." + access_name
			
			return _class_name # return class name as path or class to process elsewhere
		
	elif property_info is GDScript:
		var current_script = _get_parser_main_script()
		var member_path = UClassDetail.script_get_member_by_value(current_script, property_info)
		if member_path != null:
			return member_path
		
		var path = property_info.resource_path
		var const_name = class_obj.has_preload(path)
		if const_name:
			return const_name
	
	if PRINT_DEBUG:
		printerr("UNHANDLED PROPERTY INFO OR UNFOUND: ", property_info)
	return ""


func _property_info_to_type_no_class(property_info) -> String:
	if property_info is Dictionary:
		if property_info.has("return"):
			property_info = property_info.get("return", {})
		
		if property_info.has("class_name"):
			var _class_name = property_info.get("class_name")
			if _class_name == "":
				var type = property_info.get("type")
				return type_string(type)
			
			if not _class_name.begins_with("res://"):
				return _class_name
			return _class_name # return class name as path or class to process elsewhere
		
	elif property_info is GDScript:
		return property_info.resource_path
	
	if PRINT_DEBUG:
		printerr("UNHANDLED PROPERTY INFO OR UNFOUND: ", property_info)
	return ""




## Check that class name is Godot Native or member of the class. A valid user global class will also return true.
func _is_class_name_valid(_class_name, check_global:=true):
	if _class_name.find(".") > -1:
		_class_name = _class_name.substr(0, _class_name.find("."))
	if ClassDB.class_exists(_class_name):
		return true
	var current_script = _get_parser_main_script()
	var base = current_script.get_instance_base_type()
	if (ClassDB.class_has_enum(base, _class_name) or ClassDB.class_has_integer_constant(base, _class_name) or 
	ClassDB.class_has_method(base, _class_name) or ClassDB.class_has_signal(base, _class_name)):
		return true
	if check_global:
		if UClassDetail.get_global_class_path(_class_name) != "":
			return true
	return false


func _get_script_member_type(line:int, column:int=0): # thjs could be a bit more efficient, if not needed, could use what you got already, 
	var code_edit_parser = _get_code_edit_parser() # but also maybe speeding up scan by not getting types could be good
	#var line_text = code_edit_parser.get_line(line, true)
	var get_type_data = code_edit_parser.get_type_from_line(line, column)
	var result = get_type_data.get("result")
	if result == null:
		return ""
	var dec_type = get_type_data.get("type", &"")
	if dec_type == Keys.MEMBER_TYPE_CONST or dec_type == Keys.MEMBER_TYPE_VAR or dec_type == Keys.MEMBER_TYPE_STATIC_VAR:
		return result[1]
	elif dec_type == Keys.MEMBER_TYPE_ENUM:
		var parser = Utils.ParserRef.get_parser(self)
		var class_at_line = parser.get_class_object(parser.get_class_at_line(line)) as ParserClass
		var access = UString.dot_join(class_at_line.access_path, result[0] + Keys.ENUM_PATH_SUFFIX)
		return UString.dot_join(class_at_line.main_script_path, access)
	elif dec_type == Keys.MEMBER_TYPE_CLASS:
		var parser = Utils.ParserRef.get_parser(self)
		var class_at_line = parser.get_class_object(parser.get_class_at_line(line)) as ParserClass
		var access = UString.dot_join(class_at_line.access_path, result[0])
		return UString.dot_join(class_at_line.main_script_path, access)
	elif dec_type == Keys.MEMBER_TYPE_FUNC or dec_type == Keys.MEMBER_TYPE_STATIC_FUNC:
		return result.get(Keys.FUNC_NAME, "")
	elif dec_type == Keys.MEMBER_TYPE_SIGNAL:
		return "Signal"
	
	return ""
	
	#if line_text.ends_with("\\") or column > 0:
		#return code_edit_parser.get_type_from_line(line, column)
	#else:
		#return code_edit_parser.get_type_from_line_text(line_text.strip_edges())

func member_in_class_or_local_vars(identifier:String, class_obj:ParserClass, local_vars:Dictionary):
	return class_obj.has_script_member(identifier) or local_vars.has(identifier)
