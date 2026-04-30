
const GDScriptParser = preload("res://addons/addon_lib/brohd/alib_runtime/utils/gdscript/parser/gdscript_parser.gd")
const UString = GDScriptParser.UString
const GDScriptParse = UString.GDScriptParse

static var type_hint_regex:RegEx

static func tets_scrip():
	var parser  = ALibEditor.Singletons.EditorGDScriptParser.get_parser()
	format_script(parser, ScriptEditorRef.get_current_code_edit())

static func format_script(parser:GDScriptParser, script_editor:CodeEdit):
	var code_edit_parser = parser.get_code_edit_parser()
	var untyped_lines = {}
	var i = 0
	for _i in range(script_editor.get_line_count()):
		if i >= script_editor.get_line_count():
			break
		print(i)
		var text = script_editor.get_line(i)
		var stripped_text = text.strip_edges()
		if GDScriptParse.get_line_declaration(stripped_text).is_empty() and not stripped_text.begins_with("for "):
			i += 1
			continue
		var line_data = check_type_in_line(code_edit_parser, i)
		if line_data.is_empty():
			i += 1
			continue
		untyped_lines[i] = line_data
		var end_i = line_data.get("context").get(GDScriptParser.Keys.CONTEXT_END)
		i = end_i + 1
	
	#print(untyped_lines)
	insert_types(parser, script_editor, untyped_lines)

static func check_type_in_line(code_edit_parser:GDScriptParser.CodeEditParser, line_i:int):
	var context_data = code_edit_parser.get_line_context(line_i)
	var stripped_l:String = context_data.get(GDScriptParser.Keys.CONTEXT_TEXT).strip_edges()
	var dec:StringName = GDScriptParse.get_line_declaration(stripped_l)
	if dec == &"":
		if not stripped_l.begins_with("for "):
			return {}
		else:
			dec = &"for "
	if dec == GDScriptParse.Keywords.VAR or dec == GDScriptParse.Keywords.STATIC_VAR:
		var type_info:Array = GDScriptParse.get_var_or_const_info(stripped_l, false)
		if type_info == null:
			return {}
		#print(type_info)
		var nm:String = type_info[0]
		var assignment:String = stripped_l.trim_prefix(dec).strip_edges().trim_prefix(nm).strip_edges()
		if not assignment.begins_with(":"):
			return {
				"context": context_data,
				"dec": dec,
				"type_info": type_info
			}
	return {}


static func insert_types(parser:GDScriptParser, script_editor:CodeEdit, untyped_line_data:Dictionary):
	var action_started:bool = false
	
	var line_idxes:Array = untyped_line_data.keys()
	for i:int in line_idxes:
		var data:Dictionary = untyped_line_data[i]
		var context_data:Dictionary = data.get("context")
		var dec:String = data.get("dec")
		
		var start_idx:int = context_data.get(GDScriptParser.Keys.CONTEXT_START)
		var end_idx:int = context_data.get(GDScriptParser.Keys.CONTEXT_END)
		var multiline:bool = start_idx != end_idx
		
		if dec.ends_with(&"var "):
			var line_text = script_editor.get_line(i)
			
			var type_info:Array = data.get("type_info")
			var nm:String = type_info[0]
			var type_hint:String = type_info[1]
			var type_access_path = get_type_access_path(parser, type_hint, i)
			print(type_access_path)
			if type_access_path == "":
				type_access_path = get_type_access_path(parser, nm, i)
				if type_access_path == "":
					continue
			
			
			if not action_started:
				action_started = true
				script_editor.start_action(TextEdit.ACTION_TYPING)
			
			var nm_end_i = line_text.find(nm) + nm.length()
			line_text = line_text.insert(nm_end_i, ":" + type_access_path)
			script_editor.set_line(i, line_text)
	
	if action_started:
		script_editor.end_action()


static func get_type_access_path(parser:GDScriptParser, expression:String, line:int):
	var inferred_type:String = parser.resolve_expression_to_type(expression, line)
	print("INFERRED::", expression, "::",line, " -> ", inferred_type)
	if inferred_type == "":
		return ""
	
	if not GDScriptParse.is_absolute_path(inferred_type):
		return inferred_type
	else:
		var current_class:String = parser.get_class_at_line(line)
		var class_obj:GDScriptParser.ParserClass = parser.get_class_object(current_class) as GDScriptParser.ParserClass
		var preload_check:Variant = class_obj.has_preload(inferred_type)
		if preload_check != null:
			inferred_type = preload_check
		else:
			var access_object = parser.resolve_to_access_object(expression)
			var access_options = parser.get_access().find_path_to_type_simple(class_obj, access_object, inferred_type)
			print("ACCESS::",access_object.access_symbol)
			print(access_options.standard)
			print(access_options.script_alias)
			print(access_options.global)
			if access_options.standard != "":
				inferred_type = access_options.standard
			elif access_options.script_alias != "":
				inferred_type = access_options.script_alias
			elif access_options.global != "":
				inferred_type = access_options.global
			else:
				return ""
			return inferred_type
	
	
	return ""
	
