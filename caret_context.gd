
const GDScriptParser = preload("res://addons/addon_lib/brohd/alib_runtime/utils/resource/gdscript/parser/gdscript_parser.gd")
const CodeEditParser = GDScriptParser.CodeEditParser
const Keywords = CodeEditParser.Keywords
const Utils = GDScriptParser.Utils
const ParserRef = Utils.ParserRef
const Keys = Utils.Keys
const UString = GDScriptParser.UString

const _MAP_BLOCKS = [Keywords.FOR, Keywords.MATCH]

enum State {
	NONE,
	COMMENT,
	STRING,
	ASSIGNMENT,
	FUNC_ARGS,
	MEMBER_ACCESS,
	SCRIPT_BODY,
	TYPE_ASSIGNMENT,
	ANNOTATION,
	BLOCK_MATCH,
}


var _parser:WeakRef #
var _code_edit_parser:WeakRef
var code_edit:CodeEdit #

var state:State

var caret_column:int= -1 #
var caret_line:int= -1 #

var completion_text:String

var current_line_text:String

var code_context_caret_pos:int
var code_context:String #
var code_context_string_map:UString.StringMap #

var word_before_caret:String #
var char_before_caret:String #

var func_call_data:FuncCallData #
var assignment_data:AssignmentData #

var caret_in_function_call:bool = false #
var caret_in_function_declaration:bool = false #
var caret_in_dict:bool = false #
var caret_in_enum:bool = false #
var caret_in_match:bool = false

var bracket_type:=""

var current_class:String
var current_function:String

var caret_in_type_assignment:bool = false
var type_assignment:String

var function_blocks = []

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
	var t = ALibRuntime.Utils.UProfile.TimeFunction.new("ALL CONTEXT")
	var parser = ParserRef.get_parser(self)
	var code_edit_parser = ParserRef.get_code_edit_parser(self)
	
	current_line_text = code_edit.get_line(caret_line)
	
	#completion_text = _get_text_for_auto_complete()
	var params = {&"map_local_vars":true, &"map_blocks": _MAP_BLOCKS}
	var code_context_start_data = code_edit_parser.get_line_context_start_data(caret_line, params)
	function_blocks = code_context_start_data.get(&"blocks", [])
	code_context = code_edit_parser.get_line_context(caret_line, caret_column, true, code_context_start_data)
	print(code_context)
	#print(code_context_start_data)
	code_context_caret_pos = code_context.find(Keys.CARET_UNI_CHAR)
	code_context_string_map = parser.get_string_map(code_context)
	
	word_before_caret = code_edit_parser.parse_identifier_at_position(current_line_text, caret_column - 1)
	char_before_caret = _get_char_before_caret()
	
	current_class = parser.get_class_at_line(caret_line)
	current_function = parser.get_function_at_line(caret_line)
	if current_function != Keys.CLASS_BODY:
		var current_class_obj = parser._class_access.get(current_class) as GDScriptParser.ParserClass
		if is_instance_valid(current_class_obj):
			var current_func_obj = current_class_obj.functions.get(current_function) as GDScriptParser.ParserFunc
			if is_instance_valid(current_func_obj):
				#current_func_obj.parse()
				current_func_obj.set_in_scope_local_vars(code_context_start_data.get(&"local_vars", {}))
	
	
	#gdscript_parser.on_completion_requested() #^ this needs to be before for get_current_func to work
	
	var current_block = function_blocks.pop_back()
	var current_block_type = ""
	if current_block != null:
		current_block_type = current_block.get("type")
		
	
	_set_caret_in_func_call() #^ check first to populate CARET_IN_FUNC
	_set_caret_in_bracket()
	_set_assignment_at_caret()
	_set_in_type_assignment()
	
	state = State.NONE
	if code_edit.is_in_string(caret_line, caret_column) != -1:
		state = State.STRING
	elif code_edit.is_in_comment(caret_line, caret_column) != -1:
		state = State.COMMENT
	elif caret_in_type_assignment:
		state = State.TYPE_ASSIGNMENT
	elif word_before_caret.find(".") > -1:
		state = State.MEMBER_ACCESS
	elif caret_in_function_call:
		state = State.FUNC_ARGS
	elif assignment_data.is_valid:
		state = State.ASSIGNMENT
	elif current_block_type == &"match":
		state = State.BLOCK_MATCH
	elif current_function == Keys.CLASS_BODY:
		if current_line_text.begins_with("@"):
			state = State.ANNOTATION
		else:
			state = State.SCRIPT_BODY
	
	print(State.keys()[state])
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

func _set_caret_in_bracket():
	var closest_bracket_idx = code_context_string_map.get_tightest_bracket_set(code_context_caret_pos)
	if closest_bracket_idx == -1:
		return
	bracket_type = code_context_string_map.string[closest_bracket_idx]
	if bracket_type != "{":
		return
	var bracket_stripped = code_context.substr(0, closest_bracket_idx)
	if code_context.strip_edges().begins_with("enum "):
		if bracket_stripped.begins_with("enum "):
			caret_in_enum = true
		return
	caret_in_dict = true


func _set_assignment_at_caret():
	assignment_data = _get_assignment_at_caret()
	if not assignment_data.is_valid:
		return
	var parser = Utils.ParserRef.get_parser(self)
	var left = assignment_data.left
	var left_typed = ""
	if left.begins_with("var "):
		#var trimmed = left.trim_prefix("var ") # not sure if this was causing issues?
		var data = Utils.get_var_name_and_type_hint_in_line(left)
		if data != null:
			left_typed = parser.get_identifier_type(data[1], caret_line)
	else:
		left_typed = parser.get_identifier_type(left, caret_line)
	
	assignment_data.left_typed = left_typed


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
				var last_char_idx = best_match.get_end(1) - 1
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
				
				assign_data.left = lhs
				assign_data.operator = operator
				assign_data.right = rhs
				assign_data.is_valid = true
				return assign_data
	
	return assign_data


#region Func Call
## Return func call state. Sets CARET_IN_FUNC cache status. Caret can be in func parentheses but not in func call state.
func _set_caret_in_func_call():
	var text_to_process = code_context
	var caret_idx = code_context_caret_pos
	
	var stripped = text_to_process.strip_edges()
	var in_declar = stripped.begins_with("func") or stripped.begins_with("static func")
	if in_declar:
		caret_in_function_declaration = true
	
	_set_func_call_data()
	if not func_call_data.is_valid or in_declar:
		#completion_cache[CompletionCache.CARET_IN_FUNC_CALL] = false
		return false
	
	caret_in_function_call = true
	var arg_text = func_call_data.args[func_call_data.arg_index]
	#var arg_text = func_data[EditorCodeCompletion.FuncCall.ARGS][func_data[EditorCodeCompletion.FuncCall.ARG_INDEX]]
	#if arg_text.rfind("=", current_caret_col) > -1: # does this work? May need adjusting
	if UString.rfind_index_safe(arg_text, "=", caret_idx) > -1:
		return false
	return true




func _set_func_call_data() -> void:
	var code_edit_parser = ParserRef.get_code_edit_parser(self)
	
	func_call_data = FuncCallData.new()
	
	var text_to_process = code_context
	var caret_idx = code_context_caret_pos
	
	if UString.rfind_index_safe(text_to_process, "(", caret_idx) == -1:
		return
	
	var string_map = code_edit_parser.get_string_map(text_to_process)
	var bracket_map = string_map.bracket_map
	var string_indexes = string_map.string_mask
	if string_map.has_errors or bracket_map.is_empty():
		return
	
	var open_bracket_index = string_map.get_tightest_bracket_set(caret_idx, "(")
	if open_bracket_index == -1:
		return
	var closed_bracket_index = string_map.bracket_map[open_bracket_index]
	
	var func_full_call = code_edit_parser.parse_identifier_at_position(text_to_process, open_bracket_index - 1)
	if func_full_call == "":
		return
	
	func_full_call = func_full_call.trim_prefix("self.") #^ simple check
	#print(func_full_call)
	var arg_idxs = []
	var current_arg_index = 0
	var count = closed_bracket_index
	while count >= open_bracket_index:
		count -= 1
		if string_indexes[count] == 1:
			continue
		var _char = text_to_process[count]
		if _char == ")" or _char == "}" or _char == "]":
			count = bracket_map[count]
		
		if _char == ",":
			if caret_idx > count:
				current_arg_index += 1
			arg_idxs.append(count)
	
	arg_idxs.reverse()
	var arg_array = []
	var start_index = open_bracket_index + 1
	for i in arg_idxs:
		var substr_length = i - start_index
		var arg = text_to_process.substr(start_index, substr_length).strip_edges()
		arg_array.append(arg)
		start_index = i + 1
	
	var last_arg = text_to_process.substr(start_index, closed_bracket_index - start_index).strip_edges()
	arg_array.append(last_arg)
	
	func_call_data.is_valid = true
	func_call_data.full_call = func_full_call
	func_call_data.args = arg_array
	func_call_data.arg_index = current_arg_index


func infer_func_call_data():
	if not func_call_data.is_valid:
		return false
	if func_call_data.inferred:
		return true
	
	var parser = Utils.ParserRef.get_parser(self)
	var full_call = func_call_data.full_call
	if full_call.find(".") > -1:
		var string_map = parser.get_string_map(full_call) #^ trim method so we can just infer object types
		var trimmed = UString.trim_member_access_back(full_call, string_map)
		var method_call = UString.get_member_access_back(full_call, string_map)
		var full_call_typed = parser.get_identifier_type(trimmed, caret_line)# + "()")
		full_call_typed = full_call_typed + "." + method_call
		func_call_data.full_call_typed = full_call_typed
	
	func_call_data.inferred = true
	return true



func _set_in_type_assignment():
	var text_to_process = code_context
	var idx = code_context_caret_pos
	
	if idx == 0:
		return
	var relevant_text = text_to_process.substr(0, idx).strip_edges()
	if relevant_text == "":
		return
	
	if not is_instance_valid(_type_assignment_regex):
		_type_assignment_regex = RegEx.new()
		var pattern = "(?:\\s*is not\\s+|\\s*is\\s+|\\s*as\\s+|\\s*extends\\s+|[\\w.]+\\s*:\\s*|\\->\\s*)([\\w.]*)$"
		_type_assignment_regex.compile(pattern)
	
	var _match = _type_assignment_regex.search(relevant_text)
	if _match:
		type_assignment = _match.get_string(1)
		caret_in_type_assignment = true
		return






















func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		print("FREE CC")

# API

func get_text_for_autocomplete():
	return Utils.ParserRef.get_parser(self).code_edit_parser.get_text_for_auto_complete(caret_line, caret_column)

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
















class AssignmentData:
	var is_valid:=false
	var inferred:=false
	
	var left:String
	var left_typed:String
	var operator:String
	var right:String


class FuncCallData:
	var is_valid:=false
	var inferred:=false
	
	var full_call:String
	var full_call_typed:String
	var args:=[]
	var arg_index:int = -1
