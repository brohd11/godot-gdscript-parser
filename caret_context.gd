
const GDScriptParser = preload("res://addons/addon_lib/brohd/alib_runtime/utils/resource/gdscript/parser/gdscript_parser.gd")
const CodeEditParser = GDScriptParser.CodeEditParser
const Keywords = CodeEditParser.Keywords
const Utils = GDScriptParser.Utils
const ParserRef = Utils.ParserRef
const Keys = Utils.Keys
const UString = GDScriptParser.UString

const _MAP_BLOCKS = [Keywords.FOR, Keywords.MATCH]

enum TokenState {
	NONE,
	COMMENT,
	STRING,
	STRING_NAME,
	NODE_PATH_LITERAL,
	GET_NODE_PATH,
	GET_NODE_UNIQUE,
	ANNOTATION,
}

enum ExpressionState {
	NONE,
	DECLARATION,
	ASSIGNMENT,  # var x = | (Suggest variables, globals, functions)
	COMPARISON,      # if x == | (Suggest variables)
	TYPE_HINT,       # var x: |  (Suggest Classes, Enums, built-in types. Replaces TYPE_ASSIGNMENT)
	FUNCTION_CALL,   # my_func(|) (Suggest variables, show parameter hints)
	MEMBER_ACCESS,   # my_obj.| (Suggest properties/methods of my_obj)
	INDEX_ACCESS, # my_obj[0] or my_dict["key"]
	
	DICT_DECL,       # var x = { | } (Suggest string keys or variables)
	ARRAY_DECL,      # var x = [ | ] 
}

enum ScopeState {
	CLASS_BODY,
	FUNCTION_BODY,
	MATCH_BRANCH,
	LOOP_BODY,
}



var _parser:WeakRef #
var _code_edit_parser:WeakRef
var code_edit:CodeEdit #

var token_state:TokenState
var expression_state:ExpressionState
var scope_state:ScopeState


var caret_column:int= -1 #
var caret_line:int= -1 #

var current_class:String
var current_function:String


var _completion_text:String
var current_line_text:String

var code_context_caret_pos:int
var code_context:String #
var code_context_stripped:String
var code_context_string_map:UString.StringMap #

var expression_before_caret:String

var word_before_caret:String #
var char_before_caret:String #

var _index_access_identifier:String = ""

var _operation_data:OperationData #
var _active_function_call:FunctionCallData #

var line_declaration:String = ""




var closest_bracket_index_paren:int=-1
var closest_bracket_index_square:int=-1
var closest_bracket_index_curly:int=-1
var closest_bracket_type:=""


var type_assignment:String

var function_blocks:= []

static var _assignment_regex:RegEx
static var _type_assignment_regex:RegEx

func _init(parser:GDScriptParser, parse_context:=true) -> void:
	Utils.ParserRef.set_refs(self, parser)
	code_edit = parser.code_edit
	
	caret_column = code_edit.get_caret_column()
	caret_line = code_edit.get_caret_line() # set these here so you can overide if wanted
	if parse_context:
		parse()


func parse():
	var t = ALibRuntime.Utils.UProfile.TimeFunction.new("CARET CONTEXT")
	var parser = ParserRef.get_parser(self)
	var code_edit_parser = ParserRef.get_code_edit_parser(self)
	
	current_line_text = code_edit_parser.get_line(caret_line)
	var caret_left = current_line_text.substr(0, caret_column).strip_edges(false, true)
	
	var params = {Keys.CONTEXT_LOCAL_VARS:true, Keys.CONTEXT_BLOCKS: _MAP_BLOCKS}
	var code_context_start_data = code_edit_parser.get_line_context_start_data(caret_line, params)
	function_blocks = code_context_start_data.get(Keys.CONTEXT_BLOCKS, [])
	var context_data = code_edit_parser.get_line_context(caret_line, caret_column, true, code_context_start_data)
	code_context = context_data.get(Keys.CONTEXT_TEXT)
	code_context_stripped = code_context.strip_edges()
	print(code_context)
	code_context_caret_pos = code_context.find(Keys.CARET_UNI_CHAR)
	code_context_string_map = parser.get_string_map(code_context)
	
	current_class = parser.get_class_at_line(caret_line)
	current_function = parser.get_function_at_line(caret_line)
	if current_function != Keys.CLASS_BODY:
		var current_class_obj = parser._class_access.get(current_class) as GDScriptParser.ParserClass
		if is_instance_valid(current_class_obj):
			var current_func_obj = current_class_obj.functions.get(current_function) as GDScriptParser.ParserFunc
			if is_instance_valid(current_func_obj):
				#current_func_obj.parse()
				print("&*&*")
				print(code_context_start_data)
				
				current_func_obj.set_in_scope_local_vars(code_context_start_data.get(Keys.CONTEXT_LOCAL_VARS, {}))
	
	
	word_before_caret = code_edit_parser.parse_identifier_at_position(caret_left, caret_left.length() - 1)
	expression_before_caret = code_edit_parser.parse_expression_at_position(code_context, code_context_caret_pos - 1, code_context_string_map)
	
	
	char_before_caret = _get_char_before_caret()
	
	var current_block = function_blocks.pop_back()
	var current_block_type = ""
	if current_block != null:
		current_block_type = current_block.get("type")
	
	line_declaration = CodeEditParser.get_line_declaration(code_context_stripped).strip_edges()
	
	_check_brackets()
	_set_function_call_data()
	_set_operation_at_caret()
	
	print("&*&*")
	print(_operation_data.left_text)
	
	#print("%s" % )
	
	var in_class_body = current_function == Keys.CLASS_BODY
	
	token_state = TokenState.NONE
	if code_edit.is_in_string(caret_line, caret_column) != -1:
		match _get_string_type():
			"&": token_state = TokenState.STRING_NAME
			"^": token_state = TokenState.NODE_PATH_LITERAL
			_: token_state = TokenState.STRING
	elif code_edit.is_in_comment(caret_line, caret_column) != -1:
		token_state = TokenState.COMMENT
	elif code_context.begins_with("@"):
		token_state = TokenState.ANNOTATION
	elif expression_before_caret.begins_with("$"):
		token_state = TokenState.GET_NODE_PATH
	elif expression_before_caret.begins_with("%"):
		var expr_index = code_context_rfind(expression_before_caret, code_context_caret_pos)
		var id_before = code_edit_parser.parse_expression_at_position(code_context, expr_index - 1 , code_context_string_map)
		print("before::", id_before)
		if id_before.begins_with("'") or id_before.begins_with('"'):
			#print("FORMAT STRING")
			pass
		else:
			token_state = TokenState.GET_NODE_UNIQUE
	
	
	expression_state = ExpressionState.NONE
	if _is_in_type_assignment():
		expression_state = ExpressionState.TYPE_HINT
	elif word_before_caret.find(".") > -1:
		expression_state = ExpressionState.MEMBER_ACCESS
	elif closest_bracket_type != "":
		var idx = max(closest_bracket_index_curly, closest_bracket_index_square)
		_index_access_identifier = code_context_parse_expression(idx - 1)
		#print("before::", _index_access_identifier)
		if _index_access_identifier != "":
			expression_state = ExpressionState.INDEX_ACCESS
	elif _operation_data.is_valid:
		if _operation_data.operator == "=":
			expression_state = ExpressionState.ASSIGNMENT
		else:
			expression_state = ExpressionState.COMPARISON
	
	
	if in_class_body:
		scope_state = ScopeState.CLASS_BODY
	elif current_block_type == &"match":
		scope_state = ScopeState.MATCH_BRANCH
	else:
		scope_state = ScopeState.FUNCTION_BODY
	
	print("^&^&^&")
	print(word_before_caret)
	print(expression_before_caret)
	print(
"TOKEN STATE: %s
EXPRESSION STATE: %s
SCOPE STATE: %s" % [TokenState.keys()[token_state], ExpressionState.keys()[expression_state], ScopeState.keys()[scope_state]],
"\nIN ENUM: %s
IN DICT: %s" % [is_in_enum(), is_in_dictionary()]
	)
	t.stop()



func _get_char_before_caret():
	var text_to_process = current_line_text
	var i = caret_column - 1
	var _char = ""
	while i >= 0:
		_char = text_to_process[i]
		if _char != " ":
			break
		i -= 1
	return _char

func _get_string_type():
	var i = caret_column
	while i > 0:
		if code_context_string_map.string_mask[i] == 0:
			break
		i -= 1
	return code_context[i]

func _check_brackets():
	var bracket_map = code_context_string_map.bracket_map
	var bracket_map_keys = bracket_map.keys()
	bracket_map_keys.sort()
	
	for open in bracket_map_keys:
		if open > code_context_caret_pos:
			break
		var close = bracket_map.get(open)
		if not (open <= code_context_caret_pos and close >= code_context_caret_pos):
			continue
		var _char = code_context[open]
		if _char == "(":
			closest_bracket_index_paren = open
		elif _char == "[":
			closest_bracket_index_square = open
		elif _char == "{":
			closest_bracket_index_curly = open
		else:
			continue
	
	var closest_bracket_idx = max(closest_bracket_index_paren, closest_bracket_index_square, closest_bracket_index_curly)
	if closest_bracket_idx == -1:
		return
	closest_bracket_type = code_context[closest_bracket_idx]




func _get_assignment_at_caret():
	var text_to_process = code_context
	var caret_idx = code_context_caret_pos
	
	
	var assign_data = AssignmentData.new()
	
	#if line_text.rfind("=", caret_idx) == -1: # alternative to above, if not on right side no need to do
	if UString.rfind_index_safe(text_to_process, "=", caret_idx) == -1:
		return assign_data
	
	if not is_instance_valid(_assignment_regex):
		_assignment_regex = RegEx.new()
		var pattern = r"((?:var\s+)?\w+(?:\(.*?\))?(?:\.\w+(?:\(.*?\))?)*(?:\s*:\s*[\w.]+)?)\s*(=\s*=|:\s*=|!\s*=|=)(.*?)(?=\s*(?:or|and|&&|\|\|)|$)"
		_assignment_regex.compile(pattern)
	
	var matches = _assignment_regex.search_all(text_to_process)
	if not matches.is_empty():
		for i in range(matches.size() - 1, -1, -1):
			var _match = matches[i] as RegExMatch
			if _match.get_start(2) <= caret_idx:
				var best_match = _match
				var rhs = best_match.get_string(3).strip_edges()
				if rhs.find("=") > -1: #^ search for a 2nd assignment
					var nested_matches = _assignment_regex.search_all(rhs)
					for nm in range(nested_matches.size() - 1, -1, -1):
						var nested_match = nested_matches[nm]
						if nested_match.get_start(2) <= caret_idx:
							best_match = nested_match
							rhs = best_match.get_string(3).strip_edges()
				
				var lhs = best_match.get_string(1).strip_edges()
				#var last_char_idx = best_match.get_end(1) - 1
				var operator = best_match.get_string(2).strip_edges()
				
				#var and_index = lhs.rfind(" and ", caret_idx)
				var and_index = UString.rfind_index_safe(lhs, " and ", caret_idx)
				if and_index > -1:
					lhs = lhs.substr(and_index + 5)
				#var or_index = lhs.rfind(" or ", caret_idx)
				var or_index = UString.rfind_index_safe(lhs, " or ", caret_idx)
				if or_index > -1:
					lhs = lhs.substr(or_index + 4)
				#var bitwise_index = lhs.rfind("&&", caret_idx)
				var bitwise_index = UString.rfind_index_safe(lhs, "&&", caret_idx)
				if bitwise_index > -1:
					lhs = lhs.substr(bitwise_index + 2)
				
				lhs = lhs.trim_prefix("self.") #^ simple sub
				
				assign_data.left_text = lhs
				assign_data.operator = operator
				assign_data.right_text = rhs
				assign_data.is_valid = true
				return assign_data
	
	return assign_data


func get_operation_data() -> OperationData:
	if not _operation_data.is_valid or _operation_data.inferred:
		return _operation_data
	var parser = Utils.ParserRef.get_parser(self)
	var left = _operation_data.left_text
	if left.begins_with("var "):
		var data = Utils.get_var_or_const_info(left)
		if data != null:
			_operation_data.left_type = parser.get_identifier_type(data[1], caret_line)
	else:
		_operation_data.left_type = parser.get_identifier_type(left, caret_line)
		#var st = ""
		#for part in UString.split_member_access(left):
			#st = UString.dot_join(st,parser._type_lookup.resolve_identifier_to_global(left, parser.get_class_object(parser.get_class_at_line(caret_line)), caret_line))
		#_operation_data.test_left = st
		#print("TESTLEFT::",st)
	
	
	_operation_data.inferred = true
	return _operation_data



func _set_operation_at_caret():
	_operation_data = OperationData.new()
	var current_pos = code_context_caret_pos - 1
	
	# We use this to check if we accidentally passed a logical boundary (like 'and', 'or')
	var right_text = ""

	while current_pos >= 0:
		# 1. Skip strings completely
		if code_context_string_map.string_mask[current_pos] == 1:
			right_text = code_context[current_pos] + right_text
			current_pos -= 1
			continue
			
		var _char = code_context[current_pos]
		
		# 2. Skip closed brackets (This perfectly handles func(a == b) and arrays!)
		if _char == ")" or _char == "]" or _char == "}":
			var open_bracket = code_context_string_map.bracket_map.get(current_pos, current_pos)
			# Prepend the whole skipped block to right_text
			right_text = code_context.substr(open_bracket, current_pos - open_bracket + 1) + right_text
			current_pos = open_bracket - 1
			continue
			
		# 3. Hard Boundaries (If we hit a comma, newline, or open bracket, there is no operation here)
		if _char in [",", ";", "\n", "(", "[", "{"]:
			return
			
		# 4. Logical Word Boundaries (Stop if we crossed into a different expression)
		# E.g. "if x == 1 and |" -> we don't want to scan past 'and'
		if right_text.begins_with("and ") or right_text.begins_with("or "):
			return
			
		# 5. WE FOUND AN OPERATOR SYMBOL!
		if _char in ["=", "<", ">", "!", ":", "+", "-", "*", "/", "%"]:
			var op_end = current_pos
			var op_start = current_pos
			
			# Scan backwards to capture compound operators (like ==, !=, :=, <=)
			while op_start > 0:
				var prev_char = code_context[op_start - 1]
				if prev_char in ["=", "<", ">", "!", ":", "+", "-", "*", "/", "%"]:
					op_start -= 1
				else:
					break
			
			var operator_str = code_context.substr(op_start, op_end - op_start + 1)
			
			# Ignore the GDScript return type arrow "->"
			if operator_str == "->":
				right_text = operator_str + right_text
				current_pos = op_start - 1
				continue
				
			# Populate the OperationData
			_operation_data.operator = operator_str
			_operation_data.right_text = right_text.strip_edges()
			
			# 6. MAGIC: Use your existing function to cleanly grab the left side!
			_operation_data.left_text = code_context_parse_expression(op_start - 1)
			_operation_data.is_valid = true
			return

		# Keep building the text to the right of the operator
		right_text = _char + right_text
		current_pos -= 1





func is_in_function_call():
	return _active_function_call.is_valid

func get_function_call_data() -> FunctionCallData:
	if _active_function_call.inferred:
		return _active_function_call
	
	var full_call = _active_function_call.full_call
	
	var parser = Utils.ParserRef.get_parser(self)
	var parser_script = parser._script_path
	
	_active_function_call.function_data = parser.get_function_data(full_call, caret_line)
	
	#_active_function_call.return_type = parser.get_identifier_type(full_call, caret_line)
	
	
	_active_function_call.inferred = true
	return _active_function_call


func _set_function_call_data() -> void:
	_active_function_call = FunctionCallData.new()
	Utils.ParserRef.set_refs(_active_function_call, Utils.ParserRef.get_parser(self))
	
	if line_declaration.ends_with("func"):
		return
	if closest_bracket_index_paren == -1:
		return
	
	var code_edit_parser = ParserRef.get_code_edit_parser(self)
	
	var bracket_map = code_context_string_map.bracket_map
	var string_indexes = code_context_string_map.string_mask
	if code_context_string_map.has_errors:
		return
	
	var closed_bracket_index = code_context_string_map.bracket_map.get(closest_bracket_index_paren, -1)
	if closed_bracket_index == -1:
		return
	
	var func_full_call = code_edit_parser.parse_expression_at_position(code_context, closest_bracket_index_paren - 1, code_context_string_map)
	if func_full_call == "":
		return
	print("FULL CALL::", func_full_call)
	func_full_call = func_full_call.trim_prefix("self.") #^ simple check
	
	var args = []
	var current_arg_index = 0
	var start_idx = closest_bracket_index_paren + 1
	var count = start_idx

	while count < closed_bracket_index:
		if string_indexes[count] == 1:
			count += 1
			continue
			
		var _char = code_context[count]
		if _char == "(" or _char == "{" or _char == "[":
			count = bracket_map[count]
			continue
			
		if _char == ",":
			var arg_text = code_context.substr(start_idx, count - start_idx).strip_edges()
			args.append(arg_text)
			start_idx = count + 1
			
			if code_context_caret_pos > count:
				current_arg_index += 1
				
		count += 1
	
	var last_arg = code_context.substr(start_idx, closed_bracket_index - start_idx).strip_edges()
	args.append(last_arg)
	
	_active_function_call.is_valid = true
	_active_function_call.full_call = func_full_call
	_active_function_call.current_arguments = args
	_active_function_call.current_arg_index = current_arg_index




func _is_in_type_assignment():
	if not is_instance_valid(_type_assignment_regex):
		_type_assignment_regex = RegEx.new()
		var pattern = "(?:\\s*is not\\s+|\\s*is\\s+|\\s*as\\s+|\\s*extends\\s+|[\\w.]+\\s*:\\s*|\\->\\s*)([\\w.]*)$"
		_type_assignment_regex.compile(pattern)
	
	if code_context_caret_pos == 0:
		return false
	if is_in_dictionary() or line_declaration == "" or not code_context.begins_with("for "):
		return false # this should stop false positives
	
	var relevant_text = code_context.substr(0, code_context_caret_pos).strip_edges()
	if relevant_text == "":
		return false
	
	var _match = _type_assignment_regex.search(relevant_text)
	if _match:
		type_assignment = _match.get_string(1)
		return true
	return false



func get_index_access_identifier():
	return _index_access_identifier

func is_declaration():
	return line_declaration != ""

func is_in_enum():
	return closest_bracket_type == "{" and line_declaration == "enum"

func is_in_dictionary():
	return closest_bracket_type == "{" and line_declaration != "enum"

func is_in_array():
	return closest_bracket_type == "[" and _index_access_identifier == ""

func is_in_dictionary_access():
	
	pass



func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		print("FREE CC")

# API

func get_text_for_autocomplete():
	if _completion_text != "":
		return _completion_text
	return Utils.ParserRef.get_code_edit_parser(self).get_text_for_auto_complete(caret_line, caret_column)

func is_valid_code(line:int, col:int):
	return code_edit.is_in_string(line, col) == -1 and code_edit.is_in_comment(line, col) == -1

func code_context_find(what:String, from:int=-1, string_safe:=true):
	if string_safe:
		return UString.string_safe_find(code_context, what, from, code_context_string_map)
	return code_context.find(what, from)

func code_context_rfind(what:String, from:int=-1, string_safe:=true):
	if string_safe:
		return UString.string_safe_rfind(code_context, what, from, code_context_string_map)
	return UString.rfind_index_safe(code_context, what, from)

func code_context_parse_expression(start_pos:int):
	return ParserRef.get_code_edit_parser(self).parse_expression_at_position(code_context, start_pos, code_context_string_map)


class AssignmentData:
	var is_valid:=false
	var inferred:=false
	
	var left_text:String
	var left_type:String
	var operator:String
	var right_text:String


class OperationData:
	
	var is_valid:=false
	var inferred:=false
	
	var test_left
	
	var left_text:String
	var left_type:String
	var operator:String
	var right_text:String
	
	func get_left_declaration():
		
		pass




class FunctionCallData:
	var _parser:WeakRef #
	var _code_edit_parser:WeakRef
	
	
	var is_valid:=false
	var inferred:=false
	
	var caller:String
	
	var full_call:String
	var full_call_typed:String
	var function_data:Dictionary
	
	var current_arguments:=[]
	var current_arg_index:int = -1
	
	func get_text_current_arg() -> String:
		if current_arg_index == -1:
			return ""
		return current_arguments[current_arg_index]
	
	func func_get_current_arg_declaration():
		var current_arg_data = _func_get_current_arg_data()
		if current_arg_data == null:
			return ""
		return current_arg_data.get(Keys.TYPE, "")
	
	func func_get_current_arg_type():
		var current_arg_data = _func_get_current_arg_data()
		if current_arg_data == null:
			return ""
		var arg_type_resolved = current_arg_data.get(Keys.TYPE_RESOLVED)
		if arg_type_resolved != null:
			return arg_type_resolved
		var arg_type = current_arg_data.get(Keys.TYPE)
		if arg_type.begins_with("res://"):
			return arg_type
		var parser = Utils.ParserRef.get_parser(self)
		var resolved = parser.get_identifier_type(arg_type)
		current_arg_data[Keys.TYPE_RESOLVED] = resolved
		return resolved
	
	func _func_get_current_arg_data():
		var arg_data = function_data.get(Keys.FUNC_ARGS, {})
		var arg_names = arg_data.keys()
		if current_arg_index >= arg_names.size():
			return
		var current_arg_name = arg_names[current_arg_index]
		return arg_data[current_arg_name]
	
	func func_get_return_type():
		return function_data.get(Keys.FUNC_RETURN, "No Type Found")
