
const PLUGIN_EXPORTED = false
const PRINT_DEBUG = false # not PLUGIN_EXPORTED

const GDScriptParser = preload("uid://c4465kdwgj042") #! resolve ALibRuntime.Utils.UGDScript.Parser

const VarInsertType = preload("res://addons/addon_lib/brohd/alib_runtime/utils/gdscript/parser/utils/type_lookup/var_insert_type.gd")

const UString = GDScriptParser.UString
const UFile = GDScriptParser.UFile
const UClassDetail = GDScriptParser.UClassDetail
const UResource = GDScriptParser.UResource

const ParserClass = GDScriptParser.ParserClass
const ParserFunc = GDScriptParser.ParserFunc
const BuiltInChecker = GDScriptParser.BuiltInChecker
const Utils = GDScriptParser.Utils
const Keys = Utils.Keys
const AccessObject = GDScriptParser.Access.AccessObject
const InferenceContext = GDScriptParser.InferenceContext

const GLOBAL_CALLABLE_QUEUED = &"global_callable_queued"
const RESOLVE_FLAGS = [GLOBAL_CALLABLE_QUEUED]

const ENUM_SUFFIX = Keys.ENUM_PATH_SUFFIX
const CALLABLE_SUFFIX = Keys.CALLABLE_SUFFIX
const SIGNAL_SUFFIX = Keys.SIGNAL_SUFFIX

const OTHER_TYPES = ["void", "Variant"]
const CALL_METHODS = ["call", "callv", "call_deferred"]
const ARRAY_INDEX_METHODS = [&"get", &"back", &"front", &"pop_back", &"pop_front", &"pop_at"]

const INDEX_PREFIX = &"%%INDEX"

static var _ternary_regex:RegEx
static var _ternary_if_regex:RegEx
static var _ternary_else_regex:RegEx
static var _as_regex:RegEx
static var _bitwise_op_regex:RegEx
static var _bool_op_regex:RegEx
static var _compar_op_regex:RegEx

static var autoload_cache:= {}


var _parser:WeakRef
var code_edit:CodeEdit



var create_non_script_parsers:=true

var use_parsers_for_outside_script:=true

# for resolve inner class
var class_resolution:=false
var class_resolution_obj:ParserClass

#var _resolve_to_script:=false

var inference_context:InferenceContext
var _inf_weakref:WeakRef

func get_inference_context() -> InferenceContext:
	if _inf_weakref != null:
		return _inf_weakref.get_ref()
	return

func set_inference_context(inf:InferenceContext):
	_inf_weakref = weakref(inf)



func _get_parser() -> GDScriptParser:
	return _parser.get_ref()

func _get_code_edit_parser() -> GDScriptParser.CodeEditParser:
	return _get_parser().code_edit_parser

func _get_parser_main_script():
	return Utils.ParserRef.get_parser(self).get_current_script()


#region Get Function Data

func get_function_data_at_line(identifier:String, line:int):
	var class_data = get_class_data_at_line(line)
	return _get_function_data(identifier, class_data.class_obj, line)

func _get_function_data(identifier:String, class_obj:ParserClass, line:int=-1):
	#print("GET FUNC DATA::", identifier , "::IN::", class_obj.get_script_class_path())
	var parser = Utils.ParserRef.get_parser(self)
	
	# if this is passed with a "()" on the last member, it would need to be stripped
	var stripped_identifier = identifier
	var type_rich = parser.resolve_expression_to_type_rich(stripped_identifier, line)
	if Utils.is_absolute_path(type_rich.origin) and type_rich.origin.ends_with(CALLABLE_SUFFIX):
		var _func_name = Utils.type_path_get_member(type_rich.origin)
		var parser_data = parser.get_parser_and_class_obj_for_script(type_rich.origin)
		var func_obj = parser_data.class_obj.get_function(_func_name)
		if is_instance_valid(func_obj):
			return func_obj.get_function_data()
	elif type_rich.origin.contains(Keys.MEMBER_DELIM):
		var non_member_type = Utils.type_path_get_non_member(type_rich.origin)
		var member = Utils.type_path_get_member(type_rich.origin)
		if BuiltInChecker.class_has_method(non_member_type, member):
			return BuiltInChecker.get_func_data(non_member_type, member)
	elif BuiltInChecker.is_global_method(stripped_identifier):
		return BuiltInChecker.get_global_func_data(stripped_identifier)
	
	print("FUNC DATA TEST::NO RESULT::", identifier, " -> ", type_rich.origin)
	return {}

#endregion


#region Resolve Expression

## This call is almost identical to the normal resolve, except it will not use inheritance in the current class.
## This is because the class must be declared by something in the current script, impossible to be an inherited member.
func resolve_inner_class_at_line(expression:String, line:int):
	class_resolution = true
	
	var class_data = get_class_data_at_line(line)
	var class_obj = class_data.class_obj
	class_resolution_obj = class_obj
	var result = _resolve_expression_to_val(expression, class_data)
	class_resolution = false
	var type_check = _simple_type_check(result)
	if type_check != "" and type_check != result:
		# the only time I've seen trigger is when a path goes in, returns exact same
		printerr("IS THIS USED - _simple_type_check in resolve_inner_class_at_line::", result, " -> ", type_check)
		return type_check
	return result


func resolve_expression_to_type_at_line(expression:String, line:int):
	if class_resolution == true:
		printerr("CLASS RES TRUE")
	class_resolution = false
	
	var class_data = get_class_data_at_line(line)
	return _resolve_expression_to_type(expression, class_data, true) # true means resolve will change to first type mode

func resolve_expression_to_type_at_line_respect_inf_context(expression:String, line:int):
	if class_resolution == true:
		printerr("CLASS RES TRUE")
	class_resolution = false
	
	var class_data = get_class_data_at_line(line)
	return _resolve_expression_to_type(expression, class_data, false) # false means resolve will respect current mode


func resolve_expression_to_var_data_at_line(expression:String, line:int):
	return _resolve_expression_to_var_data_at_line_simple(expression, line)

func _resolve_expression_to_var_data_at_line_simple(expression:String, line:int):
	if class_resolution == true:
		printerr("CLASS RES TRUE")
	class_resolution = false
	var t = ALibRuntime.Utils.UProfile.TimeFunction.new("GET VAR DATA")
	
	var class_data = get_class_data_at_line(line)
	if not class_data.valid_data:
		return get_empty_type_rich()
	
	var inf_context = _get_or_instance_inf_context()
	inf_context.find_origin = true
	var inf_expression = _get_inf_expression(class_data, expression)
	var inf_check = _check_inf_expression(inf_context, inf_expression)
	if inf_check != null:
		_check_inf_on_exit()
		var empty = get_empty_type_rich()
		empty.type = inf_check
		return empty
	
	
	var origin = _resolve_expression_to_val(expression, class_data)
	var member_stack = inf_context.member_stack.duplicate()
	
	# finish this expression, then check the type with a new context
	# would just call the _resolve_to_origin, but I want to keep the member stack in tact
	inf_context.finish_expression(inf_expression, origin)
	inf_context.find_origin = false
	inf_context.member_stack.clear()
	inf_context=null
	_check_inf_on_exit()
	
	# just check the type again rather than tracking the stack
	var type = _resolve_expression_to_type(expression, class_data, true)
	
	var is_instance = type.ends_with(Keys.INS_DELIM)
	
	var type_check = Utils.type_path_get_type(type, true)
	if type_check != "":
		if type_check != "Enum":
			type = type_check
	elif type == "" and origin != "": # if this fails, can try a back up on the origin, not likely to ever happen
		printerr("Failed type, but not origin::", expression, " -> ", origin)
		type_check = Utils.type_path_get_type(origin, true)
		if type_check != "" and type_check != "Enum":
			type = type_check
		else:
			type = origin
	
	# i think this should not be here, but for now it can. Instead use the is_instance key
	if type != "" and is_instance and not type.ends_with(Keys.INS_DELIM):
		type = Utils.type_path_add_ins(type)
	
	var data = get_empty_type_rich()
	data.origin = origin
	data.type = type
	data.member_stack = member_stack
	data.is_instance = is_instance
	
	#t.stop()
	#print(expression," -> ",origin)
	#InferenceContext.print_member_stack(member_stack)
	#print(var_data)
	return data


func _resolve_expression_to_origin(expression: String, class_data:ClassData) -> String:
	if class_resolution == true:
		printerr("CLASS RES TRUE")
	class_resolution = false
	
	var inf_context = _get_or_instance_inf_context()
	var inf_expression = _get_inf_expression(class_data, expression)
	var inf_check = _check_inf_expression(inf_context, inf_expression)
	if inf_check != null:
		_check_inf_on_exit()
		return inf_check
	
	var current_find_setting = inf_context.find_origin
	inf_context.find_origin = true
	
	var result = _resolve_expression_to_val(expression, class_data)
	inf_context.finish_expression(inf_expression, result)
	
	
	
	inf_context.find_origin = current_find_setting
	inf_context=null
	_check_inf_on_exit()
	return result


func _resolve_expression_to_type(expression: String, class_data:ClassData, set_find_origin:=false) -> String:
	if class_resolution == true:
		printerr("CLASS RES TRUE")
	class_resolution = false
	
	if not class_data.valid_data:
		return ""
	
	var inf_context = _get_or_instance_inf_context()
	var inf_expression = _get_inf_expression(class_data, expression)
	var inf_check = _check_inf_expression(inf_context, inf_expression)
	if inf_check != null:
		_check_inf_on_exit()
		return inf_check
	
	var current_find_setting = inf_context.find_origin
	if set_find_origin:
		inf_context.find_origin = false
	
	var result = _resolve_expression_to_val(expression, class_data)
	inf_context.finish_expression(inf_expression, result)
	
	if set_find_origin:
		inf_context.find_origin = current_find_setting
	inf_context=null
	_check_inf_on_exit()
	return result


#^ consider passing the class data object instead this will allow better local var shadow checking and clean up the arguments
# resolves expression to value
func _resolve_expression_to_val(expression: String, class_data:ClassData, recursions=0) -> String:
	if recursions >= 10:
		return "Variant"
	print_deb(T.RESOLVE, recursions, "CALLING AGAIN", expression)
	var parser = _get_parser()
	var main_script = parser.get_current_script()
	var main_script_path = main_script.resource_path
	
	var initial_class_obj = class_data.class_obj
	var local_vars = class_data.local_vars
	
	if expression.begins_with("(") and expression.ends_with(")"):
		expression = expression.trim_prefix("(").trim_suffix(")")
	
	if Utils.is_absolute_path(expression):
		print_deb(T.RESOLVE, "EARLY EXIT", "BEGIN WITH RES", expression)
		var path = _ensure_valid_type_path(expression)
		return Utils.file_path_to_type(path)
		#return expression
	
	if expression == "self": # if self, we can just return the path to the class
		var class_path = UString.dot_join(main_script_path, initial_class_obj.access_path)
		return Utils.type_path_add_ins(class_path)
	elif expression.begins_with("self."):
		expression = expression.trim_prefix("self.")
	
	var tern_check = _check_for_ternary_operation(expression, class_data)
	if tern_check != "":
		#print("TERN::", expression, " -> ", tern_check)
		return tern_check
	var bool_bit_check = _check_for_bool_or_bitwise_operation(expression)
	if bool_bit_check != "":
		#print("COMPCHECK::bool::", expression, " -> ", bool_bit_check)
		return bool_bit_check
	
	var comp_check:String = _check_for_math_operation(expression)
	if comp_check != "":
		#print("COMPCHECK::", expression, " -> ", comp_check)
		expression = comp_check
	
	var string_map = parser.get_string_map(expression)
	var parts: Array = UString.split_member_access(expression, string_map)
	
	var current_class_obj:ParserClass = initial_class_obj
	var current_type_path = Keys.INS_DELIM # set this based on if function is static or not
	if class_data.initial_type_path != "":
		current_type_path = class_data.initial_type_path
	elif class_data.in_static_function():
		#printerr("SETTING TO NOT INS")
		current_type_path = ""
	
	
	var external_script_path:String
	var external_script_class_access:String
	
	var current_part_in_script = true
	var is_awaited = false
	var queued_callable:String
	var last_queued_callable:String
	var queued_signal:String # not sure if needed or not...
	
	print_deb(T.RESOLVE, "START:%s - %s ----------" % [recursions, expression], "INITIAL CLASS", initial_class_obj.get_script_class_path())
	print_deb(T.RESOLVE, "PARTS", parts)
	var count = 0
	while parts.size() > 0 and count < 10:
		count += 1
		var current_part: String = parts.pop_front()
		
		# clean this up
		var is_initial_class = current_type_path.trim_suffix(Keys.INS_DELIM) == "" or current_type_path.trim_suffix(Keys.INS_DELIM) == (initial_class_obj.get_script_class_path())

		#if current_class_obj == initial_class_obj:
		if is_initial_class:
			local_vars = class_data.local_vars
		else: # out of initial class, local vars no longer valid
			local_vars = {}
		
		print_deb(T.RESOLVE, "         ----------------------            ")
		print_deb(T.RESOLVE, "NEXT PART", current_part, "CURRENT TYPE PATH", current_type_path)
		
		var is_func = current_part.find("(") != -1
		var identifier = current_part.split("(", false, 1)[0] if is_func else current_part
		identifier = identifier.strip_edges()
		
		var current_t_is_ins = current_type_path.ends_with(Keys.INS_DELIM)# or is_initial_class
		if current_t_is_ins:
			current_type_path = current_type_path.trim_suffix(Keys.INS_DELIM)
		
		
		
		var add_to_inf_context:=true
		
		var id_is_ins = identifier.ends_with(Keys.INS_DELIM)
		if id_is_ins:
			print_deb(T.RESOLVE, "ID IS INS", identifier)
			identifier = identifier.get_slice(Keys.INS_DELIM, 0)
		
		if identifier in RESOLVE_FLAGS:
			identifier = ""
		
		print_deb(T.RESOLVE, "TYPE IS INS", current_t_is_ins, "ID IS INS", id_is_ins)
		
		if current_type_path.contains(Keys.TYPE_DELIM):
			var type = Utils.type_path_get_type(current_type_path, true)
			if not type.is_empty():
				if type == "Enum":
					if not BuiltInChecker.class_has_method("Dictionary", identifier):
						return current_type_path # commented below works, but doesn't give proper path to enum
					#var dic_return = BuiltInChecker.get_func_return("Dictionary", identifier)
					#var new = UString.dot_join(current_type_path.trim_suffix(ENUM_SUFFIX), identifier)
					#return Utils.type_path_add_type(new, dic_return)
					current_type_path = "Dictionary[StringName, int]"
					current_part_in_script = false
				elif type == "Callable":
					pass
				else:
					# signal was also being treated specially, but may not need it
					# can any signal specific information be taken from it? if so, can do the queue
					# but as I can see, seems to be irrelavent
					current_type_path = type
					current_part_in_script = false
		
		#^ the 'new' logic was previously here
		
		print_deb(T.RESOLVE, "CURRENT TYPE PATH", current_type_path)
		print_deb(T.RESOLVE, "Queued Callable", queued_callable)
		print_deb(T.RESOLVE, "Queued Signal", queued_signal)
		
		if current_part.begins_with("await "):
			is_awaited = true
			#current_part = current_part.get_slice("await ", 1).strip_edges()
			identifier = current_part.get_slice("await ", 1).strip_edges()
		
		#var is_callable = current_type_path.ends_with(CALLABLE_SUFFIX)
		var callable_is_queued = queued_callable != ""
		var signal_is_queued = queued_signal != ""
		#var is_signal = current_type_path.ends_with(SIGNAL_SUFFIX)
		var current_t_is_dict = current_type_path == "Dictionary" or current_type_path.begins_with("Dictionary[")
		var current_t_is_arr = current_type_path == "Array" or current_type_path.begins_with("Array[")
		var current_t_is_collection = current_t_is_dict or current_t_is_arr
		
		var resolved_type = ""
		if not current_part.begins_with(INDEX_PREFIX):
			var index_access = not current_part.begins_with("[") and current_part.ends_with("]")
			if current_t_is_collection: # i think this was a indent issue
				index_access = false
			if not is_func:
				var part_check = current_part.get_slice("[", 0).strip_edges()
				if part_check == "Dictionary" or part_check == "Array":
					index_access = false
			if index_access:
				var all_index_access = get_index_access_in_string(current_part)
				for string in all_index_access:
					parts.push_front(INDEX_PREFIX + string)
			
				if not is_func:
					var part_check = current_part.get_slice("[", 0).strip_edges()
					identifier = part_check # proceed to process the identifier
		else:
			var identifier_name = current_part.trim_prefix(INDEX_PREFIX).trim_prefix("[").trim_suffix("]")
			if UString.is_string_or_string_name(identifier_name):
				identifier = UString.unquote(identifier_name) # proceed to process the identifier
			elif current_t_is_collection:
				resolved_type = get_type_hint_from_collection(current_type_path)
			else:
				resolved_type = BuiltInChecker.get_variant_index_access_type(current_type_path)
		
		
		if identifier == "new": #^ relocated here to allow index access
			current_type_path = Utils.get_or_add_current_type_path(current_type_path, current_class_obj)
			if is_func:
				if not current_type_path.ends_with(Keys.INS_DELIM):
					current_type_path = current_type_path + Keys.INS_DELIM
				continue
			else:
				queued_callable = Utils.type_path_add_member(current_type_path, "new") + CALLABLE_SUFFIX
				continue
		
		print_deb(T.RESOLVE, "CYCLE ----------")
		print_deb(T.RESOLVE, "CHECK", identifier, "CURRENT TYPE", current_type_path, "RAW", current_part, "RES", resolved_type)
		
		var preload_resolved:=false
		var class_member_resolved:=false
		var current_type_has_member = _class_has_member(current_type_path, identifier)
		var current_type_base_has_member = _class_has_member(current_class_obj.script_base_type, identifier)
		if resolved_type != "":
			pass # this seems ok as a guard for all 
		if identifier == "preload" and is_func: # this may be not needed anymore? is in in_script_process
			print_deb(T.RESOLVE, "PRELOAD BRANCH")
			preload_resolved = true
			resolved_type = resolve_preload(current_part, current_class_obj)
			#if id_is_ins:
				#resolved_type += Keys.INS_DELIM
			print_deb(T.RESOLVE, "PRELOAD BRANCH", "RES", resolved_type)
		elif BuiltInChecker.is_builtin_class(identifier):
			resolved_type = identifier
			print_deb(T.RESOLVE, "BUILTIN IDENTIFIER BRANCH", "RES", resolved_type)
		#elif local_vars.has(identifier):
		elif is_initial_class and member_in_class_or_local_vars(identifier, current_class_obj, local_vars):
			print_deb(T.RESOLVE, "INITIAL CLASS BRANCH", "RES", resolved_type)
			pass # if the identifier is a local var it may shadow a built in
		elif callable_is_queued:
			if not identifier in CALL_METHODS: # bind, is_valid, etc
				resolved_type = get_class_member_type("Callable", identifier)
				if resolved_type == "Callable":
					resolved_type = current_type_path
				else:
					last_queued_callable = queued_callable
					queued_callable = ""
			else: # call, callv, call_deferred
				print_deb(T.RESOLVE, "ID IN CALL METHODS", identifier)
				var trimmed_callable_path = queued_callable.trim_suffix(CALLABLE_SUFFIX)
				if Utils.is_absolute_path(queued_callable):
					resolved_type = Utils.type_path_get_non_member(trimmed_callable_path)
					var callable_name = Utils.type_path_get_member(trimmed_callable_path)
					parts.push_front(callable_name + "()") # get the name and push it with the paren to get value
				else:
					var builtin = "" # need this for global funcs
					var method_name = trimmed_callable_path
					if queued_callable.contains(Keys.MEMBER_DELIM):
						builtin = trimmed_callable_path.get_slice(Keys.MEMBER_DELIM, 0)
						method_name = trimmed_callable_path.get_slice(Keys.MEMBER_DELIM, 1)
					resolved_type = get_class_member_type(builtin, method_name)
				
				queued_callable = ""
			print_deb(T.RESOLVE, "CALLABLE BRANCH", "RES", resolved_type)
		elif current_type_path != "null" and (current_type_has_member or current_type_base_has_member or BuiltInChecker.is_global_method(identifier)):
			# TEST ALERT this may be a bit jank, need further testing
			
			# if id is get or in call, process them via the custom methods
			if identifier != "get" and not identifier in CALL_METHODS:
				if current_type_has_member:
					pass # if current type has member, continue as usual
				elif current_type_base_has_member:
					# not in current but is in base, switch types
					current_type_path = current_class_obj.script_base_type
			# TEST ALERT
			
			if not BuiltInChecker.is_global_method(identifier) and not BuiltInChecker.is_variant_type(current_type_path):
				if not current_t_is_ins and not BuiltInChecker.is_member_const(current_type_path, identifier):
					print_deb(T.RESOLVE, "NOT A CONST", current_type_path, identifier)
					return ""
			
			# not sure why this is checking for 'null' string
			print_deb(T.RESOLVE, "class has member")
			if BuiltInChecker.class_has_method(current_type_path, identifier) and not is_func:
				queued_callable = Utils.type_path_add_member(current_type_path, identifier) + CALLABLE_SUFFIX
				if current_type_path == "":
					current_type_path = GLOBAL_CALLABLE_QUEUED
				
				resolved_type = current_type_path
				class_member_resolved = true # set it here in case a global method is called and type path doesn't change
				
			elif BuiltInChecker.class_has_signal(current_type_path, identifier):
				if is_awaited: # signal arguments
					resolved_type = get_class_member_type(current_type_path, identifier)
					print_deb(T.RESOLVE, "SIG GET RES", current_type_path, identifier, "->", resolved_type)
				else: # signal object
					#queued_signal = Utils.type_path_add_member(current_type_path, identifier) + SIGNAL_SUFFIX
					resolved_type = current_type_path
					resolved_type = Utils.type_path_add_member(current_type_path, identifier) + SIGNAL_SUFFIX
			elif BuiltInChecker.class_has_enum(current_type_path, identifier):
				resolved_type = get_class_member_type(current_type_path, identifier)
				resolved_type = Utils.type_path_add_member(current_type_path, identifier) + ENUM_SUFFIX
			elif current_t_is_dict and (identifier == "get" or identifier == "get_or_add"):
				resolved_type = _resolve_builtin_class_member(current_part, current_type_path, current_class_obj, local_vars)
				pass # skip for now, this is handled below, maybe move here
			else:
				
				resolved_type = get_class_member_type(current_type_path, identifier)
				print_deb(T.RESOLVE, "get_class_member_type::", current_type_path, "::", identifier)
			
			if resolved_type != "":
				class_member_resolved = true
			
			print_deb(T.RESOLVE, "BUILT IN RESOLVE BRANCH", "RES", resolved_type)
		else:
			print_deb(T.RESOLVE, "NO BRANCH", "RES", resolved_type)
		
		
		## this was originally just on the class member branch, will this cause issues to apply to all?
		#if not preload_resolved and resolved_type != "" and current_t_is_ins:
			#resolved_type = Utils.type_path_add_ins(resolved_type)
		
		
		if resolved_type == "": 
			if current_class_obj.class_has_member(identifier):
				print_deb_err(T.RESOLVE, "IS THIS USED SECOND CLASS HAS MEMBER --- START::", current_part, "::", current_type_path)
				# handles 'call', 'get' in classes and Dictionary.get() inferring
				if is_func and identifier in CALL_METHODS:
					var meth_str = Utils.get_string_inside_brackets(current_part)
					if meth_str != "":
						print_deb_err(T.RESOLVE, "SETTING ID METHOD::", current_part, " -> ", identifier)
						identifier = meth_str
						is_func = true
						
				elif identifier != "get" and identifier != "get_or_add": # all after this are 'get'
					resolved_type = get_class_member_type(current_class_obj.script_base_type, identifier)
					if resolved_type != "":
						class_member_resolved = true
					print_deb_err(T.RESOLVE, "IS THIS USED ---- ::", identifier, " -> ", resolved_type) 
				elif is_func and Utils.is_absolute_path(current_type_path):
					var prop_str = Utils.get_string_inside_brackets(current_part)
					if prop_str != "":
						print_deb_err(T.RESOLVE, "SETTING ID PROP::", identifier, " -> ", prop_str)
						identifier = prop_str
						is_func = false
				else: # get can be tricky, the built in returns Nil, but we can attempt to infer more. Maybe limit to Dictionary?
					resolved_type = _resolve_builtin_class_member(current_part, current_type_path, current_class_obj, local_vars)
					if resolved_type != "":
						print_deb_err(T.RESOLVE, "IS THIS USED SECOND CLASS HAS MEMBER::TYPE SUCCESSFULLY RESOLVED::", current_part, "::", current_type_path, "::", resolved_type)
				
				if resolved_type != "":
					print_deb_err(T.RESOLVE, "SECOND CLASS HAS MEMBER --- DID RESOLVE::", current_part, "::", current_type_path, "::", resolved_type)
		
		# this was originally just on the class member branch, will this cause issues to apply to all?
		if not preload_resolved and resolved_type != "" and current_t_is_ins:
			resolved_type = Utils.type_path_add_ins(resolved_type)
		
		
		var resolved_member = false
		if resolved_type == "":
			if current_part_in_script: #^ --- IN SCRIPT ---
				print_deb(T.RESOLVE, "IN_SCRIPT", identifier, "IN", main_script_path, "CLASS", current_class_obj.access_path)
				
				
				if not member_in_class_or_local_vars(identifier, current_class_obj, local_vars):
					# should this have the same adding await and what not as process external to this?
					var id_to_send = identifier
					if is_awaited:
						id_to_send = "await " + id_to_send
					if is_func:
						id_to_send = id_to_send + "()"
					resolved_type = _get_inherited_member_type(identifier, id_to_send, current_class_obj)
					print_deb(T.RESOLVE,"INHERITED", resolved_type)
				else:
					print_deb(T.RESOLVE, "CLASS OR LOCAL")
					if is_func:
						resolved_type = _resolve_process_in_script_data(identifier, current_class_obj, local_vars)
						print_deb(T.RESOLVE, "RESOLVE IN SCRIPT", identifier, resolved_type)
					elif current_class_obj.has_script_signal(identifier):
						if is_awaited:
							resolved_type = current_class_obj.get_script_signal_args(identifier, true)
						else:
							var class_path = Utils.get_or_add_current_type_path(current_type_path, current_class_obj)
							resolved_type = Utils.type_path_add_member(class_path, identifier + SIGNAL_SUFFIX)
							#queued_signal = Utils.type_path_add_member(class_path, identifier + SIGNAL_SUFFIX)
							#resolved_type = class_path
							#if current_t_is_ins:
								#resolved_type = Utils.type_path_add_ins(resolved_type)
					
						# check local vars too, they can shadow func names
					elif not current_class_obj.has_function(identifier) or local_vars.has(identifier):
						resolved_type = _resolve_process_in_script_data(identifier, current_class_obj, local_vars)
						print_deb(T.RESOLVE, "RESOLVE IN SCRIPT", identifier, resolved_type)
					else:
						if current_class_obj.has_function(identifier):
							var class_path = Utils.get_or_add_current_type_path(current_type_path, current_class_obj)
							#resolved_type = Utils.type_path_add_member(class_path, identifier + CALLABLE_SUFFIX)
							queued_callable = Utils.type_path_add_member(class_path, identifier + CALLABLE_SUFFIX)
							resolved_type = class_path
							if current_t_is_ins:
								resolved_type = Utils.type_path_add_ins(resolved_type)
					
					if resolved_type.contains(Keys.MEMBER_INFER_DELIM):
						identifier = resolved_type.get_slice(Keys.MEMBER_INFER_DELIM, 0)
						resolved_type = resolved_type.get_slice(Keys.MEMBER_INFER_DELIM, 1)
					
					if not current_t_is_ins and not local_vars.has(identifier): # add the local here for managing static funcs, I think it's ok?
						var member_data = current_class_obj.get_member_data(identifier)
						print_deb(T.RESOLVE, "MEMBER_DATA", member_data)
						if not member_data:
							resolved_type = ""
						elif not Utils.member_is_valid_static(member_data.get(Keys.MEMBER_TYPE)):
							resolved_type = ""
						
					if resolved_type != "":
						resolved_member = true
				
				if resolved_type != "":
					add_to_inf_context = false
				
			else: #^ --- OUTSIDE SCRIPT ---
				if Utils.is_absolute_path(current_type_path):
					 # these need to be the same as how it was sent, essentially this is just doing the current thing in the inherited script
					var id_to_send = identifier
					#id_to_send.
					if is_awaited:
						id_to_send = "await " + id_to_send
					if is_func:
						id_to_send = id_to_send + "()"
					resolved_type = _process_external_identifier(id_to_send, external_script_path, external_script_class_access)
					print_deb(T.RESOLVE, "EXTERNAL", "%s -> %s" % [id_to_send, resolved_type])
					
					if resolved_type != "":
						add_to_inf_context = false
		
		
		if resolved_type == "" and not Utils.is_absolute_path(current_type_path):# pass through current part so that you can get full context
			print_deb(T.RESOLVE, "OUTSIDE BUILT IN", identifier)
			if queued_callable == "":
				resolved_type = _resolve_builtin_class_member(current_part, current_type_path, current_class_obj, local_vars) # ie. Dictionary.get(), can infer default
				if resolved_type != "":
					printerr("IS THIS USED -- Outside built in ", current_part, " -> ", resolved_type)
		
		if resolved_type == "":
			print_deb(T.RESOLVE, "ATTEMPT GLOBAL", identifier)
			resolved_type = check_global_or_autoload(identifier)
		
		print_deb(T.RESOLVE, "BASE ID", resolved_type)
		
		if resolved_type == "":
			var part_simple_check = _variant_type_check(current_part)
			if part_simple_check != "":
				print_deb(T.RESOLVE, "VARIANT CHECK", resolved_type,"->" ,part_simple_check)
				resolved_type = part_simple_check
		
		#^ --- HANDLE THE RESULT ---
		
		if resolved_type is not String and resolved_type is not StringName:
			print_deb(T.RESOLVE, "RETURN FAIL", expression)
			return ""
		if resolved_type == "": # If we hit a dead end (untyped var, unknown function)
			print_deb(T.RESOLVE, "RETURN FAIL", expression)
			return ""
		
		
		#^ not sure about this, this is included in the variant check, is variant check overkill? also checked above...
		#var as_check = _check_for_type_cast(resolved_type)
		#if as_check != "":
			#print_deb(T.RESOLVE, "AS CHECK", resolved_type,"->" ,as_check)
			#resolved_type = as_check
		
		var pre_recurse_var_check = _variant_type_check(resolved_type)
		if pre_recurse_var_check != "":
			print_deb(T.RESOLVE, "PRE REC VAR", resolved_type, "->", pre_recurse_var_check)
			resolved_type = pre_recurse_var_check
		
		
		# RECURSION CHECK: if not a valid type or path, resolve further
		if _is_unresolved_expression(resolved_type):# and not resolved_member:
			add_to_inf_context = false
			print_deb(T.RESOLVE, "UNRESOLVED RECURSING", resolved_type)
			# Pass the initial context because expressions are evaluated where they were declared!
			var recursive = _resolve_expression_to_val(resolved_type, class_data, recursions + 1)
			if recursive.is_empty():
				print_deb(T.RESOLVE, "RECURSE FAIL EMPTY", resolved_type)
				return ""
			if recursive != resolved_type:
				print_deb(T.RESOLVE, "RECURSE RESOLVED TYPE %s -> %s" %[resolved_type, recursive])
				resolved_type = recursive
			else:
				print_deb(T.RESOLVE, "RECUR == INPUT", resolved_type)
				return ""
		else:
			print_deb(T.RESOLVE, "RESOLVED_EXPRESSION", resolved_type)
		
		
		#deb
		var old_path = current_type_path # for debug
		if resolved_member:
			print_deb(T.RESOLVE ,"RES MEMBER",identifier, " -> ", resolved_type, " ->", current_type_path, "~")
		#/deb
		
		
		var variant_check = _variant_type_check(resolved_type, false)
		if variant_check != "":
			resolved_type = variant_check
		
		# TEST ALERT this may be a bit jank, need further testing, not sure if this is where it should go..
		
		# convert resource path to it's gdscript base
		if Utils.is_absolute_path(resolved_type) and resolved_type.trim_suffix(Keys.INS_DELIM).get_extension() == "tres":
			var trimmed_path = resolved_type.trim_suffix(Keys.INS_DELIM)
			var script_path = UResource.get_resource_script_class(trimmed_path)
			#push_warning("RESOLVED TRES::", script_path)
			resolved_type = script_path
			var global_check = check_global_or_autoload(resolved_type)
			if global_check != "":
				#push_warning("RESOLVED GLOBAL::", global_check)
				resolved_type = global_check
			resolved_type = Utils.type_path_add_ins(resolved_type)
		# TEST ALERT
		
		print_deb(T.RESOLVE ,"PRE NMEW RESMEM",resolved_member,"PRE::",identifier, " -> ", resolved_type, " ->:", current_type_path, ":")
		var non_member_part = Utils.type_path_get_non_member(resolved_type)
		if non_member_part != "" and BuiltInChecker.is_builtin_class(non_member_part):
			pass # these can be passed and will be set below
		elif resolved_member and not Utils.is_absolute_path(resolved_type):
			var member_path = Utils.get_or_add_current_type_path(current_type_path, current_class_obj)
			if local_vars.has(identifier):
				#var var_data = local_vars.get(identifier, {})
				#var member_type = var_data.get(Keys.MEMBER_TYPE)
				#var line_idx = var_data.get(Keys.LINE_INDEX)
				#var local_var_id = "local(%s-%s)" % [identifier, line_idx]
				#member_path = Utils.type_path_add_member(member_path, local_var_id)
				#resolved_type = Utils.type_path_add_type(member_path, resolved_type)
				pass # local vars don't have their location inferred, unless they are point at a member
			elif current_class_obj.has_script_member(identifier):
				member_path = Utils.type_path_add_member(member_path, identifier)
				resolved_type = Utils.type_path_add_type(member_path, resolved_type)
		
		
		if add_to_inf_context:
			var inf_context = get_inference_context()
			if inf_context:
				print_deb(T.RESOLVE, "INF CONTEXT::", current_type_path, "::", identifier, "::", resolved_type)
				print_deb(T.RESOLVE, "CLASS RESOLVED::", class_member_resolved)
				var type_path = current_type_path
				if last_queued_callable != "":
					type_path = last_queued_callable
					last_queued_callable = ""
				elif class_member_resolved and (type_path == "" or Utils.is_absolute_path(type_path)):
					type_path = "global"
				type_path = Utils.get_or_add_current_type_path(type_path, current_class_obj)
				var res_type_string = type_path + Keys.MEMBER_DELIM + identifier + Keys.MEMBER_STACK_DELIM + resolved_type
				#var stack_string = InferenceContext.get_stack_string(identifier, resolved_type, current_class_obj, local_vars)
				# I seemed to have been getting things out of order due to recursion, hence the idx tracking and insert
				# however, it doesn't seem to be doing it now...
				#inf_context.member_stack.insert(next_inf_index, stack_string)
				inf_context.add_to_member_stack(res_type_string)
				#inf_context.add_to_member_stack("RES - " + res_type_string)
		
		print_deb(T.RESOLVE ,"PRE FINAL BRANCHES",resolved_member,"PRE::",identifier, " -> ", resolved_type, " ->:", current_type_path, ":")
		
		if resolved_type.ends_with(CALLABLE_SUFFIX):
			queued_callable = resolved_type
			if current_t_is_ins:
				current_type_path = Utils.type_path_add_ins(current_type_path)
		elif not Utils.is_absolute_path(resolved_type):
			print_deb(T.RESOLVE ,"RESMEM",resolved_member,"PRE::",identifier, " -> ", resolved_type, " ->:", current_type_path, ":")
			current_part_in_script = false
			current_type_path = resolved_type
			print_deb(T.RESOLVE ,"POST::",identifier, " -> ", resolved_type, " -> ", current_type_path)
		else:
			current_type_path = resolved_type
			
			var script_data = Utils.type_path_get_script_data(current_type_path)
			var current_script_path = script_data[0]
			var access_path = script_data[1]
			
			print_deb(T.RESOLVE ,"RESOLVED IS PATH::", current_type_path, "::ACCESS::", access_path)
			current_part_in_script = current_type_path.begins_with(main_script_path)
			if current_part_in_script:
				var new_class_obj = parser.get_class_object(access_path)
				print_deb(T.RESOLVE, "SWITCH OBJ", script_data, "%s -> %s" % [current_class_obj, new_class_obj])
				current_class_obj = new_class_obj
				if new_class_obj == null:
					print_deb(T.RESOLVE, "UNHANDLED CLASS OBJECT", current_type_path)
					pass
			else:
				external_script_path = current_script_path
				external_script_class_access = access_path
				print_deb(T.RESOLVE ,"SET EXTERNAL::", external_script_path, "::", external_script_class_access)
	
		
		print_deb(T.RESOLVE, "SET PATH %s -> %s" % [old_path, current_type_path])
		print_deb(T.RESOLVE, "PARTS_LEFT",".".join(parts))
		
		if is_awaited and current_type_path.ends_with(SIGNAL_SUFFIX):
			var type_path = ""
			var signal_name = Utils.type_path_get_member(current_type_path)
			if current_type_path.contains(Keys.MEMBER_DELIM):
				type_path = current_type_path.get_slice(Keys.MEMBER_DELIM, 0)
			parts.push_front("await " + signal_name)
			current_type_path = type_path
			if current_t_is_ins:
				current_type_path = Utils.type_path_add_ins(current_type_path)
		
		# should this do both id and the current?
		if id_is_ins:
			current_type_path = Utils.type_path_add_ins(current_type_path)
		
		print_deb(T.RESOLVE, "SET PATH FINAL %s -> %s" % [old_path, current_type_path])
	
	print_deb(T.RESOLVE, "RETURN", str(recursions), " ==== ", current_type_path)
	
	if queued_callable != "":
		current_type_path = queued_callable
	
	if Utils.is_absolute_path(current_type_path):
		current_type_path = _ensure_valid_type_path(current_type_path)
		current_type_path = Utils.file_path_to_type(current_type_path)
	elif current_type_path == Keys.INS_DELIM:
		current_type_path = "" # this would mean 0 resolutions could be done, or an empty string attempted
	print_deb(T.RESOLVE, "RETURN", str(recursions), " ==== ", current_type_path)
	return current_type_path




func _is_unresolved_expression(identifier:String):
	#if identifier.begins_with("res://"):
	#if _simple_type_check(identifier) != "":
		#return false
	if identifier.trim_suffix(Keys.INS_DELIM) in RESOLVE_FLAGS:
		#print("THIS SHOULD FINE::")
		return false
	if identifier.ends_with(Keys.INS_DELIM):
		identifier = identifier.trim_suffix(Keys.INS_DELIM)
		if Utils.is_absolute_path(identifier) or BuiltInChecker.is_builtin_class(identifier):
			return false
		#return true
	
	if _variant_type_check(identifier) != "":
		return false
	if Utils.is_absolute_path(identifier):
		return false
	elif _valid_identifier(identifier):
		return false
	elif identifier.begins_with("typedarray::"):
		return false
	elif identifier.contains(Keys.TYPE_DELIM):
		return UString.string_safe_find(identifier, Keys.TYPE_DELIM) == -1 # this may be slow..
	elif identifier.contains(Keys.MEMBER_DELIM):
		return UString.string_safe_find(identifier, Keys.MEMBER_DELIM) == -1 # this may be slow..
	elif identifier.ends_with(CALLABLE_SUFFIX):
		return false
	elif identifier.ends_with(SIGNAL_SUFFIX):
		return false
	
	# TEST forces 'Node.ProccessMode' down a level and returns with 'Node.ProccessMode##Enum'
	#elif identifier.find(".") > -1:
		#var sm = Utils.ParserRef.get_parser(self).get_string_map(identifier)
		#var front = UString.get_member_access_front(identifier, sm)
		#var back = UString.trim_member_access_front(identifier, sm)
		#if ClassDB.class_exists(front):
			#if ClassDB.class_has_enum(front, back):
				#return false
			# not sure about this
			#if ClassDB.class_has_integer_constant(front, back):
				#return false
		
		#if _class_has_member(front, back):
			#return false
		#return true
	
	return true


func _resolve_process_in_script_data(member_name:String, class_obj:ParserClass, local_vars:Dictionary):
	#if class_obj.cached_resolve_valid_for_member(member_name):
		#print("IN TYPE LOOKUP::GET MEMBER::", member_name)
		#return class_obj.get_cached_resolve_for_member(member_name)
	
	
	var inf_context = get_inference_context()
	
	
	var count = 0
	var last_result = ""
	var result:String = member_name
	var is_ins = member_name.ends_with(Keys.INS_DELIM)
	
	print_deb(T.RESOLVE, member_name, "GOING IN")
	while member_in_class_or_local_vars(result, class_obj, local_vars):
		count += 1
		if count > 50:
			#print("COUNTED OUT")
			break
		
		
		# the idea with this was to keep this level before any recursive entries
		#var next_inf_index = inf_context.member_stack.size() if inf_context else 0
		
		var next_result = _check_class_obj_member_data(result, class_obj, local_vars)
		if next_result == null or next_result == "":
			result = ""
			break
		if result == next_result:
			break
		print_deb(T.RESOLVE, "NEXT RES", result, " -> ", next_result)
		if next_result.contains(Keys.MEMBER_INFER_DELIM):
			last_result = next_result.get_slice(Keys.MEMBER_INFER_DELIM, 0)
			result = next_result.get_slice(Keys.MEMBER_INFER_DELIM, 1)
		
		
		if result.contains(Keys.MEMBER_ASSIGN_DELIM):
			var assignment = result.get_slice(Keys.MEMBER_ASSIGN_DELIM, 0)
			var type_hint = result.get_slice(Keys.MEMBER_ASSIGN_DELIM, 1)
			
			if inf_context.find_origin:
				result = assignment
				# the below could be used, but is better off not if finding the origin, perhaps checking
				# if it is a raw dictionary assignment "= {}", if not continue
				if (type_hint.begins_with("Array[") and assignment.begins_with("[")) or (type_hint.begins_with("Dictionary[") and assignment.begins_with("{")):
					result = type_hint
				else:
					result = assignment
				
			else:
				result = type_hint
		
		print_deb(T.RESOLVE, next_result, "RESULT")
		
		
		if inf_context:
			var stack_string = InferenceContext.get_stack_string(member_name, next_result, class_obj, local_vars)
			# I seemed to have been getting things out of order due to recursion, hence the idx tracking and insert
			# however, it doesn't seem to be doing it now...
			#inf_context.member_stack.insert(next_inf_index, stack_string)
			inf_context.add_to_member_stack(stack_string)
			#inf_context.add_to_member_stack("PROC - " + stack_string) # just a debug tag
		else:
			push_warning("NO INF CONTEXT")
			pass
		
		
		if result.ends_with(Keys.INS_DELIM):
			is_ins = true
			result = result.trim_suffix(Keys.INS_DELIM)
		
		if class_obj.has_function(result) and not local_vars.has(result):
			break # if the result is a raw function call, break and process it
		
	
	if is_ins:
		result = Utils.type_path_add_ins(result)
	
	if last_result != "":
		return Utils.join_delim(last_result, result, Keys.MEMBER_INFER_DELIM)
	return result


func _resolve_builtin_class_member(identifier:String, current_type_path:String, _class_obj:ParserClass, _local_vars:Dictionary):
	var type_to_check = ""
	var is_func = identifier.find("(") > -1
	var stripped_identifer = identifier.substr(0, identifier.find("(")) if is_func else identifier
	print_deb(T.BUILTIN, identifier, "TYPE", current_type_path)
	var method_handled = false
	if current_type_path == &"Dictionary":
		if identifier.begins_with("get") or identifier.begins_with("get_or_add"):
			var args = identifier.get_slice("(", 1)
			#print(identifier, args)
			args = args.substr(0, args.rfind(")"))
			if args.find(",") == -1:
				return "Variant"
			type_to_check = args.get_slice(",", 1).strip_edges()
			method_handled = true
	elif current_type_path.begins_with("Dictionary["):
		var key = stripped_identifer == "keys"
		type_to_check = get_type_hint_from_collection(current_type_path, not key)
		method_handled = true
	
	if not method_handled and BuiltInChecker.is_builtin_class(current_type_path):
		var return_type = BuiltInChecker.get_func_return(current_type_path, stripped_identifer)
		print_deb(T.BUILTIN, "ID", stripped_identifer, "RETURN", return_type)
		return return_type
	
	if not method_handled and BuiltInChecker.is_global_method(stripped_identifer):
		var return_type = BuiltInChecker.get_global_func_return(stripped_identifer)
		print_deb(T.BUILTIN, "ID", stripped_identifer, "RETURN", return_type)
		return return_type
	
	if type_to_check == "":
		return ""
	
	return type_to_check



func _process_external_identifier(identifier:String, script_path:String, class_access_path:String = ""):
	var type = ""
	var t = ALibRuntime.Utils.UProfile.TimeFunction.new("OUTSIDE PARSER: " + identifier + " -> " + str(script_path.get_file()))
	print_deb(T.RESOLVE, "ATTEMPT_EXTERNAL", identifier, script_path, class_access_path)
	var external_parser = _get_parser_for_script(script_path)
	#print(script_path, "::", class_access_path, "::", identifier)
	if not external_parser:
		return ""
	var class_obj = external_parser.get_class_object(class_access_path) as ParserClass
	
	if is_instance_valid(class_obj):
		#type = external_parser.resolve_expression_to_type(identifier, class_obj.declaration_line)
		type = external_parser.get_type_lookup().resolve_expression_to_type_at_line_respect_inf_context(identifier, class_obj.declaration_line)
	print_deb(T.RESOLVE, "ATTEMPT_EXTERNAL_END", identifier, script_path, class_access_path)
	#t.stop()
	return type

#TODO this is using identifer every where, should it be stripped? _process_external needs the func'()' for proper callable management
## Get property info of inherited var, return type as string.
func _get_inherited_member_type(identifier:String, full_part:String, class_obj:ParserClass):
	var is_func = identifier.find("(") > -1
	var stripped_identifer = identifier.substr(0, identifier.find("(")) if is_func else identifier
	stripped_identifer = stripped_identifer.trim_suffix(Keys.INS_DELIM)
	if not stripped_identifer.is_valid_ascii_identifier():
		print_deb(T.INHERITED, "NOT VALID ASCII", stripped_identifer)
		return ""
	elif BuiltInChecker.is_variant_type(stripped_identifer):
		return ""
	elif UClassDetail.get_global_class_path(stripped_identifer) != "":
		return ""
	
	if class_obj.class_has_member(stripped_identifer):
		return stripped_identifer
	
	if class_resolution and class_obj == class_resolution_obj:
		#^r IMPLEMENT OUTER SCRIPT CONSTANTS HERE
		print_deb(T.INHERITED, "CLASS RESOLUTION IN INHERIT", class_resolution_obj.get_script_class_path())
		return ""
	
	var member_data = class_obj.get_inherited_member(stripped_identifer)
	if member_data != null:
		var script_path = member_data.get(Keys.SCRIPT_PATH)
		if script_path != null:
			var access_path = member_data.get(Keys.ACCESS_PATH)
			# want to pass un changed identifer for proper resolution
			return _process_external_identifier(full_part, script_path, access_path) # may need access path for class?
	
	print_deb(T.INHERITED, "MEMBER_DATA", class_obj.get_script_class_path())
	print_deb(T.INHERITED, "MEMBER_DATA", stripped_identifer, member_data)
	
	print_deb(T.INHERITED, "EXTERNAL SCRIPT", "COULD NOT GET", stripped_identifer)
	var script = class_obj.get_script_resource()
	var base_script = script.get_base_script()
	if is_instance_valid(base_script):
		var inheriting_script = _find_inheriting_script(stripped_identifer, class_obj)
		if inheriting_script != "":
			var script_data = UString.get_script_path_and_suffix(inheriting_script)
			print_deb(T.INHERITED, "EXTERNAL SCRIPT", inheriting_script)
			printerr("IS THIS EVER USED - _get_inherited_member_type::want to delete _find_inheriting_script")
			return _process_external_identifier(identifier, script_data[0], script_data[1]) # may need access path for class?
	return ""


func _ensure_valid_type_path(full_script_path:String):
	if full_script_path.begins_with("preload"):
		var const_data = Utils.get_var_or_const_info("const dummy = " + full_script_path)
		full_script_path = const_data[1] # not sure if this is still needed, but I think it would 
		print("TYPE_PRELOAD::", full_script_path) # be better to use resolve_preload maybe?
		## TEST
	
	var script_data = UString.get_script_path_and_suffix(full_script_path)
	var script_path = script_data[0]
	var class_access = script_data[1]
	if class_access == "":
		return full_script_path
	var parser = _get_parser_for_script(script_path)
	if full_script_path.contains(Keys.TYPE_DELIM) or full_script_path.contains(Keys.MEMBER_DELIM):
		return full_script_path
	
	
	if full_script_path.ends_with(Keys.INS_DELIM):
		return full_script_path
	
	var type_check = Utils.type_path_get_type(full_script_path, true)
	if type_check == "Enum": # is this even needed anymore?
		var target_parser = parser.get_parser_and_class_obj_for_script(full_script_path)
		var enum_name = Utils.type_path_get_member(full_script_path)
		var class_obj = target_parser.class_obj
		if is_instance_valid(class_obj):
			if class_obj.has_enum(enum_name):
				return full_script_path
	elif type_check != "":
		return full_script_path
	
	elif class_access.contains(Keys.MEMBER_DELIM) or class_access.contains(Keys.TYPE_DELIM):
		return full_script_path
	else:
		var class_obj = parser.get_class_object(class_access)
		if is_instance_valid(class_obj):
			return full_script_path
	
	
	#^ what is the reason for this? I think this should just return?
	print_deb(T.RESOLVE, "Ensure Valid Type Path - Recursing")
	return parser.get_type_lookup().resolve_expression_to_type_at_line_respect_inf_context(class_access, 0)


#endregion

#region Resolve Access Object

func resolve_expression_to_access_object_at_line(expression:String, line:int):
	var class_data = get_class_data_at_line(line)
	return resolve_expression_to_access_object(expression, class_data)

func resolve_expression_to_access_object(expression: String, class_data:ClassData):
	var parser = _get_parser()
	var main_script = parser.get_current_script()
	var main_script_path = main_script.resource_path
	
	var initial_class_obj = class_data.class_obj
	var local_vars = class_data.local_vars
	
	#^ should this ever really be called? returns string instead of access_object, doesn't make sense to me..
	#if Utils.is_absolute_path(expression) and not expression.begins_with("preload"):
		#print_deb(T.VAR_TO_CONST, "EARLY EXIT", "BEGIN WITH RES", expression)
		#return expression
	
	var string_map = parser.get_string_map(expression)
	var front = UString.get_member_access_front(expression, string_map)
	var back = UString.get_member_access_back(expression, string_map)
	
	print_deb(T.VAR_TO_CONST, "ACCESS OBJECT START", expression)
	
	var access_object = AccessObject.new()
	
	# ALERT testing with back, was front before
	var dec_symbol = _resolve_access_object([front], initial_class_obj, local_vars, true)
	if dec_symbol == front:
		var new = expression
		#new = _validate_const_chain(expression, initial_class_obj)
		print_deb(T.VAR_TO_CONST, "DECLARATION RAW SWITCH", dec_symbol, " -> ", new)
		dec_symbol = expression
		#dec_symbol = _validate_const_chain(expression, initial_class_obj) # this is for type hints var:SomeClass.Type, returns the whole string
	# ALERT
	print_deb(T.VAR_TO_CONST, "DECLARATION RAW", dec_symbol)
	#if dec_symbol.begins_with("res://"):
	if Utils.is_absolute_path(dec_symbol):
		var script_data = UString.get_script_path_and_suffix(dec_symbol)
		if script_data[0] == main_script_path:
			var access = script_data[1]
			if access == "":
				access = "self"
			dec_symbol = access
	elif dec_symbol == "":
		dec_symbol = "self"
	#else: # TEST NEW #^r causes issues, but this makes sense, cannot declare as self..., can access from self
		#dec_symbol = "self"
	
	access_object.declaration_symbol = dec_symbol
	
	var access_symbol = _resolve_access_object([front], initial_class_obj, local_vars)
	print_deb(T.VAR_TO_CONST, "ACCESS RAW", access_symbol)
	#if access_symbol.begins_with("res://"):
	if Utils.is_absolute_path(access_symbol):
		var script_data = UString.get_script_path_and_suffix(access_symbol)
		if script_data[0] == main_script_path:
			var access = script_data[1]
			if access == "":
				access = "self" #^r what purpose does this even serve? don't seem to use it anywhere?
			access_symbol = access
	elif access_symbol == "":
		access_symbol = "self"
	#else: # TEST NEW #^r this is causing some to not work right, NewScript with the renamed time funcs
		#access_symbol = "self" #^r this was for when base types were here? EditorInterface, String etc.. where was it an issue though?
	access_object.access_symbol = access_symbol
	
	access_object.declaration_type = _resolve_expression_to_type(dec_symbol, class_data)
	#if access_object.declaration_type.begins_with("res://"):
	if Utils.is_absolute_path(access_object.declaration_type):
		var member_data = parser.get_member_info_from_script(access_object.declaration_type)
		if member_data != null:
			access_object.declaration_access_path = member_data.get(Keys.ACCESS_PATH)
	
	access_object.access_type = _resolve_expression_to_type(access_symbol, class_data)
	
	print_deb(T.VAR_TO_CONST, "TYPE", access_object.declaration_type, "DEC",access_object.declaration_symbol, "ACCESS" ,access_object.access_symbol)
	return access_object


func _resolve_access_object(parts:Array, initial_class_obj: ParserClass, local_vars:Dictionary, first_const:=false):
	if parts[0] == "self": # if self, we can just return the path to the class
		return "self"
	
	var current_class_obj:ParserClass = initial_class_obj
	print_deb(T.VAR_TO_CONST, "&&&& START: %s ----------" % [parts])
	
	var count = 0
	while parts.size() > 0 and count < 10:
		count += 1
		
		var current_part: String = parts.pop_front()
		var is_func = current_part.find("(") != -1
		var identifier = current_part.split("(", false, 1)[0] if is_func else current_part
		
		identifier = identifier.trim_suffix(Keys.INS_DELIM)
		
		if is_func and identifier == "new":
			return current_class_obj.get_script_class_path()
		
		print_deb(T.VAR_TO_CONST, "")
		print_deb(T.VAR_TO_CONST, "CYCLE ----------")
		print_deb(T.VAR_TO_CONST, "CHECK", identifier)
		
		var resolved_type = ""
		if member_in_class_or_local_vars(identifier, current_class_obj, local_vars):
			print_deb(T.VAR_TO_CONST, "IN CLASS", identifier)
			if current_class_obj.has_constant_or_class(identifier):
				if first_const:
					return identifier
				else:
					var const_path = _resolve_const_path(identifier, current_class_obj)
					print(const_path)
					return const_path
			
			#resolved_type = _var_to_const(identifier, current_class_obj, local_vars, first_const)
			var res = _var_to_const(identifier, current_class_obj, local_vars, first_const)
			if res.contains(Keys.MEMBER_INFER_DELIM):
				resolved_type = res.get_slice(Keys.MEMBER_INFER_DELIM, 1)
			else:
				resolved_type = res
			print_deb(T.VAR_TO_CONST, "IN CLASS RESOLVED", resolved_type)
			var front = UString.get_member_access_front(resolved_type)
			
			if current_class_obj.has_constant_or_class(front):
				if resolved_type.contains("."):
					resolved_type = _validate_const_chain(resolved_type, current_class_obj)
				return resolved_type
			if resolved_type != identifier:
				parts.push_front(front)
				continue
			else:
				return resolved_type
		elif current_class_obj.has_inherited_member(identifier):
			#return ""
			var member_data = current_class_obj.get_inherited_member(identifier)
			#^c Unsure about this, technically, if it is inherited, the access is self? Not sure what this should resolve to.
			var inh_script_path = member_data.get(Keys.SCRIPT_PATH, &"")
			if inh_script_path == "":
				return ""
			var parser_data = _get_parser_and_class_for_script(inh_script_path)
			var parser = parser_data.get(Keys.GET_PARSER)
			var inh_class_obj = parser_data.get(Keys.GET_CLASS_OBJ)
			var type_lookup = parser.get_type_lookup()
			
			var resolved = type_lookup._resolve_access_object([identifier], inh_class_obj, {}, first_const)
			print_deb(T.VAR_TO_CONST, "INHERITED", identifier, "RESOLVED", resolved) # should this return self? func could return something else
			if resolved != identifier:
				parts.push_front(UString.get_member_access_front(resolved))
				continue
			else:
				return resolved
		
		if BuiltInChecker.is_builtin_class(identifier):
			return identifier
		elif UClassDetail.get_global_class_path(identifier) != "":
			return identifier
		elif _is_class_name_valid(identifier):
			return identifier
		
		#if resolved_type == "":# pass through current part so that you can get full context
			#print_deb(T.VAR_TO_CONST, "OUTSIDE BUILT IN", identifier)
			#resolved_type = _resolve_builtin_class_member(current_part, current_type_path, current_class_obj, local_vars) # ie. Dictionary.get(), can infer default
		
		print_deb(T.VAR_TO_CONST, "NONE", identifier, "RES", resolved_type)
		
		#^ --- HANDLE THE RESULT ---
		if resolved_type is not String or resolved_type == "":
			return ""
	return ""

func _var_to_const(member_name:String, class_obj:ParserClass, local_vars:Dictionary, first_const:=false):
	var count = 0
	var last_result = ""
	var result = member_name
	while member_in_class_or_local_vars(result, class_obj, local_vars):
		
		if first_const:
			if class_obj.has_constant_or_class(result):
				return result
		count += 1
		if count > 50:
			print_deb(T.VAR_TO_CONST, "COUNTED OUT")
			break
		var next_result
		if class_obj.has_function(result):
			var function:ParserFunc = class_obj.get_function(result)
			next_result = function.get_return_type_raw() # returns the raw declaration
			print_deb(T.VAR_TO_CONST, "_var_to_const - get return type", next_result)
		else:
			next_result = _check_class_obj_member_data(result, class_obj, local_vars)
			print_deb(T.VAR_TO_CONST, "_var_to_const - get member data", next_result)
		if next_result == null:
			break
		
		if next_result.contains(Keys.MEMBER_INFER_DELIM):
			last_result = next_result.get_slice(Keys.MEMBER_INFER_DELIM, 0)
			next_result = next_result.get_slice(Keys.MEMBER_INFER_DELIM, 1)
		
		if result == next_result or Utils.is_absolute_path(result):
			break
		result = next_result
		
	
	result = result.trim_suffix(Keys.INS_DELIM)
	if last_result != "":
		print_deb(T.VAR_TO_CONST, "_var_to_const - return w delim", Utils.join_delim(last_result, result, Keys.MEMBER_INFER_DELIM))
		return Utils.join_delim(last_result, result, Keys.MEMBER_INFER_DELIM)
	print_deb(T.VAR_TO_CONST, "_var_to_const - return", result)
	return result






func _resolve_const_path(member_name:String, class_obj:ParserClass):
	var full_chain_parts:= []
	var count = 0
	var result = member_name
	while member_in_class_or_local_vars(result, class_obj, {}):
		count += 1
		if count > 50:
			print_deb(T.VAR_TO_CONST, "COUNTED OUT")
			break
		var next_result = _check_class_obj_member_data(result, class_obj, {})
		if next_result.contains(Keys.MEMBER_INFER_DELIM):
			next_result = next_result.get_slice(Keys.MEMBER_INFER_DELIM, 1)
		next_result = next_result.trim_suffix(Keys.INS_DELIM)
		
		#next_result = next_result.trim_suffix(Keys.INS_DELIM)
		#var not_valid = next_result == null or result == next_result or next_result.begins_with("res://")
		var not_valid = next_result == null or result == next_result or Utils.is_absolute_path(next_result)
		if not_valid:
			break
		var parts = next_result.split(".", false)
		parts.reverse()
		var p_sz = parts.size()
		for i in range(p_sz):
			var part = parts[i]
			if i == p_sz - 1:
				result = part
			else:
				full_chain_parts.push_front(part)
	
	
	full_chain_parts.push_front(result)
	print("RESOLVE CONST PATH::", ".".join(full_chain_parts))
	return ".".join(full_chain_parts)


func _validate_const_chain(chain_text:String, class_obj:ParserClass):
	var parser = _get_parser()
	
	#if chain_text.begins_with("res://"):
	if Utils.is_absolute_path(chain_text):
		print_deb(T.VAR_TO_CONST, "EARLY EXIT", "BEGIN WITH RES", chain_text)
		return chain_text
	
	var string_map = parser.get_string_map(chain_text)
	var parts = UString.split_member_access(chain_text, string_map)
	
	var working_path = ""
	for i in range(parts.size()):
		var part = parts[i]
		var type = ""
		if UClassDetail.get_global_class_path(part) != "":
			type = UClassDetail.get_global_class_path(part)
		else:
			var member_data = class_obj.get_member(part)
			if member_data == null or member_data is ParserFunc:
				break
			var member_type = member_data.get(Keys.MEMBER_TYPE)
			if member_type == Keys.MEMBER_TYPE_ENUM:
				working_path = UString.dot_join(working_path, part)
				break
			if not (member_type == Keys.MEMBER_TYPE_CLASS or member_type == Keys.MEMBER_TYPE_CONST):
				break
			
			type = class_obj.get_member_type(part)
			#if not type.begins_with("res://"):
			if not Utils.is_absolute_path(type):
				break
		working_path = UString.dot_join(working_path, part)
		var next_parser_data = parser.get_parser_and_class_obj_for_script(type)
		if not next_parser_data:
			break
		parser = next_parser_data.parser
		class_obj = next_parser_data.class_obj
		#var result = next_parser.
	
	return working_path

#endregion


#region Utils

func path_has_suffix(string:String) -> StringName:
	if string.ends_with(ENUM_SUFFIX):
		return ENUM_SUFFIX
	if string.ends_with(CALLABLE_SUFFIX):
		return CALLABLE_SUFFIX
	if string.ends_with(SIGNAL_SUFFIX):
		return SIGNAL_SUFFIX
	return &""

## Get member type in class obj. Returns declaration or converted to type if it is a simple check [method _simple_type_check].
## Allow rebuild param will determine if the script will reparse if not found at it's line index.
func get_class_obj_member_type(member_name:String, class_obj:ParserClass, local_vars:Dictionary={}, allow_rebuild:=true):
	var result = _check_class_obj_member_data(member_name, class_obj, local_vars, allow_rebuild)
	if result.contains(Keys.MEMBER_INFER_DELIM):
		result = result.get_slice(Keys.MEMBER_INFER_DELIM, 1)
	return result

## Get the member's definition text, returned as member_name:;;:declaration
func _check_class_obj_member_data(member_name:String, class_obj:ParserClass, local_vars:Dictionary, allow_rebuild:=true):
	var is_local = false
	var member_data = local_vars.get(member_name)
	if member_data != null:
		is_local = true
	else:
		member_data = class_obj.get_member(member_name)
	
	if member_data == null:
		print("MEMBER NULL, WHAT TO DO???: ", member_name, " CLASS:: ", class_obj.get_name())
		return "" # only time I have triggered is deleting a var and then quickly trying to access, difficult to trigger
	
	var type_declaration = ""
	var member_type = member_data.get(Keys.MEMBER_TYPE)
	var line_index = member_data.get(Keys.LINE_INDEX)
	if member_type == Keys.MEMBER_TYPE_CLASS:
		type_declaration = member_data.get(Keys.TYPE)
	elif member_data is ParserFunc:
		type_declaration = member_data.get_return_type()
		print_deb(T.RESOLVE, "GET FUNC", type_declaration)
	elif member_type == Keys.MEMBER_TYPE_FUNC_ARG:
		type_declaration = member_data.get(Keys.TYPE)
	else:
		var column = member_data.get(Keys.COLUMN_INDEX, 0)
		print_deb(T.RESOLVE, "COLUMN ", column)
		if not is_local: # local is parsed every auto complete cycle, only necessary on body members
			var code_edit_parser = _get_code_edit_parser()
			if not code_edit_parser.check_member_line(member_type, member_name, line_index, column, allow_rebuild):
				if allow_rebuild:
					return _check_class_obj_member_data(member_name, class_obj, local_vars, false)
				else:
					print("ABORT CHECK MEMBER DATA")
					return "" # this should be handled by the above member_data check
		
		type_declaration = _get_script_member_type(line_index, column)
		print_deb(T.RESOLVE, "MEMBER GET TYPE", member_name, " -> ", type_declaration)
		#if type_declaration == "Signal":
			#type_declaration = UString.dot_join(class_obj.get_script_class_path(), member_name + SIGNAL_SUFFIX)
		
		#prints(member_type, member_name, type_declaration)
		#^ handle for loop collection inference
		if not type_declaration.is_empty() and member_type == Keys.MEMBER_TYPE_FOR:
			var original_type = type_declaration
			print_deb(T.RESOLVE, "FOR LOOP TYPE::", type_declaration)
			if type_declaration.contains(Keys.MEMBER_INFER_DELIM):
				print_deb(T.RESOLVE, "MEMBER DELIM HERE IN FOR")
				type_declaration = type_declaration.get_slice(Keys.MEMBER_INFER_DELIM, 0)
			else:
				var collection_text = type_declaration
				var collection_type_dec = ""
				if type_declaration.contains(Keys.MEMBER_ASSIGN_DELIM):
					collection_text = type_declaration.get_slice(Keys.MEMBER_ASSIGN_DELIM, 0)
					collection_type_dec = type_declaration.get_slice(Keys.MEMBER_ASSIGN_DELIM, 1)
				print_deb(T.RESOLVE, "FOR LOOP TYPE::COLLECTION", collection_text, "TYPEHINT",collection_type_dec)
				 # if this defined and we arent doing origin search, then we don't need to go further
				if collection_type_dec != "" and not _check_inf_find_origin():
					type_declaration = collection_type_dec
				elif collection_text.ends_with("values()") or collection_text.ends_with("keys()"):
					# these 2 resolve expression do not respect origin, so they are faster
					# remains to be seen if this is valid...
					#if collection_type_dec == "":
					var dict_path = UString.trim_member_access_back(collection_text)
					collection_type_dec = resolve_expression_to_type_at_line(dict_path, line_index)
					type_declaration = get_type_hint_from_collection(collection_type_dec, collection_text.ends_with("values()"))
				else:
					#if collection_type_dec == "":
					collection_type_dec = resolve_expression_to_type_at_line(collection_text, line_index)
					type_declaration = get_type_hint_from_collection(collection_type_dec)
			print_deb(T.RESOLVE, "LOOP", original_type, " -> ", type_declaration)
	
	# niche case, if a local var is the same name as a class member and directly assigned it will rerun with no local vars
	if type_declaration == member_name and allow_rebuild: # allow rebuild will only allow one attempt
		return _check_class_obj_member_data(member_name, class_obj, {}, false)
	
	if type_declaration.begins_with("preload"):
		var p_check = resolve_preload(type_declaration, class_obj)
		if p_check != "": # adding this check here allows a non resolved preload to be resolved to path and have ins tag added if appropriate
			type_declaration = p_check # does the one in the main body still apply?, I am thinking no
			
	
	
	if type_declaration != "":
		type_declaration = member_name + Keys.MEMBER_INFER_DELIM + type_declaration
	
	print_deb(T.RESOLVE, "_check_class_obj_member_data - type", type_declaration)
	return type_declaration





func _valid_identifier(identifier:String):
	if _is_class_name_valid(identifier): # don't allow global so they are resolved to script.
		return true
	#if BuiltInChecker.is_global_method(identifier):
		#return true
	if BuiltInChecker.is_builtin_class(identifier):
		return true
	if identifier in OTHER_TYPES:
		return true
	return false

## Check that class name is Godot Native or member of the class. A valid user global class will also return true.
func _is_class_name_valid(identifier:String):
	#if identifier.find(".") > -1:
		#identifier = identifier.substr(0, identifier.find("."))
	if ClassDB.class_exists(identifier):
		return true
	var current_script = _get_parser_main_script()
	var base = current_script.get_instance_base_type()
	#if (
		##ClassDB.class_has_enum(base, identifier) or
		##ClassDB.class_has_integer_constant(base, identifier) or
		#ClassDB.class_has_method(base, identifier) or
		#ClassDB.class_has_signal(base, identifier)
		#):
		#return true
	return false


# Can I combine this with get_class member? or maybe just add a bool check to builtin checker
## Check that ClassDB class contains member.
func _class_has_member(base_type:String, identifier:String):
	if base_type.begins_with("Array["):
		base_type = "Array"
	elif base_type.begins_with("Dictionary["):
		base_type = "Dictionary"
	
	# this should be sufficient for this check
	return BuiltInChecker.class_has_member(base_type, identifier)


static func get_class_member_type(base_type:String, identifier:String, resolve_const:=false):
	var original_base = base_type
	var collection_base = false
	if base_type.contains("["):
		var is_dupe = identifier == "duplicate" or identifier == "duplicate_deep"
		if base_type.begins_with("Array"):
			collection_base = true
			if is_dupe:
				return base_type
			elif identifier in ARRAY_INDEX_METHODS:
				return get_type_hint_from_collection(base_type)
			else:
				base_type = "Array"
		elif base_type.begins_with("Dictionary"):
			collection_base = true
			if is_dupe:
				return base_type
			elif identifier == "find_key":
				return get_type_hint_from_collection(base_type)
			elif identifier == "get" or identifier == "get_or_add":
				return get_type_hint_from_collection(base_type, true)
			if identifier == "keys": # third false stops the ins tag from being added, not needed
				return "Array[%s]" % get_type_hint_from_collection(base_type, false, false)
			elif identifier == "values":
				return "Array[%s]" % get_type_hint_from_collection(base_type, true, false)
			else:
				base_type = "Dictionary"
	
	# this is special for these, can either handle 'enum::SomeEnum' or keep these
	if ClassDB.class_has_enum(base_type, identifier):
		if resolve_const:
			return Utils.type_path_add_type(Utils.type_path_add_member(base_type, identifier), "Enum")
			return "Enum"
		return Utils.type_path_add_type(Utils.type_path_add_member(base_type, identifier), "Enum")
		return UString.dot_join(base_type, identifier)
	elif ClassDB.class_has_integer_constant(base_type, identifier):
		var int_enum = ClassDB.class_get_integer_constant_enum(base_type, identifier)
		if int_enum != "":
			if resolve_const:
				return "Enum"
			return Utils.type_path_add_type(Utils.type_path_add_member(base_type, int_enum), "Enum")
			return UString.dot_join(base_type, int_enum)
		if resolve_const:
			return "int"
		return Utils.type_path_add_type(Utils.type_path_add_member(base_type, identifier), "int")
		return UString.dot_join(base_type, identifier)
	
	var result = BuiltInChecker.get_member_type(base_type, identifier)
	return result



func _variant_type_check(type_hint:String, type_cast_check:=true):
	if type_cast_check:
		_initialize_op_regexes()
		var as_check = _check_for_type_cast(type_hint)
		if as_check != "":
			return as_check
	
	if type_hint.ends_with(CALLABLE_SUFFIX):
		return ""
	if type_hint.ends_with(SIGNAL_SUFFIX):
		return ""
	
	if BuiltInChecker.is_builtin_class(type_hint):
		return type_hint
	if type_hint in OTHER_TYPES:
		return type_hint
	
	if type_hint == "true" or type_hint == "false":
		return "bool"
	elif type_hint.is_valid_int():
		return "int"
	elif type_hint.is_valid_float():
		return "float"
	elif type_hint.begins_with("[") and type_hint.ends_with("]"):
		return "Array"
	elif type_hint.begins_with("{") and type_hint.ends_with("}"):
		return "Dictionary"
	elif type_hint.begins_with("&"):
		if Utils.token_is_string(type_hint.trim_prefix("&")):
			return "StringName"
	elif type_hint.begins_with("^"):
		if Utils.token_is_string(type_hint.trim_prefix("^")):
			return "NodePath"
	elif Utils.token_is_string(type_hint):
		return "String"
	elif type_hint.begins_with("typedarray::"):
		return "Array[%s]" % type_hint.get_slice("::", 1).trim_suffix(Keys.INS_DELIM)
	elif type_hint.begins_with("Array"): # for Array[SomeType]
		var arr_hint = type_hint.substr(5).strip_edges()
		if arr_hint.begins_with("["):
			return "Array" + arr_hint
	elif type_hint.begins_with("Dictionary"): # for keyed dicts Dictionary[Key, Val]
		var type_pair = type_hint.substr(10).strip_edges()
		if type_pair.begins_with("["):
			return "Dictionary" + type_pair
	elif type_hint.begins_with("f"): # will this cause issues?
		if type_hint.begins_with("func ") or type_hint.begins_with("func("):
			return "Callable"
	
	
	if ClassDB.class_exists(type_hint):
		return type_hint
	
	# TEST this would force these to be handled via recursion and give a fully typed path
	#var current_script = _get_parser_main_script()
	#var base = current_script.get_instance_base_type()
	#if (
		##ClassDB.class_has_enum(base, type_hint) or
		##ClassDB.class_has_integer_constant(base, type_hint) or 
		#ClassDB.class_has_method(base, type_hint) or 
		#ClassDB.class_has_signal(base, type_hint)
		#):
		#return UString.dot_join(base, type_hint)
	# TEST
	
	return ""


static func get_type_hint_from_collection(string:String, value:bool=false, add_ins:bool=true) -> String:
	var type_check = Utils.type_path_get_type(string)
	if type_check != "":
		string = type_check
	if string.begins_with("Packed"):
		return BuiltInChecker.get_variant_index_access_type(string)
	if not string.contains("["):
		return "Variant"
	if string.begins_with("Array"):
		var type = string.get_slice("[", 1).get_slice("]", 0).strip_edges()
		if not add_ins:
			return type
		return Utils.type_path_add_ins(type)
	elif string.begins_with("Dictionary"):
		var key_pair = string.get_slice("[", 1).get_slice("]", 0)
		var type:String
		if value:
			type = key_pair.get_slice(",", 1).strip_edges()
		else:
			type = key_pair.get_slice(",", 0).strip_edges()
		if not add_ins:
			return type
		return Utils.type_path_add_ins(type)
	return "Variant"

func get_index_access_in_string(string:String):
	var string_map:GDScriptParser.UString.StringMap = _get_parser().get_string_map(string)
	var matches:Array[String] = []
	var i = 0
	while i < string.length():
		if string_map.string_mask[i] == 1:
			i += 1
			continue
		var _char = string[i]
		if _char == "[":
			var close = string_map.bracket_map[i] + 1
			matches.append(string.substr(i, close - i))
			i = close
			continue
		
		i += 1
	matches.reverse()
	return matches


func _check_for_type_cast(type_hint:String):
	_initialize_op_regexes()
	var parser = Utils.ParserRef.get_parser(self)
	var string_map:UString.StringMap
	var as_matches = _as_regex.search_all(type_hint)
	if not as_matches.is_empty():
		string_map = parser.get_string_map(type_hint)
		for m in as_matches:
			var i = m.get_start(0)
			if string_map.index_in_string_or_comment(i) or string_map.get_tightest_bracket_set(i) != -1:
				continue
			var cast = m.get_string(1).strip_edges()
			if BuiltInChecker.is_variant_type(cast):
				return cast
			
			return cast + Keys.INS_DELIM
	return ""


func _check_for_ternary_operation(text: String, class_data:ClassData):
	_initialize_op_regexes()
	var parser = Utils.ParserRef.get_parser(self)
	var string_map = parser.get_string_map(text)
	
	var true_expr = ""
	var false_expr = ""
	
	for m:RegExMatch in _ternary_if_regex.search_all(text):
		var i = m.get_start()
		if string_map.index_in_string_or_comment(i) or string_map.get_tightest_bracket_set(i) != -1:
			continue # Find the depth 0 'if'
		true_expr = text.substr(0, i).strip_edges()
		break
	
	if true_expr == "":
		return "" # no depth 0 'if', not ternary
	
	for m in _ternary_else_regex.search_all(text):
		var i = m.get_start()
		if string_map.index_in_string_or_comment(i) or string_map.get_tightest_bracket_set(i) != -1:
			continue # find the depth 0 'else'
		false_expr = text.substr(m.get_end()).strip_edges()
		break
	
	var true_type = _resolve_expression_to_type(true_expr, class_data)
	var true_check = Utils.type_path_get_type(true_type)
	if true_check != "":
		true_type = true_check
	if true_check == "Variant": # at this point, it will always return variant
		return "Variant"
	var false_type = _resolve_expression_to_type(false_expr, class_data)
	var false_check = Utils.type_path_get_type(false_type)
	if false_check != "":
		false_type = false_check
	
	if true_type == false_type:
		return true_type
	else:
		return "Variant" # mismatch, fallback to variant


func _check_for_bool_or_bitwise_operation(type_hint:String):
	_initialize_op_regexes()
	var parser = Utils.ParserRef.get_parser(self)
	var string_map = parser.get_string_map(type_hint)
	var bit_matches = _bitwise_op_regex.search_all(type_hint)
	for m in bit_matches:
		var i = m.get_start(0)
		if string_map.index_in_string_or_comment(i):
			continue
		if string_map.get_tightest_bracket_set(i) != -1:
			continue
		return "int"
	
	var bool_matches = _bool_op_regex.search_all(type_hint)
	for m in bool_matches:
		var i = m.get_start(0)
		if string_map.index_in_string_or_comment(i):
			continue
		if string_map.get_tightest_bracket_set(i) != -1:
			continue
		return "bool"
	return ""


func _check_for_math_operation(type_hint:String):
	_initialize_op_regexes()
	var parser = Utils.ParserRef.get_parser(self)
	var string_map = parser.get_string_map(type_hint)
	var compare_matches = _compar_op_regex.search_all(type_hint)
	for m in compare_matches:
		var i = m.get_start(0)
		if string_map.get_tightest_bracket_set(i) != -1:
			continue
		if string_map.index_in_string_or_comment(i):
			continue
		var indentifier = type_hint.substr(0, i)
		return indentifier.strip_edges()
	return ""


func _get_script_member_type(line:int, column:int=0): # thjs could be a bit more efficient, if not needed, could use what you got already, 
	var code_edit_parser = _get_code_edit_parser() # but also maybe speeding up scan by not getting types could be good
	var get_type_data = code_edit_parser.get_type_from_line(line, column)
	var result = get_type_data.get("result")
	if result == null:
		return ""
	elif result is Array and result.is_empty():
		return ""
	var dec_type = get_type_data.get("type", &"")
	if dec_type == Keys.MEMBER_TYPE_FOR:
		return Utils.get_type_from_for_info(result)
	elif dec_type == Keys.MEMBER_TYPE_CONST:
		var assignment = result[2]
		if Utils.is_absolute_path(assignment):
			var ext = assignment.get_extension()
			if ext == "tres" or ext == "res":
				assignment = Utils.type_path_add_ins(assignment)
		return assignment # assigned text
	elif dec_type == Keys.MEMBER_TYPE_VAR or dec_type == Keys.MEMBER_TYPE_STATIC_VAR:
		return Utils.get_type_from_var_info(result)
	elif dec_type == Keys.MEMBER_TYPE_ENUM:
		var parser = Utils.ParserRef.get_parser(self)
		var class_at_line = parser.get_class_object(parser.get_class_at_line(line)) as ParserClass
		var access = UString.dot_join(class_at_line.main_script_path, class_at_line.access_path)
		#var access = UString.dot_join(class_at_line.access_path, result[0] + Keys.ENUM_PATH_SUFFIX)
		return Utils.type_path_add_member(access, result[0] + Keys.ENUM_PATH_SUFFIX)
	elif dec_type == Keys.MEMBER_TYPE_CLASS:
		var parser = Utils.ParserRef.get_parser(self)
		var class_at_line = parser.get_class_object(parser.get_class_at_line(line)) as ParserClass
		var access = UString.dot_join(class_at_line.access_path, result[0])
		return UString.dot_join(class_at_line.main_script_path, access)
	elif dec_type == Keys.MEMBER_TYPE_FUNC or dec_type == Keys.MEMBER_TYPE_STATIC_FUNC:
		return result.get(Keys.FUNC_NAME, "")
	elif dec_type == Keys.MEMBER_TYPE_SIGNAL:
		return "Signal" # maybe this should append tag like the above?
	
	return ""


func resolve_preload(preload_call:String, class_obj:ParserClass):
	# at this point, this should not be a path, that would have been handled already
	var preload_string = preload_call.get_slice("preload", 1).strip_edges()
	if not preload_string.begins_with("("):
		return ""
	#preload_string = preload_string.trim_prefix("(").trim_suffix(")").strip_edges()
	preload_string = preload_string.trim_prefix("(").substr(0, preload_string.find(")")).strip_edges()
	
	var path = Utils.run_expression(preload_string, class_obj.script_resource)
	if path == "":
		return ""
	if not Utils.is_absolute_path(path):
		path = Utils.ensure_absolute_path(path, class_obj.main_script_path)
	else:
		path = UFile.uid_to_path(path)
	
	if path.get_extension() == "tres" or path.get_extension() == "res":
		path = Utils.type_path_add_ins(path)
	return path


func member_in_class_or_local_vars(identifier:String, class_obj:ParserClass, local_vars:Dictionary):
	var in_members = class_obj.has_script_member(identifier) or local_vars.has(identifier)
	return in_members

func check_global_or_autoload(identifier:String) -> String:
	var global = UClassDetail.get_global_class_path(identifier)
	if not global.is_empty():
		return global
	return autoload_cache.get(identifier, "")

func set_autoload_cache():
	if autoload_cache == null:
		autoload_cache = {}
	
	var valid_scripts = {}
	for data:Dictionary in ProjectSettings.get_property_list():
		if not data.name.begins_with("autoload/"):
			continue
		var autoload_name = data.name
		var autoload_path = ProjectSettings.get_setting(autoload_name)
		if not autoload_path.begins_with("*"):
			continue
		
		autoload_name = autoload_name.trim_prefix("autoload/")
		autoload_path = UFile.uid_to_path(autoload_path.trim_prefix("*"))
		
		if autoload_cache.has(autoload_name) and autoload_path == autoload_cache[autoload_name]:
			valid_scripts[autoload_name] = autoload_path
			continue
		
		if autoload_path.get_extension() == "gd":
			pass
		elif autoload_path.get_extension() == "cs":
			continue
		else:
			autoload_path = ALibRuntime.Utils.UResource.UPackedScene.ReadFile.get_root_script_path(autoload_path)
			if autoload_path == "":
				continue
		
		valid_scripts[autoload_name] = autoload_path
	
	autoload_cache = valid_scripts


func _get_parser_for_script(script_path:String):
	var parser = Utils.ParserRef.get_parser(self)
	return parser.get_parser_for_path(script_path)

func _get_parser_and_class_for_script(full_script_path:String):
	var parser = Utils.ParserRef.get_parser(self)
	var script_data = Utils.type_path_get_script_data(full_script_path)
	var script_path = script_data[0]
	var class_access = script_data[1]
	return parser.get_parser_and_class_obj(script_path, class_access)


func get_class_data_at_line(line:int) -> ClassData:
	var parser = Utils.ParserRef.get_parser(self)
	var class_data = ClassData.new(parser, line)
	return class_data




#endregion


#region InferenceContext

func _get_or_instance_inf_context():
	var inf_context = get_inference_context()
	if not is_instance_valid(inf_context):
		inf_context = InferenceContext.new()
		inference_context = inf_context
		set_inference_context(inf_context)
	return inf_context

func _get_inf_expression(class_data:ClassData, expression:String):
	return class_data.class_obj.get_script_class_path() + "::" + class_data.func_name + "::" + expression

func _check_inf_expression(inf_context:InferenceContext, inf_expression:String):
	if inf_context.has_expression(inf_expression):
		inf_context.finish_expression(inf_expression, "Variant")
		return "Variant"
	else:
		inf_context.start_expression(inf_expression)

func _check_inf_on_exit():
	if is_instance_valid(inference_context):
		inference_context = null

func _check_inf_find_origin():
	var inf_context = get_inference_context()
	if not inf_context:
		return false
	return inf_context.find_origin

#endregion


func _initialize_op_regexes():
	if not is_instance_valid(_ternary_if_regex):
		_ternary_if_regex = RegEx.new()
		_ternary_if_regex.compile("\\bif\\b")
	if not is_instance_valid(_ternary_else_regex):
		_ternary_else_regex = RegEx.new()
		_ternary_else_regex.compile("\\belse\\b")
	if not is_instance_valid(_ternary_regex):
		_ternary_regex = RegEx.new()
		_ternary_regex.compile("\\bif\\b.*?\\belse\\b")
	
	if not is_instance_valid(_as_regex):
		_as_regex = RegEx.new() # this should remove all doubt
		_as_regex.compile(r"\bas\s+([A-Za-z_][A-Za-z0-9_]*(\s*\.\s*[A-Za-z_][A-Za-z0-9_]*)*(\s*\[([^\[\]]*|\[[^\[\]]*\])*\])?)")
		#_as_regex.compile("\\bas\\b")
	
	if not is_instance_valid(_bitwise_op_regex):
		_bitwise_op_regex = RegEx.new()
		_bitwise_op_regex.compile("(?:<<|>>|~|\\^(?![\"\'])|(?<!&)&(?!&|[\"\'])|(?<!\\|)\\|(?!\\|))")
	
	if not is_instance_valid(_bool_op_regex):
		_bool_op_regex = RegEx.new()
		_bool_op_regex.compile("(?:==|!=|<=|>=|<|>|&&|\\|\\||!|\\b(?:and|or|not|in)\\b)")
	
	if not is_instance_valid(_compar_op_regex):
		_compar_op_regex = RegEx.new()
		_compar_op_regex.compile("(?:\\*\\*|\\*|\\/|%|(?<![eE])[+\\-])")




class ClassData:
	var valid_data:=true
	
	var initial_type_path:String = ""
	var initial_line:int
	var class_obj:ParserClass
	var func_obj:ParserFunc
	var func_name:String = ""
	var local_vars:Dictionary = {}
	
	func _init(parser:GDScriptParser, line:int) -> void:
		initial_line = line
		class_obj = parser.get_class_object(parser.get_class_at_line(initial_line))
		if not is_instance_valid(class_obj):
			valid_data = false
			return
		var function_name = class_obj.get_function_at_line(initial_line)
		if function_name != Keys.CLASS_BODY:
			func_name = function_name
			func_obj = class_obj.get_function(function_name)
			if is_instance_valid(func_obj):
				func_obj.parse()
				local_vars = func_obj.get_in_scope_local_vars(initial_line)
	
	func in_static_function():
		if is_instance_valid(func_obj):
			return func_obj.is_static()
		return false


#! keys type:String origin:String  member_stack:Array is_instance:bool
static func get_empty_type_rich():
	return {"type": "", "origin": "", "member_stack": [], "is_instance": false}

#! arg_location section:T
static func print_deb(section:String, ...msg:Array):
	if not PRINT_DEBUG:
		return
	if section in _PRINT:
		msg.push_front(section)
		ALibEditor.PrintDebug.print(msg)

static func print_deb_err(section:String, ...msg:Array):
	if not PRINT_DEBUG:
		return
	if section in _PRINT:
		msg.push_front(section)
		ALibEditor.PrintDebug.print_err(msg)

const _PRINT = [
	#T.BUILTIN,
	#T.INHERITED,
	#T.VAR_TO_CONST,
	T.RESOLVE,
	#T.ACCESS_PATH
	]


class T:
	const RESOLVE = "RESOLVE"
	const BUILTIN = "BUILTIN"
	const INHERITED = "INHERITED"
	const VAR_TO_CONST = "VAR TO CONST"
	const ACCESS_PATH = "ACCESS PATH"
	const TYPE_ORIGIN = "TYPE_ORIGIN"




#^r The Graveyard

#^r THESE MAY BE OBSOLETE








func _find_inheriting_script(identifier:String, class_obj:ParserClass):
	var inherited_scripts = class_obj.get_inherited_scripts()
	for path in inherited_scripts:
		var parser_data = _get_parser_and_class_for_script(path)
		#var parser = _get_parser_for_script(path)
		var inh_class = parser_data.get(Keys.GET_CLASS_OBJ) as ParserClass
		if inh_class.has_script_member(identifier):
			return path
	return ""


# this is only used in the inner class type check, I don't think it needs to be here
func _simple_type_check(type_hint:String, exit_check:=false):
	
	if exit_check:
		var type_check = Utils.type_path_get_type(type_hint)
		if type_check != "":
			return type_check
	
	_initialize_op_regexes()
	var as_check = _check_for_type_cast(type_hint)
	if as_check != "":
		return as_check
	
	
	if BuiltInChecker.is_builtin_class(type_hint):
		return type_hint
	if type_hint in OTHER_TYPES:
		return type_hint
	if type_hint.begins_with("uid:"):
		return UFile.uid_to_path(type_hint)
	#if type_hint.begins_with("res://"):
	if Utils.is_absolute_path(type_hint):
		return Utils.file_path_to_type(type_hint) # do this here?
		#return type_hint
	
	
	if type_hint == "true" or type_hint == "false":
		return "bool"
	elif type_hint.is_valid_int():
		return "int"
	elif type_hint.is_valid_float():
		return "float"
	elif type_hint.begins_with("[") and type_hint.ends_with("]"):
		return "Array"
	elif type_hint.begins_with("{") and type_hint.ends_with("}"):
		return "Dictionary"
	elif type_hint.begins_with("&"):
		if Utils.token_is_string(type_hint.trim_prefix("&")):
			return "StringName"
	elif type_hint.begins_with("^"):
		if Utils.token_is_string(type_hint.trim_prefix("^")):
			return "NodePath"
	elif Utils.token_is_string(type_hint):
		return "String"
	elif type_hint.begins_with("typedarray::"):
		return "Array[%s]" % type_hint.get_slice("::", 1).trim_suffix(Keys.INS_DELIM)
	elif type_hint.begins_with("Array"): # for Array[SomeType]
		var arr_hint = type_hint.get_slice("Array", 1).strip_edges()
		if arr_hint.begins_with("["):
			return "Array" + arr_hint
	elif type_hint.begins_with("Dictionary"): # for keyed dicts Dictionary[Key, Val]
		var type_pair = type_hint.get_slice("Dictionary", 1).strip_edges()
		if type_pair.begins_with("["):
			return "Dictionary" + type_pair
	elif type_hint.begins_with("f"): # will this cause issues?
		if type_hint.begins_with("func ") or type_hint.begins_with("func("):
			return "Callable"
	
	
	if ClassDB.class_exists(type_hint):
		return type_hint
	var current_script = _get_parser_main_script()
	var base = current_script.get_instance_base_type()
	if (ClassDB.class_has_enum(base, type_hint) or ClassDB.class_has_integer_constant(base, type_hint) or 
	ClassDB.class_has_method(base, type_hint) or ClassDB.class_has_signal(base, type_hint)):
		return UString.dot_join(base, type_hint)
	
	return ""


#^r BELOW ARE FOR SURE

### Get script member info, ignores Godot Native class inheritance properties.
#func get_script_member_info_by_path(script:GDScript, member_path:String, member_hints:=UClassDetail._MEMBER_ARGS, check_global:=true):
	#return UClassDetail.get_member_info_by_path(script, member_path, member_hints, false, false, false, check_global)

#func _find_member_inheriting_script(identifier:String, script:GDScript):
	#var last_script = script
	#if get_script_member_info_by_path(script, identifier) == null:
		#return ""
	#var current_script = script.get_base_script()
	#while current_script != null:
		#if get_script_member_info_by_path(current_script, identifier) == null:
			#break
		#last_script = current_script
		#current_script = current_script.get_base_script()
	#return last_script.resource_path


#func _var_to_const_get_inh_func_return(identifier:String, class_obj:ParserClass, first_const:=false):
	#var inh_script_path = _find_inheriting_script(identifier, class_obj)
	#var parser_data = _get_parser_and_class_for_script(inh_script_path)
	#var inh_class_obj = parser_data.get(Keys.GET_CLASS_OBJ)
	#
	##var script_data = UString.get_script_path_and_suffix(inh_script_path)
	##var parser = _get_parser_for_script(script_data[0])
	##var inh_class_obj = parser.get_class_object(script_data[1])
	#var function = inh_class_obj.get_function(identifier) as ParserFunc
	#var return_type = function.get_return_type_raw()
	#print_deb(T.VAR_TO_CONST, return_type)
	#return return_type

#func _get_inherited_func_return(identifier:String, class_obj:ParserClass, inferred:=true):
	#
	#var member_data = class_obj.get_inherited_member(identifier)
	#if member_data != null:
		#var script_path = member_data.get(Keys.SCRIPT_PATH)
		#if script_path != null:
			#var access_path = member_data.get(Keys.ACCESS_PATH)
			#var parser = _get_parser_for_script(script_path)
			#var next_class = parser.get_class_object(access_path)
			#var funct = next_class.get_function(identifier)
			#if is_instance_valid(funct):
				#return funct.get_return_type(inferred)
			#return ""
	#
	#var inh_script_path = _find_member_inheriting_script(identifier, class_obj.script_resource)
	#var parser_data = _get_parser_and_class_for_script(inh_script_path)
	##var parser = _get_parser_for_script(inh_script_path)
	##var inh_class_obj = parser.get_class_object()
	#var inh_class_obj = parser_data.get(Keys.GET_CLASS_OBJ)
	#var function = inh_class_obj.get_function(identifier) as ParserFunc
	#if is_instance_valid(function):
		#return function.get_return_type(inferred)
	#return ""

#^r THESE MAY BE OBSOLETE
