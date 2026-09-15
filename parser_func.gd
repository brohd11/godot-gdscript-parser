
const PLUGIN_EXPORTED = false

const GDScriptParser = preload("uid://c4465kdwgj042") #! resolve ALibRuntime.Utils.UGDScript.Parser
const CodeEditParser = GDScriptParser.CodeEditParser
const Utils = GDScriptParser.Utils
const UString = GDScriptParser.UString
const Keys = Utils.Keys
const ParserRef = Utils.ParserRef

@warning_ignore_start("unused_private_class_variable")
var _parser:WeakRef
var _class_obj:WeakRef
var _code_edit_parser:WeakRef
@warning_ignore_restore("unused_private_class_variable")

var _cache_dirty:=true

var _cache:Dictionary = {} # not related to above member

var func_lines:PackedInt32Array
var declaration_line:int
var end_line:int
var class_indent:int = 0

var name:String
var member_data:Dictionary ={}

var empty_return_as_variant:bool =false # where to set this?
var _return_type_raw:String = ""
var _return_type_raw_line:int = -1
var _return_type:String = "" # done
var arguments:Dictionary = {} # done

var _has_static_return:bool=false

## All mapped local vars in function.
var local_vars:Dictionary = {}
var _local_vars_mapped:bool =false

## In scope local vars, set during type look up.
var in_scope_local_vars:Dictionary = {}
var _in_scope_local_vars_set:=false

## Assigned lambdas retain their binding key; inline callbacks use a source-position key.
var is_lambda:bool = false
var declaration_column:int = -1
var end_column:int = -1
var owner_variable:String = ""
## Immediate closures. Plain-text fills these lazily; read through get_lambdas().
var lambdas:Dictionary = {}

func contains_position(line:int, column:int = -1) -> bool:
	if line < declaration_line or line > end_line:
		return false
	if column < 0:
		return true
	return (line != declaration_line or column >= declaration_column) and \
		(line != end_line or end_column < 0 or column < end_column)

func set_lambdas(data:Dictionary) -> void:
	for local:Dictionary in local_vars.values():
		local.erase(Keys.LAMBDA)
	var updated:Dictionary = {}
	var code_parser:CodeEditParser = ParserRef.get_code_edit_parser(self)
	for key:String in data:
		var entry:Dictionary = data[key]
		updated[key] = create_lambda(key, entry, ParserRef.get_parser(self), ParserRef.get_class_obj(self),
			code_parser.get_indent_code_edit(entry.get(Keys.LINE_INDEX, declaration_line)), lambdas.get(key))
	lambdas = updated


func is_static() -> bool:
	return member_data.get(Keys.MEMBER_TYPE, "").begins_with("static")

func queue_refresh() -> void:
	_cache_dirty = true
	invalidate_line_caches()

## Drop only what is keyed by absolute line number. Local var keys embed the line
## ("%s-%s-%s" % [name, line, col], see _process_local_var), so a shifted func range voids them all.
## Split out of queue_refresh() so a line-range sync can skip the declaration re-read.
func invalidate_line_caches() -> void:
	_in_scope_local_vars_set = false
	in_scope_local_vars.clear() # not sure how this will interact with parse
	
	# these are not related to type lookup local vars
	_local_vars_mapped = false
	local_vars.clear()
	lambdas.clear() # keyed by local unique name, which embeds the line


func set_in_scope_local_vars(new_vars:Dictionary) -> void:
	_in_scope_local_vars_set = true
	end_line = func_lines[func_lines.size() - 1]
	_set_function_data()
	in_scope_local_vars = new_vars
	in_scope_local_vars.merge(arguments.duplicate())

func parse() -> void:
	end_line = func_lines[func_lines.size() - 1]
	_set_function_data()
	map_variables()




func _set_function_data() -> void:
	if not _cache_dirty:
		return
	_return_type = "" # ensure this doesn't get stuck
	
	var func_data:Dictionary
	if is_lambda:
		func_data = {"result": Utils.get_func_info(_get_lambda_parts()[0])}
	else:
		var column:int = member_data.get(Keys.COLUMN_INDEX, 0)
		var code_edit_parser:CodeEditParser = ParserRef.get_code_edit_parser(self)
		if not code_edit_parser.check_member_line(member_data.get(Keys.MEMBER_TYPE), name, declaration_line, column):
			GDScriptParser.print_deb_err(["FUNCTION DATA: NOT VALID"])
			return
		func_data = code_edit_parser.get_type_from_line(declaration_line, column)

	_has_static_return = true
	
	arguments.clear()
	var result:Variant = func_data.get("result")
	_cache_dirty = false # at this point it has been read
	if result == null:
		_return_type_raw = ""
		return
	if not result is Dictionary:
		GDScriptParser.print_deb_err([result, "::", name])
		#_cache_dirty = true # should this reset? this shouldn't happen
		return
	
	var arg_data:Dictionary = result.get(Keys.FUNC_ARGS, {})
	for arg:String in arg_data.keys():
		var arg_data_array:Array = arg_data[arg]
		var arg_type:String = arg_data_array[1]
		var arg_assign:String = arg_data_array[2]
		var has_static_type:bool = true
		if arg_type.is_empty():
			has_static_type = arg_data_array[3] # implicit type check
			arg_type = arg_assign
		elif not GDScriptParser.BuiltInChecker.is_variant_type(arg_type):
			arg_type = arg_type + Keys.INS_DELIM
		else:
			pass
		arguments[arg] = {
			Keys.TYPE: arg_type,
			Keys.ASSIGNMENT: arg_assign,
			Keys.HAS_STATIC_TYPE: has_static_type,
			Keys.MEMBER_TYPE: Keys.MEMBER_TYPE_FUNC_ARG,
			Keys.LINE_INDEX: declaration_line
			}
	
	var ret_str:String = result.get(Keys.FUNC_RETURN, "")
	if ret_str != "":
		ret_str = Utils.type_path_add_ins(ret_str)
	else:
		_has_static_return = false
	_return_type_raw = ret_str
	
	#print("SET FUNC DATA: ", result)

func has_static_return() -> bool:
	_set_function_data()
	return _has_static_return



## Scan current func for local vars and func data.
func map_variables() -> void:
	#print("MAP:", name, ":", _local_vars_mapped)
	if _local_vars_mapped:
		return
	var found_for_local_vars:Dictionary = {}
	
	_set_function_data()
	end_line = func_lines[func_lines.size() - 1]
	var code_edit_parser:CodeEditParser = ParserRef.get_code_edit_parser(self)
	if not is_lambda:
		set_lambdas(code_edit_parser.get_plain_lambdas(ParserRef.get_class_obj(self), self))
	if is_lambda and declaration_line == end_line:
		var body:String = _get_lambda_parts()[1]
		var body_column:int = code_edit_parser.get_line(declaration_line).find(body, declaration_column)
		var boundaries:Array[int] = []
		for token:Dictionary in CodeEditParser.LambdaScanner._tokens(body):
			if token.text != ";" or token.depth != 0:
				continue
			var inside_child:bool = false
			for child in lambdas.values():
				if child.contains_position(declaration_line, body_column + token.offset):
					inside_child = true
			if not inside_child:
				boundaries.append(token.offset)
		boundaries.append(body.length())
		var statement_start:int = 0
		for boundary:int in boundaries:
			var statement:String = body.substr(statement_start, boundary - statement_start)
			var stripped_statement:String = statement.strip_edges()
			if stripped_statement.begins_with("var "):
				var col:int = body_column + statement_start + statement.find(stripped_statement)
				_process_local_var(stripped_statement, declaration_line, col, found_for_local_vars)
			statement_start = boundary + 1
	for i:int in range(declaration_line + 1, end_line + 1): # +1 to ensure last line is carried over
		var inside_child:bool = false
		for child in lambdas.values():
			if i > child.declaration_line and i <= child.end_line:
				inside_child = true
				break
		if inside_child:
			continue
		if not code_edit_parser.is_valid_code(i, -1):
			continue
		
		var line_text:String = code_edit_parser.get_line(i)
		var stripped:String = line_text.strip_edges()
		var indent:int = code_edit_parser.get_indent_code_edit(i)
		var line_dec:StringName = GDScriptParser.CodeEditParser.get_line_declaration(stripped)
		if line_dec.is_empty() and not stripped.begins_with("for "):
			continue
		if indent <= class_indent:
			break
		
		var ctx_start_data = code_edit_parser.get_line_context_start_simple(i)
		var has_semi_cols:bool = ctx_start_data.get(Keys.CONTEXT_SEMI_COLON, false)
		
		
		if has_semi_cols:
			var data:Dictionary = code_edit_parser.get_semi_colon_strings(i)
			var cols = data.keys()
			var last_col = cols[cols.size() - 1]
			for column:int in cols:
				var text:String = data[column]
				if column == last_col:
					text = code_edit_parser.get_line_context_text(i, column)
				# column + 1 , accounts for the ';', works without, but mismatches with tree sitter
				_process_local_var(text.strip_edges(), i, column + 1, found_for_local_vars)
		else:
			var line_ctx:Dictionary = code_edit_parser.get_line_context(i)
			var context_text:String = line_ctx.get(Keys.CONTEXT_TEXT, "")
			var col:int = line_text.find(stripped)
			_process_local_var(context_text.strip_edges(), i, col, found_for_local_vars)
	
	for key:String in arguments.keys():
		var type_hint:String = arguments[key].get(Keys.TYPE)
		found_for_local_vars[_get_cache_string(key, type_hint)] = true
	
	for key:String in _cache.keys():
		if not found_for_local_vars.has(key):
			_cache.erase(key)
	
	_local_vars_mapped = true

func _process_local_var(stripped:String, line:int, col:int, found_vars:Dictionary) -> void:
	for child in lambdas.values():
		if child.contains_position(line, col):
			return
	var member_type:StringName = Keys.MEMBER_TYPE_VAR
	var is_for:bool = stripped.begins_with("for ")
	if is_for: # this should be regex
		member_type = Keys.MEMBER_TYPE_FOR
	
	var var_data:Variant
	if is_for:
		var_data = Utils.get_for_loop_info(stripped)
	else:
		var_data = Utils.get_var_or_const_info(stripped)
	if var_data != null:
		var var_name:String = var_data[0]
		var type_hint:String = var_data[1]
		var has_static_type:bool = true
		if type_hint.is_empty():
			if is_for:
				has_static_type = false
			else:
				has_static_type = var_data[3] # implicit type check
		
		var data:Dictionary = {
			Keys.MEMBER_NAME: var_name,
			Keys.LINE_INDEX: line,
			Keys.COLUMN_INDEX: col,
			Keys.MEMBER_TYPE: member_type,
			Keys.TYPE: type_hint,
			Keys.ASSIGNMENT: var_data[2],
			Keys.HAS_STATIC_TYPE: has_static_type,
		}
		var unique_name:String = "%s-%s-%s" % [var_name, line, col]
		local_vars[unique_name] = data
		found_vars[_get_cache_string(unique_name, type_hint)] = true
	

func get_local_var_member_data(member_name:String) -> Variant:
	if local_vars.has(member_name):
		return local_vars.get(member_name)
	elif arguments.has(member_name):
		return arguments.get(member_name)
	return

func get_local_var_type(member_name:String) -> String:
	var type_rich:Dictionary = get_local_var_type_rich(member_name)
	if type_rich:
		return type_rich.type
	return ""

#! keys i-GDScriptParser.resolve_expression_to_type_rich;
func get_local_var_type_rich(member_name:String) -> Dictionary:
	var is_arg:bool = arguments.has(member_name)
	var std_local:bool = local_vars.has(member_name)
	if not std_local and not is_arg:
		return GDScriptParser.TypeLookup.get_empty_type_rich()
	
	var parser:GDScriptParser = Utils.ParserRef.get_parser(self)
	var dec_line:int
	var var_data:Dictionary
	if is_arg:
		var_data = arguments.get(member_name)
		dec_line = declaration_line
	else:
		var_data = local_vars.get(member_name)
		dec_line = var_data.get(Keys.LINE_INDEX)
	
	var type_hint:String = var_data.get(Keys.TYPE, "")
	if type_hint == "":
		type_hint = var_data.get(Keys.ASSIGNMENT, "")
	if type_hint == "":
		return GDScriptParser.TypeLookup.get_empty_type_rich()
	
	var cache_string:String = _get_cache_string(member_name, type_hint)
	for i:int in range(1): # single loop for early break
		#break # ALERT
		if not GDScriptParser.CACHE_TYPES:
			break
		if not _cache.has(cache_string):
			break
		var cache_data:Dictionary = _cache[cache_string]
		if cache_data.get(Keys.CLASS_CACHE_DEC) != type_hint:
			break
		if not cache_data.has(Keys.CLASS_CACHE_DEPENDENCIES):
			break
		var cached_deps:Variant = cache_data.get(Keys.CLASS_CACHE_DEPENDENCIES)
		if not GDScriptParser.InferenceContext.validate_dependencies(cached_deps, parser.get_script_path()):
			break
		return cache_data.get(Keys.CLASS_CACHE_TYPE)
	
	var cached_data:Dictionary = _cache.get_or_add(cache_string, {})
	cached_data[Keys.CLASS_CACHE_DEC] = type_hint
	
	if member_name.contains("-"):
		member_name = member_name.get_slice("-", 0)
	
	var probe_line := dec_line + 1   # +1 forces the var to be in scope
	var seeded := false
	if not func_lines.has(probe_line) and not _in_scope_local_vars_set:
		# Terminal var: probe_line escaped this func (EOF / next-decl no-blank).
		# Resolve on the var's OWN line (which IS in func_lines, so ClassData -> self),
		# pre-seeding an in-scope set that includes this var itself.
		var scope: Dictionary = get_in_scope_local_vars(dec_line)          # priors + args
		var line_text: String = ParserRef.get_code_edit_parser(self).get_line(dec_line)
		Utils.add_var_to_dict(line_text.strip_edges(), dec_line, 0, scope) # add the terminal var
		set_in_scope_local_vars(scope)
		seeded = true
		probe_line = dec_line
	
	var type_rich: Dictionary = parser.resolve_expression_to_type_rich(member_name, probe_line)
	if seeded:
		_in_scope_local_vars_set = false
		in_scope_local_vars.clear()
	
	if type_rich.type != "" and type_rich.origin != "":
		cached_data[Keys.CLASS_CACHE_DEPENDENCIES] = GDScriptParser.InferenceContext.get_dependencies_from_member_stack(type_rich)
		cached_data[Keys.CLASS_CACHE_TYPE] = type_rich
	return type_rich

func is_local_var_static_typed(member_name:String) -> bool:
	var is_arg:bool = arguments.has(member_name)
	var std_local:bool = local_vars.has(member_name)
	if not std_local and not is_arg:
		return false
	
	var var_data:Dictionary
	if is_arg:
		var_data = arguments.get(member_name)
	else:
		var_data = local_vars.get(member_name)
	return var_data.get(Keys.HAS_STATIC_TYPE, false)


func get_in_scope_local_vars(line:int, column:int = -1) -> Dictionary:
	if _in_scope_local_vars_set and column < 0:
		return in_scope_local_vars
	
	var class_obj = ParserRef.get_class_obj(self)
	if is_instance_valid(class_obj):
		var stack:Array = class_obj.get_lambda_stack_at_line(line, column)
		if not stack.is_empty():
			return class_obj.get_in_scope_vars_at_line(line, stack, column)
	return _scan_in_scope_vars(line, -1, true, column)

## One upward indent scan for the locals at `line`. `stop_line` bounds it to a lambda body;
## `include_args` merges this func's args underneath the locals.
func _scan_in_scope_vars(line:int, stop_line:int = -1, include_args:bool = true, column:int = -1) -> Dictionary:
	var code_edit_parser:CodeEditParser = ParserRef.get_code_edit_parser(self)
	var context_data:Dictionary = code_edit_parser.get_line_context_start_data(line, {
		Keys.CONTEXT_BLOCKS: [Utils.Keywords.FOR],
		Keys.CONTEXT_STOP_LINE: stop_line,
		})
	var in_scope_vars:Dictionary = context_data.get(Keys.CONTEXT_LOCAL_VARS, {})
	if column >= 0:
		map_variables()
		var tokens:Array = CodeEditParser.LambdaScanner._tokens(code_edit_parser.get_line(line))
		for data:Dictionary in local_vars.values():
			if data.get(Keys.LINE_INDEX, -1) != line:
				continue
			var start:int = data.get(Keys.COLUMN_INDEX, -1)
			if ParserRef.get_class_obj(self).use_ts:
				start = _character_column(code_edit_parser, line, start)
			# A same-line declaration is visible after its terminating semicolon.
			for token:Dictionary in tokens:
				if token.text == ";" and token.offset > start and token.offset < column:
					in_scope_vars[data[Keys.MEMBER_NAME]] = data
					break
	if include_args:
		in_scope_vars.merge(arguments)
	return in_scope_vars

func get_function_data() -> Dictionary:
	var return_string:String = get_return_type()
	return {Keys.FUNC_ARGS: arguments.duplicate(), Keys.FUNC_RETURN:return_string}

func get_arguments_raw() -> Dictionary:
	var dict:Dictionary = {}
	if not _cache_dirty: # seems ok, but could this get out of sync?
		for a:String in arguments:
			dict[a] = true
		return dict
	
	var column:int = member_data.get(Keys.COLUMN_INDEX, 0)
	var code_edit_parser:CodeEditParser = ParserRef.get_code_edit_parser(self)
	if code_edit_parser.check_member_line(member_data.get(Keys.MEMBER_TYPE), name, declaration_line, column):
		var func_data:Dictionary = code_edit_parser.get_type_from_line(declaration_line, column)
		var result:Variant = func_data.get("result")
		if not result is Dictionary:
			GDScriptParser.print_deb_err(["GET ARG RAW", result, name])
			return {}
		if result:
			var func_args:Dictionary = result.get(Keys.FUNC_ARGS, {})
			for a:String in func_args:
				dict[a] = true
			return dict
	
	return {}
	

func get_arguments() -> Dictionary:
	_set_function_data()
	return arguments

func get_return_type(inferred:=true) -> String: # this could be used to parse
	_set_function_data()
	
	if _return_type_raw == "":
		_return_type_raw = _infer_return_type()
	
	if not inferred:
		return _return_type_raw
	
	if _return_type == "" or not Utils.is_absolute_path(_return_type):
		var parser:GDScriptParser = Utils.ParserRef.get_parser(self)
		var return_line:int = maxi(declaration_line, _return_type_raw_line)
		_return_type = parser.get_type_lookup().resolve_expression_to_type_at_line_respect_inf_context(_return_type_raw, return_line)
	
	if _return_type == "":
		_return_type = "Variant"
	
	_return_type = Utils.type_path_add_ins(_return_type)
	return _return_type

func get_return_type_raw() -> String:
	_set_function_data()
	if _return_type_raw == "":
		_return_type_raw = _infer_return_type()
	return _return_type_raw

func get_return_type_rich() -> Dictionary:
	_set_function_data()
	if _return_type_raw == "":
		_return_type_raw = _infer_return_type()
	
	var parser:GDScriptParser = Utils.ParserRef.get_parser(self)
	var return_line:int = maxi(declaration_line, _return_type_raw_line)
	var type_rich:Dictionary = parser.resolve_expression_to_type_rich(_return_type_raw, return_line)
	if type_rich.type == "":
		type_rich.type = "Variant"
	return type_rich

# this may be slowww, possibly do it in the mapping step
# other option would be to set a limit for indent, check only func level
func _infer_return_type() -> String:
	if is_lambda and func_lines.size() <= 1: # one-liner: the body shares the declaration line
		_return_type_raw_line = declaration_line
		var body:String = _get_lambda_parts()[1]
		if body == "return" or body.begins_with("return "):
			var returned:String = body.trim_prefix("return").strip_edges()
			if returned != "":
				return returned
		return "Variant" if empty_return_as_variant else "void"
	var code_edit_parser:CodeEditParser = Utils.ParserRef.get_code_edit_parser(self)
	var func_indent:int = class_indent + code_edit_parser.indent_size
	# technically this should be Variant, but this will behave similar to a return of a Variant where a return is necessary even if null
	# if not return statement at all is found, -> void, else Variant
	var potential_return:String = "void" 
	end_line = func_lines[func_lines.size() - 1]
	#var i = min(end_line + 1, code_edit_parser.code_edit.get_line_count() - 1)
	var i:int = end_line + 1
	while i > declaration_line + 1:
		i -= 1
		var line_text:String = code_edit_parser.get_line(i, true)
		if not line_text.strip_edges().begins_with("return"):
			continue
		if not code_edit_parser.is_valid_code(i, line_text.find("return")):
			continue
		var indent:int = code_edit_parser.get_indent_code_edit(i)
		
		potential_return = code_edit_parser.get_line_context(i, 0, false, {Keys.CONTEXT_START: i}).get(Keys.CONTEXT_TEXT, "")
		if indent == func_indent:
			break
		else:
			var valid:bool = false
			var nest_i:int = i
			while nest_i > declaration_line:
				nest_i -= 1
				var line:String = code_edit_parser.get_line(nest_i, true, true)
				if line == "":
					continue
				if not code_edit_parser.is_valid_code(nest_i, 0):
					continue
				var nest_indent:int = code_edit_parser.get_indent_code_edit(nest_i)
				if nest_indent >= indent:
					continue
				var func_idx:int = line.find("func")
				if func_idx == -1:
					valid = true
					break
				i = nest_i - 1
				break
			if valid:
				break
	
	
	_return_type_raw_line = i
	var raw_result:String = potential_return.strip_edges().trim_prefix("return").strip_edges()
	if raw_result == "":
		if empty_return_as_variant:
			return "Variant"
		return "void"
	
	#var parser = Utils.ParserRef.get_parser(self)
	#
	#_return_type = parser.resolve_expression_to_type(raw_result, i)
	#print("FUNC INFERRING::", raw_result, " -> ", _return_type)
	#print("FUNC INFER::", _return_type)
	return raw_result

static func get_local_var_unique_name(var_name:String, line:int, col:int):
	return "%s-%s-%s" % [var_name, line, col]

static func get_local_var_unique_name_from_data(var_name:String, data:Dictionary):
	if data.get(Keys.MEMBER_TYPE) == Keys.MEMBER_TYPE_FUNC_ARG:
		return var_name
	return get_local_var_unique_name(var_name, data.get(Keys.LINE_INDEX), data.get(Keys.COLUMN_INDEX))

func _get_cache_string(member_name:String, type_hint:String) -> String:
	return member_name + "::" + type_hint


#region Lambdas
## Build or refresh a closure, translating extension byte columns for CodeEdit lookups.
static func create_lambda(owner_name:String, lambda_data:Dictionary, parser:GDScriptParser, class_obj, owner_indent:int, existing:Variant = null) -> Variant:
	var lambda:Variant = existing
	if is_instance_valid(lambda):
		lambda.queue_refresh()
	else:
		lambda = GDScriptParser.ParserFunc.new()
		lambda.is_lambda = true
		lambda.name = owner_name
		ParserRef.set_refs(lambda, parser, class_obj)
	var start:int = lambda_data.get(Keys.LINE_INDEX, -1)
	var end:int = maxi(lambda_data.get(Keys.END_LINE, start), start)
	lambda.declaration_line = start
	lambda.func_lines = range(start, end + 1)
	lambda.end_line = end
	var code_parser:CodeEditParser = ParserRef.get_code_edit_parser(class_obj)
	lambda.declaration_column = _character_column(code_parser, start, lambda_data.get(Keys.COLUMN_INDEX, -1))
	lambda.end_column = _character_column(code_parser, end, lambda_data.get("end_column", -1))
	lambda.owner_variable = lambda_data.get("owner_variable", owner_name)
	lambda.class_indent = owner_indent
	lambda.member_data = {Keys.MEMBER_TYPE: Keys.MEMBER_TYPE_LAMBDA, Keys.MEMBER_NAME: owner_name, Keys.LINE_INDEX: start}
	var locals:Variant = lambda_data.get("locals")
	if locals is Dictionary: # tree-sitter collected the body already, nested lambdas included
		lambda.local_vars = locals.duplicate(true)
		lambda._local_vars_mapped = true
	if lambda_data.has("lambdas"):
		lambda.set_lambdas(lambda_data.lambdas)
	elif locals is Dictionary:
		lambda._create_lambdas_from_locals()
	return lambda

static func _character_column(code_parser:CodeEditParser, line:int, bytes:int) -> int:
	if bytes < 0 or line < 0:
		return -1
	return code_parser.get_line(line).to_utf8_buffer().slice(0, bytes).get_string_from_utf8().length()

## Tree-sitter hands locals over pre-collected; lift their `lambda` sub-dicts into ParserFuncs.
func _create_lambdas_from_locals() -> void:
	var code_edit_parser:CodeEditParser = ParserRef.get_code_edit_parser(self)
	for unique_name:String in local_vars.keys():
		var data:Dictionary = local_vars[unique_name]
		var lambda_data:Variant = data.get(Keys.LAMBDA)
		if lambda_data == null:
			continue
		data.erase(Keys.LAMBDA)
		var indent:int = code_edit_parser.get_indent_code_edit(data.get(Keys.LINE_INDEX, declaration_line))
		lambdas[unique_name] = create_lambda(unique_name, lambda_data, ParserRef.get_parser(self), ParserRef.get_class_obj(self), indent)

## Immediate assigned and inline lambdas; map the body lazily when needed.
func get_lambdas() -> Dictionary:
	ParserRef.get_code_edit_parser(self).ensure_lambda_data()
	map_variables()
	return lambdas

func get_lambda(unique_name:String) -> Variant:
	return get_lambdas().get(unique_name)

## [signature, body]: the signature rewritten as `func _lambda(args) -> T` so Utils.get_func_info
## normalizes it like a real func; body is the text after its `:` (used for one-liners).
func _get_lambda_parts() -> Array:
	var code_edit_parser:CodeEditParser = ParserRef.get_code_edit_parser(self)
	var text:String = code_edit_parser.get_line_context_text(declaration_line)
	if declaration_column >= 0:
		var lines:PackedStringArray = []
		for line:int in range(declaration_line, end_line + 1):
			var part:String = code_edit_parser.get_line(line)
			if line == end_line and end_column >= 0:
				part = part.left(end_column)
			if line == declaration_line:
				part = part.substr(declaration_column)
			lines.append(part)
		text = "\n".join(lines)
	var string_map = code_edit_parser.get_string_map(text)
	var eq:int = -1 if declaration_column >= 0 else UString.string_safe_find(text, "=", 0, string_map)
	var start:int = UString.string_safe_find(text, "func", maxi(eq, 0), string_map)
	var open:int = -1 if start == -1 else text.find("(", start)
	if open == -1:
		return ["", ""]
	var depth:int = 0
	var close:int = -1
	for i:int in range(open, text.length()):
		if string_map.string_mask[i] == 1:
			continue
		if text[i] == "(":
			depth += 1
		elif text[i] == ")":
			depth -= 1
			if depth == 0:
				close = i
				break
	if close == -1:
		return ["", ""]
	var rest:String = text.substr(close + 1)
	var colon:int = rest.find(":")
	var ret:String = rest.strip_edges() if colon == -1 else rest.substr(0, colon).strip_edges()
	var signature:String = "func _lambda(%s)" % text.substr(open + 1, close - open - 1)
	if ret.begins_with("->"):
		signature += " " + ret
	var body:String = "" if colon == -1 else rest.substr(colon + 1).strip_edges()
	return [signature, body]
#endregion
