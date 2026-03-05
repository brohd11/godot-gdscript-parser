
const GDScriptParser = preload("res://addons/addon_lib/brohd/alib_runtime/utils/resource/gdscript/parser/gdscript_parser.gd")
const Utils = GDScriptParser.Utils
const Keys = Utils.Keys
const UString = GDScriptParser.UString

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
}


var _parser:WeakRef #
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

var bracket_type:=""

var current_class:String
var current_function:String

var caret_in_type_assignment:bool = false
var type_assignment:String

var _string_map_cache:={}
static var _assignment_regex:RegEx
static var _type_assignment_regex:RegEx
static var _context_regex: RegEx

func _init(parser:GDScriptParser, parse_context:=true) -> void:
	_parser = weakref(parser)
	code_edit = parser.code_edit
	
	caret_column = code_edit.get_caret_column()
	caret_line = code_edit.get_caret_line() # set these here so you can overide if wanted
	if parse_context:
		parse()


func parse():
	current_line_text = code_edit.get_line(caret_line)
	
	#completion_text = _get_text_for_auto_complete()
	
	code_context = _get_line_context(caret_line, caret_column, true)
	code_context_caret_pos = code_context.find(Keys.CARET_UNI_CHAR)
	code_context_string_map = _get_string_map(code_context)
	
	word_before_caret = _parse_identifier_at_position(current_line_text, caret_column - 1)
	char_before_caret = _get_char_before_caret()
	
	var parser = _get_parser()
	current_class = parser.get_class_at_line(caret_line)
	current_function = parser.get_function_at_line(caret_line)
	
	
	#gdscript_parser.on_completion_requested() #^ this needs to be before for get_current_func to work
	
	_set_caret_in_func_call() #^ check first to populate CARET_IN_FUNC
	_set_caret_in_bracket()
	_set_assignment_at_caret()
	_set_in_type_assignment()
	
	state = State.NONE
	if is_index_in_string(caret_column, caret_line):
		state = State.STRING
	elif is_index_in_comment(caret_column, caret_line):
		state = State.COMMENT
	elif caret_in_type_assignment:
		state = State.TYPE_ASSIGNMENT
	elif word_before_caret.find(".") > -1:
		state = State.MEMBER_ACCESS
	elif caret_in_function_call:
		state = State.FUNC_ARGS
	elif assignment_data.is_valid:
		state = State.ASSIGNMENT
	elif current_function == Keys.CLASS_BODY:
		if current_line_text.begins_with("@"):
			state = State.ANNOTATION
		else:
			state = State.SCRIPT_BODY
	
	print(State.keys()[state])
	




func _parse_identifier_at_position(text_to_process:String, start_pos:int):
	var string_map = _get_string_map(text_to_process)
	
	var current_pos = start_pos
	var name_start_pos = start_pos + 1
	var last_char = ""
	while current_pos >= 0:
		if string_map.string_mask[current_pos] == 1:
			current_pos -= 1
			continue
		
		var _char = text_to_process[current_pos]
		if _char == ")" or _char == "]" or _char == "}":
			current_pos = string_map.bracket_map.get(current_pos, current_pos)
		
		if not _char.is_valid_ascii_identifier() and _char != ".":
			var valid = false
			if _char == ")" and last_char == ".":
				valid = true
			if _char in UString.NUMBERS:
				valid = true
			
			if not valid:
				break
		
		last_char = _char
		name_start_pos = current_pos
		current_pos -= 1
	
	return text_to_process.substr(name_start_pos, start_pos - name_start_pos + 1)

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
	var parser = _get_parser()
	var left = assignment_data.left
	var left_typed = ""
	if left.begins_with("var "):
		#var trimmed = left.trim_prefix("var ") # not sure if this was causing issues?
		var data = Utils.get_var_name_and_type_hint_in_line(left)
		if data != null:
			left_typed = parser.get_identifier_type(data[1])
	else:
		left_typed = parser.get_identifier_type(left)
	
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
	func_call_data = FuncCallData.new()
	
	var text_to_process = code_context
	var caret_idx = code_context_caret_pos
	
	if UString.rfind_index_safe(text_to_process, "(", caret_idx) == -1:
		return
	
	var string_map = _get_string_map(text_to_process)
	var bracket_map = string_map.bracket_map
	var string_indexes = string_map.string_mask
	if string_map.has_errors or bracket_map.is_empty():
		return
	
	var open_bracket_index = string_map.get_tightest_bracket_set(caret_idx, "(")
	if open_bracket_index == -1:
		printerr("Could not get bracket for: ", text_to_process)
		return
	var closed_bracket_index = string_map.bracket_map[open_bracket_index]
	
	var func_full_call = _parse_identifier_at_position(text_to_process, open_bracket_index - 1)
	if func_full_call == "":
		return
	
	func_full_call = func_full_call.trim_prefix("self.") #^ simple check
	print(func_full_call)
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
	
	var parser = _get_parser()
	var full_call = func_call_data.full_call
	if full_call.find(".") > -1:
		var string_map = _get_string_map(full_call) #^ trim method so we can just infer object types
		var trimmed = UString.trim_member_access_back(full_call, string_map)
		var method_call = UString.get_member_access_back(full_call, string_map)
		var full_call_typed = parser.get_identifier_type(trimmed)# + "()")
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



func _get_line_context(target_line_index:int, _caret_column:=0, insert_caret:=false) -> String:
	if not is_instance_valid(_context_regex):
		_context_regex = RegEx.new()
		_context_regex.compile("[\"'(){}\\[\\]]")
	
	var t = ALibRuntime.Utils.UProfile.TimeFunction.new("Get Caret Context")
	var has_semi_col:=false
	var context_start_line = target_line_index + 1
	var context_end_line = target_line_index + 1
	while context_start_line > 0:
		context_start_line -= 1
		var line = code_edit.get_line(context_start_line) # musn't be stripped for _is_valid_code
		if line == "":
			continue
		var semi_i = line.rfind(";")
		while semi_i != -1:
			if not _is_valid_code(context_start_line, semi_i):
				semi_i = line.rfind(";", semi_i - 1)
			else:
				has_semi_col = true
				break
		line = line.strip_edges()
		if not Utils.line_has_any_declaration(line) or code_edit.is_in_string(context_start_line, 0) != -1:
			continue
		if not line.begins_with("func "):
			break
		if Utils.get_func_name_in_line(line) != "":
			break
	
	var bracket_depth = 0
	var in_string = code_edit.is_in_string(context_start_line, 0) != -1
	var is_prev_continued = false
	for i in range(context_start_line, code_edit.get_line_count()):
		var line = code_edit.get_line(i)
		if bracket_depth == 0 and not in_string and not is_prev_continued: # if not in string
			context_start_line = i
			context_end_line = i
		
		var results = _context_regex.search_all(line)
		for res in results:
			var pos = res.get_start()
			var c = res.get_string()
			var quote_char = c == "'" or c == '"'
			if quote_char:
				if in_string:
					pos += 1
				else:
					pos = max(pos - 1, 0)
			
			if _is_valid_code(i, pos):
				if quote_char:
					in_string = not in_string
				elif c == "(" or c == "[" or c == "{":
					bracket_depth += 1
				else:
					bracket_depth = max(0, bracket_depth - 1)
		
		is_prev_continued = false # 2. CHECK FOR LINE CONTINUATIONS '\'
		var stripped = line.strip_edges()
		if stripped.ends_with("\\"):
			var bs_idx = line.rfind("\\")
			if _is_valid_code(i, bs_idx):
				is_prev_continued = true
		
		if not is_prev_continued:
			if i >= target_line_index and bracket_depth == 0 and not in_string:
				#print("BREAKING %s -> %s " % [context_start_line, context_end_line], line)
				context_end_line = i
				break
	
	var caret_idx = 0
	var context_text = ""
	for i in range(context_start_line, context_end_line + 1):
		var line = GDScriptParser.Parse.get_line_no_comment(i, code_edit)
		if i == target_line_index:
			if insert_caret:
				line = line.insert(_caret_column, Keys.CARET_UNI_CHAR)
				caret_idx = line.rfind(Keys.CARET_UNI_CHAR) + context_text.length()
			
		if code_edit.is_in_string(i) == -1:
			context_text += line.strip_edges(i > context_start_line, true).trim_suffix("\\")
		else:
			context_text += "\n" + line
	
	if has_semi_col and insert_caret:
		var string_map = _get_string_map(context_text)
		var semi_prev = UString.string_safe_rfind(context_text, ";", caret_idx, string_map) + 1
		var semi_next = UString.string_safe_find(context_text, ";", caret_idx, string_map)
		context_text = context_text.substr(semi_prev, semi_next)
	
	
	t.stop()
	return context_text

func _is_valid_code(line:int, col:int):
	return code_edit.is_in_string(line, col) == -1 and code_edit.is_in_comment(line, col) == -1




func code_context_find(what:String, from:int=-1, string_safe:=true):
	if string_safe:
		return UString.string_safe_find(code_context, what, from, code_context_string_map)
	return code_context.find(what, from)

func code_context_rfind(what:String, from:int=-1, string_safe:=true):
	if string_safe:
		return UString.string_safe_rfind(code_context, what, from, code_context_string_map)
	return UString.rfind_index_safe(code_context, what, from)



func _get_text_for_auto_complete():
	# if the caret or has been moved, reconstruct the string
	if caret_column != code_edit.get_caret_column() or caret_line != code_edit.get_caret_line():
		var lines = code_edit.text.split("\n")
		var current_line = lines[caret_line] as String
		current_line = current_line.insert(caret_column, Keys.CARET_UNI_CHAR)
		lines[caret_line] = current_line
		return "\n".join(lines)
	else:
		return code_edit.get_text_for_code_completion()


func _get_string_map(text:String):
	if _string_map_cache.has(text):
		return _string_map_cache[text]
	var string_map = UString.get_string_map(text, UString.StringMap.Mode.FULL)
	_string_map_cache[text] = string_map
	return string_map

func _get_parser() -> GDScriptParser:
	return _parser.get_ref()












func _get_indent(line:int):
	return code_edit.get_indent_level(line) / code_edit.get_tab_size()











# API

func is_index_in_comment(column:int=-1, line:int=-1):
	if line == -1:
		line = code_edit.get_caret_line()
	if column == -1:
		column = code_edit.get_caret_column()
	return code_edit.is_in_comment(line, column) > -1

func is_index_in_string(column:int=-1, line:int=-1):
	if line == -1:
		line = code_edit.get_caret_line()
	if column == -1:
		column = code_edit.get_caret_column()
	return code_edit.is_in_string(line, column) > -1


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		print("FREE CC")


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
