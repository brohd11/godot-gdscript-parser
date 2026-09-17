#! import_p Keys,

const PRINT_DEBUG = false

const URString = GDScriptParser.URString
const URClassDetail = GDScriptParser.URClassDetail

const ParserClass = GDScriptParser.ParserClass
const Utils = GDScriptParser.Utils
const Keys = Utils.Keys
const Keywords = Utils.Keywords
const LambdaScanner = preload("res://addons/addon_lib/gdscript_parser/utils/lambda_scanner.gd")

var _parser:WeakRef
var code_edit:CodeEdit

var use_native_backend:bool = false # set by the owning GDScriptParser (source of truth) in its _init
var native_manager:Variant
const NATIVE_MANAGER_PATH = "res://addons/addon_lib/gdscript_lsp/code_edit_manager.gd"
const NATIVE_SERVICE_PATH = "res://addons/addon_lib/gdscript_lsp/service.gd"

var indent_size:int

func _get_parser() -> GDScriptParser:
	return _parser.get_ref()

## A parser that is not the editor's active parser was obtained to READ another script, so its
## CodeEdit is a scratch line-walker rather than a buffer anyone is editing. active_parser is
## assigned as soon as the parser is constructed (gdscript_parser.get_parser_for_path), which is
## before parse() runs - a flag set in _finalize_parser_data would arrive one parse too late.
## A null active_parser means we cannot tell, so keep today's attached behaviour.
func _is_read_only_reader(parser:GDScriptParser) -> bool:
	return is_instance_valid(parser.active_parser) and parser.active_parser != parser


## Structural view of a script straight from the workspace index, with no buffer registered.
## Null when the extension is absent, too old, or the file is not indexed.
func _get_disk_document(script_path:String, text := "") -> Object:
	if not ResourceLoader.exists(NATIVE_SERVICE_PATH):
		return null
	var service = load(NATIVE_SERVICE_PATH).get_instance()
	if not is_instance_valid(service) or not service.has_method(&"get_disk_document"):
		return null
	return service.get_disk_document(script_path, text)


var string_map_cache:={}
static var assignment_regex:RegEx
static var type_assignment_regex:RegEx
static var context_regex: RegEx

var _map_regex:RegEx
var _annotation_regex:RegEx

var _first_parse_complete:=false
var cache_dirty:=true
var _full_native_revision: int = -1
var _line_sync_version:int = -1 # code_edit version the line ranges were last synced to
var _lambda_source:String = ""
var _plain_lambda_source:String = ""
var _plain_lambda_roots:Array = []
var _refreshing_lambdas:bool = false

func ensure_lambda_data() -> void:
	if _refreshing_lambdas or not is_instance_valid(code_edit) or code_edit.text == _lambda_source:
		return
	_refreshing_lambdas = true
	parse_text(true)
	_refreshing_lambdas = false

func get_plain_lambdas(class_obj:ParserClass, function = null) -> Dictionary:
	var source:String = code_edit.text
	if source != _plain_lambda_source:
		_plain_lambda_source = source
		_plain_lambda_roots = LambdaScanner.scan(source)
	var selected:Array = []
	for entry:Dictionary in _plain_lambda_roots:
		var line:int = entry.line_index
		if _get_parser().get_class_at_line(line) != class_obj.access_path:
			continue
		var function_name:String = class_obj.get_function_at_line(line)
		if function == null:
			if class_obj.functions.has(function_name):
				continue
		elif function_name != function.name:
			continue
		selected.append(entry)
	return _plain_lambda_collection(selected, function != null)

func _plain_lambda_collection(entries:Array, local_scope:bool) -> Dictionary:
	var reserved:Dictionary = {}
	for entry:Dictionary in entries:
		if not entry._owner.is_empty():
			var key:String = entry._owner
			if local_scope:
				key += "-%s-%s" % [entry.line_index, entry._owner_column]
			reserved[key] = true
	var result:Dictionary = {}
	for entry:Dictionary in entries:
		var owner:String = entry._owner
		if local_scope and not owner.is_empty():
			owner += "-%s-%s" % [entry.line_index, entry._owner_column]
		var key:String = owner
		if key.is_empty():
			var base:String = "inline_lambda_%s_%s" % [entry.line_index, entry.column_index]
			key = base
			var suffix:int = 1
			while reserved.has(key) or result.has(key):
				key = base + "_%s" % suffix
				suffix += 1
		result[key] = {Keys.LINE_INDEX: entry.line_index, Keys.COLUMN_INDEX: entry.column_index,
			Keys.END_LINE: entry.end_line, "end_column": entry.end_column, "owner_variable": owner,
			"lambdas": _plain_lambda_collection(entry._children, true)}
	return result

func _set_code_edit(new_code_edit:CodeEdit):
	if is_instance_valid(code_edit):
		if code_edit != new_code_edit:
			if code_edit.text_changed.is_connected(_on_text_changed):
				code_edit.text_changed.disconnect(_on_text_changed)
			cache_dirty = true
			_first_parse_complete = false
			_line_sync_version = -1 # versions are per code_edit, never compare across buffers
	
	code_edit = new_code_edit
	if not code_edit.text_changed.is_connected(_on_text_changed):
		code_edit.text_changed.connect(_on_text_changed)

## Sync to the parser's code_edit + indent WITHOUT running a full parse_text. Used when a
## CACHED_RESOLVED parser lazily attaches source so single-line reads (check_member_line /
## get_type_from_line) work on a resolve-cache miss. Structure stays sourced from the disk cache.
func sync_code_edit() -> void:
	var parser:GDScriptParser = _get_parser()
	if not is_instance_valid(parser) or not is_instance_valid(parser.code_edit):
		return
	_set_code_edit(parser.code_edit)
	indent_size = code_edit.get_tab_size()


## Only ever fires for a code_edit the user types into: TextEdit emits text_changed for incremental
## edits while in the tree, but NEVER for `code_edit.text = ...` (set_text emits text_set instead).
## A buffer code_edit is only ever filled by that assignment, so those parsers never go dirty here -
## every such site pairs its assignment with an empty _class_access or an explicit force instead.
func _on_text_changed():
	cache_dirty = true

var _pc:_ParserContext

class _ParserContext:
	var class_access_map = {&"":[]}
	var member_map := {}
	var constant_map := {}
	var inner_class_map := {}
	
	var access_path:StringName = &""
	var current_indentation_level:int = 0
	var extended_lines:= []
	var pending_annotations:= []
	
	var in_function:= false
	var current_func_dict:={}
	
	var class_name_data:= {}
	var main_script_path:StringName= &""

func ensure_first_parse():
	if _first_parse_complete:
		return
	parse_text()

func parse_text(force:=false):
	if use_native_backend:
		#return parse_text_native()
		return parse_text_native(force)
	
	_initialize_regex_map()
	_initialize_regex_annotation()
	
	var parser = _get_parser()
	if not is_instance_valid(parser.code_edit):
		#print("CALLED PARSE NO CODE EDIT")
		return
	
	
	var t = GDScriptParser.TF.new("S::" + parser.get_script_path())
	
	
	
	_set_code_edit(parser.code_edit)
	indent_size = code_edit.get_tab_size()
	
	var existing_class_access = parser._class_access # if existing class is empty, then it hasn't been parsed
	if existing_class_access.is_empty():
		cache_dirty = true
	
	if not cache_dirty and not force: # cache_dirty means text is changed. If it hasn't then everything should be valid
		#t.stop()
		#print("CODE EDIT PARSE EARLY EXIT::", parser.get_script_path().get_file())
		return
	
	var main_script = parser._script_resource
	if not is_instance_valid(main_script):
		cache_dirty = true
		return
	var main_script_path = main_script.resource_path
	
	_pc = _ParserContext.new()
	_pc.main_script_path = StringName(main_script_path)
	
	var class_access_map = _pc.class_access_map
	var extended_lines = _pc.extended_lines
	
	var i = 0
	# full line count so that range() includes last line
	var code_edit_line_count = code_edit.get_line_count()
	for _i in range(code_edit_line_count):
		if i >= code_edit_line_count: # some how get line can return a blank line when calling out of range?
			break
		var stripped:String = get_line(i, true, true)
		if stripped == "" or not is_valid_code(i, 0): # avlid code check for multiline strings with vars, for a template or something
			class_access_map[_pc.access_path].append(i)
			if _pc.in_function:
				_pc.current_func_dict[Keys.FUNC_LINES].append(i)
			#print("CURRENT TOP::", i, "::EXTENDED LINES::", extended_lines, _pc.current_func_dict.get(Keys.FUNC_LINES))
			i += 1
			continue
		
		var has_semi_col = stripped.find(";") > -1
		if has_semi_col:
			var data = get_semi_colon_strings(i)
			for column in data.keys():
				var text = data[column]
				_parse_line(text.strip_edges(), i, column)
		else:
			_parse_line(stripped, i)
		
		class_access_map[_pc.access_path].append(i)
		if _pc.in_function:
			_pc.current_func_dict[Keys.FUNC_LINES].append(i)
		
		if not extended_lines.is_empty():
			for index in extended_lines:
				class_access_map[_pc.access_path].append(index)
				if _pc.in_function:
					_pc.current_func_dict[Keys.FUNC_LINES].append(index)
				i += 1
			extended_lines.clear()
		
		i += 1
	
	var temp_class_access = {}
	var _class_paths = class_access_map.keys()
	for path:String in _class_paths:
		var _class_obj:ParserClass
		if existing_class_access.has(path):
			_class_obj = existing_class_access[path]
			_class_obj.queue_refresh()
		if not is_instance_valid(_class_obj):
			_class_obj = ParserClass.new()
			Utils.ParserRef.set_refs(_class_obj, parser)
			_class_obj.access_path = path
			_class_obj.indent_level = get_indent_access_path(path)
		
		var members = _pc.member_map.get(path, {})
		_class_obj.set_extends(members.get("extends", "RefCounted"))
		members.erase("extends")
		
		var valid_constants:Dictionary = _pc.constant_map.get("", {}).duplicate()
		var valid_classes:Dictionary = _pc.inner_class_map.get("", {}).duplicate()
		if path != "":
			var working_path = ""
			var parts = URString.split_member_access(path)
			for x in range(parts.size()):
				var part = parts[x]
				working_path = URString.dot_join(working_path, part)
				valid_constants.merge(_pc.constant_map.get(working_path, {}), true)
				#valid_classes.merge(_pc.inner_class_map.get(working_path, {}), true)
				var classes = _pc.inner_class_map.get(working_path, {})
				for name in classes.keys():
					# for proper scoping, act like merge with no overwrite
					var class_data = classes[name]
					if not valid_classes.has(name):
						valid_classes[name] = class_data
						continue
					
					# but if the class is self, then it ovewrites, inner classes at the same level will
					# defer to the lower level if they are named the same ie. Nested.Nested and Nested.Another
					# Nested.Another will access Nested when typing Nested, not the nested class. Whereas if it has a unique name
					# it can be accessed directly. Nested.Nested will access itself when typing Nested,
					if class_data.get(Keys.ACCESS_PATH) == path: # so it overides here.
						valid_classes[name] = class_data
		
		_class_obj.main_script_path = _pc.main_script_path
		if path == "":
			_class_obj.set_script_resource(parser._script_resource)
			_class_obj.class_name_data = _pc.class_name_data
		else:
			#_class_obj.set_script_resource(URClassDetail.get_member_info_by_path(main_script, _pc.access_path))
			var inner_script = URClassDetail.get_member_info_by_path(main_script, path)
			#prints("INNERSCRIPT::", inner_script, "::PATH::", path)
			_class_obj.set_script_resource(inner_script)
		
		var class_lines = class_access_map[path]
		_class_obj.set_lines(class_lines)
		
		_class_obj.use_ts = false
		_class_obj.set_members(members, {})
		_class_obj.set_constants(valid_constants)
		_class_obj.set_inner_classes(valid_classes)
		
		temp_class_access[path] = _class_obj
	
	# remove classes that may have been removed
	for access_path in parser._class_access.keys():
		if not temp_class_access.has(access_path):
			parser._class_access.erase(access_path)
	
	# reassign the classes and new classes
	parser.set_class_objs(temp_class_access)
	for class_obj:ParserClass in temp_class_access.values():
		class_obj.set_lambdas(get_plain_lambdas(class_obj))
	_lambda_source = code_edit.text
	
	
	if PRINT_DEBUG:
		t.stop()
	#print("CLASSES ",temp_class_access.keys())
	cache_dirty = false
	_first_parse_complete = true
	_pc = null
	return temp_class_access


func _parse_line(stripped:String, line:int, column:int=0):
	var has_extension = stripped.ends_with("\\")
	if has_extension or stripped.begins_with("@"):
		if has_extension or _line_has_open_bracket(stripped): # complex case, get full context # old version just checked stripped.count('(') != stripped.count(')')
			var context_data = get_line_context(line, 0, false, {Keys.CONTEXT_START: line})
			var end_index = context_data.get(Keys.CONTEXT_END)
			for e_i in range(line + 1, end_index):
				_pc.extended_lines.append(e_i)
			stripped = context_data.get(Keys.CONTEXT_TEXT, "").strip_edges()
		
		while stripped.begins_with("@"):
			var _match = _annotation_regex.search(stripped)
			if _match:
				var matched_text = _match.get_string()
				_pc.pending_annotations.append(matched_text.strip_edges())
				stripped = stripped.substr(matched_text.length()) # Slice the annotation off the front of the line
			else:
				break # Failsafe
	
	var indentation_level = get_indent_code_edit(line)
	if indentation_level < _pc.current_indentation_level:
		if stripped != "":
			var iterations = (_pc.current_indentation_level - indentation_level) / indent_size
			for z in range(iterations):
				var dot = _pc.access_path.rfind(".")
				if dot == -1:
					_pc.access_path = StringName("")
					break
				else:
					_pc.access_path = StringName(_pc.access_path.substr(0, _pc.access_path.rfind(".")))
			
			#prints("DROP LEVEL:", indentation_level, current_indentation_level,old_access_path, " -> ", access_path)
			_pc.current_indentation_level = indentation_level
	
	if not (stripped.begins_with("class") or _pc.current_indentation_level == indentation_level):
		return

	if is_nameless_enum_declaration(stripped): # _map_regex needs a name
		_pc.pending_annotations.clear()
		_parse_nameless_enum(line, column)
		return

	var result = _map_regex.search(stripped)
	if result:
		var keyword:StringName = result.get_string(2)
		if result.get_string(1) != "":
			if result.get_string(1) != "static":
				GDScriptParser.print_deb_err(["REGEX MISTAKE SHOULD BE STATIC ", result.get_string(1)])
			keyword = "static " + keyword
		var member_name = StringName(result.get_string(3))
		
		var data = {
			Keys.MEMBER_TYPE:keyword,
			Keys.MEMBER_NAME:member_name,
			Keys.LINE_INDEX:line,
			Keys.SCRIPT_PATH: _pc.main_script_path,
			Keys.ACCESS_PATH: _pc.access_path,
		}
		if not _pc.pending_annotations.is_empty():
			data[Keys.ANNOTATIONS] = _pc.pending_annotations.duplicate()
			_pc.pending_annotations.clear()
		
		_pc.in_function = false
		if keyword == "class":
			var new_access_path = URString.dot_join(_pc.access_path, member_name)
			#data[Keys.MEMBER_TYPE] = Keys.MEMBER_TYPE_CLASS
			data[Keys.TYPE] = URString.dot_join(_pc.main_script_path, new_access_path)
			
			_pc.inner_class_map.get_or_add(_pc.access_path, {})[member_name] = data
			
			var line_context = stripped
			if stripped.ends_with("\\"):
				line_context = get_line_context(line, 0, false, {Keys.CONTEXT_START:line}).get(Keys.CONTEXT_TEXT, stripped).strip_edges()
			if line_context.contains(" extends "):
				var extended = _get_extends_out_line(line_context)
				_pc.member_map.get_or_add(new_access_path, {})["extends"] = extended
			
			
			_pc.current_indentation_level += indent_size
			_pc.access_path = new_access_path
			_pc.class_access_map[_pc.access_path] = []
		else:#if _pc.current_indentation_level == indentation_level:
			data[Keys.COLUMN_INDEX] = column
			if keyword.ends_with(&"func"):
				_pc.current_func_dict = data
				_pc.in_function = true
				data[Keys.FUNC_LINES] = PackedInt32Array()
				_pc.member_map.get_or_add(_pc.access_path, {})[member_name] = data
			elif keyword == &"class_name":
				if stripped.contains(" extends "):
					var extended = _get_extends_out_line(stripped)
					_pc.member_map.get_or_add(_pc.access_path, {})[&"extends"] = extended
				_pc.class_name_data = data
			elif keyword.begins_with("c") or keyword == &"enum":
				_pc.constant_map.get_or_add(_pc.access_path, {})[member_name] = data
			else:
				if keyword.ends_with(&"var") and stripped.contains("func"):
					var var_info:Variant = Utils.get_var_or_const_info(stripped)
					if var_info != null and Utils.is_lambda_assignment(var_info[2]):
						data[Keys.LAMBDA] = {Keys.LINE_INDEX: line, Keys.END_LINE: get_indent_block_end(line)}
				_pc.member_map.get_or_add(_pc.access_path, {})[member_name] = data
	elif stripped.begins_with("extends "):
		var extended = _get_extends_out_line(stripped)
		_pc.member_map.get_or_add(_pc.access_path, {})["extends"] = extended


## Nameless enum entries are int consts in the class scope, one per entry, shaped like tree-sitter's
## so both parse paths fold into `constants` the same way.
func _parse_nameless_enum(line:int, column:int) -> void:
	var end_index:int = get_line_context(line, 0, false, {Keys.CONTEXT_START: line}).get(Keys.CONTEXT_END, line)
	end_index = clampi(end_index, line, code_edit.get_line_count() - 1)
	var lines:PackedStringArray = []
	for i:int in range(line, end_index + 1):
		lines.append(get_line(i, true))
	if column > 0: # a `;`-split part: blank what precedes it, keeping columns
		lines[0] = " ".repeat(column) + lines[0].substr(column)
	for i:int in range(line + 1, end_index + 1):
		_pc.extended_lines.append(i)

	var constants:Dictionary = _pc.constant_map.get_or_add(_pc.access_path, {})
	for entry:Array in Utils.get_nameless_enum_entries(lines, line):
		var entry_name:StringName = StringName(entry[0])
		constants[entry_name] = {
			Keys.MEMBER_TYPE: Keys.MEMBER_TYPE_CONST,
			Keys.MEMBER_NAME: entry_name,
			Keys.LINE_INDEX: entry[1],
			Keys.COLUMN_INDEX: entry[2],
			Keys.SCRIPT_PATH: _pc.main_script_path,
			Keys.ACCESS_PATH: _pc.access_path,
			Keys.TYPE: &"int",
			Keys.HAS_STATIC_TYPE: true,
			Keys.ASSIGNMENT: entry[3],
		}

## Last line of the indented block opened on `line`, e.g. a multi-line lambda body. Starts from the
## line's bracket context end so a signature spanning lines is covered.
func get_indent_block_end(line:int) -> int:
	var count:int = code_edit.get_line_count()
	var end:int = get_line_context(line, 0, false, {Keys.CONTEXT_START: line}).get(Keys.CONTEXT_END, line)
	end = clampi(end, line, count - 1)
	var base_indent:int = get_indent_code_edit(line)
	for i:int in range(end + 1, count):
		if get_line(i, true, true) == "":
			continue
		if get_indent_code_edit(i) <= base_indent:
			break
		end = i
	return end


func _get_extends_out_line(line_text:String):
	var extends_string:String
	if line_text.begins_with("extends"):
		extends_string = line_text
	else:
		extends_string = line_text.substr(line_text.find(" extends ")).strip_edges()
	
	var class_info = Utils.get_class_info("class dummy " + extends_string + ":")
	var extended = class_info[1]
	if extended == "":
		extended = "RefCounted"
	elif Utils.token_is_string(extended):
		extended = Utils.get_full_path_from_string(extended)
		extended = Utils.ensure_absolute_path(extended, _pc.main_script_path)
	return extended

func _line_has_open_bracket(stripped:String):
	if stripped.count("(") != stripped.count(")"):
		return true
	if stripped.count("{") != stripped.count("}"):
		return true
	if stripped.count("[") != stripped.count("]"):
		return true
	return false


func parse_text_native(force:=false):
	
	#_initialize_regex_map() # these aren't used with ts I believe
	#_initialize_regex_annotation()
	
	var parser = _get_parser()
	if not is_instance_valid(parser.code_edit):
		#print("CALLED PARSE NO CODE EDIT")
		return
	
	var t = GDScriptParser.TF.new("TS::" + parser.get_script_path())
	
	_set_code_edit(parser.code_edit)
	indent_size = code_edit.get_tab_size()
	
	var existing_class_access = parser._class_access # if existing class is empty, then it hasn't been parsed
	if existing_class_access.is_empty():
		cache_dirty = true
	
	var main_script = parser._script_resource
	var main_script_path = parser.get_script_path()

	var native_revision:int
	var full_parse_data:Dictionary

	if _is_read_only_reader(parser):
		# This parser exists only to READ another script. Its CodeEdit is there so GDScript can walk
		# lines faster than a PackedStringArray - nobody is editing it. Note the discriminator is the
		# parser's purpose, not the CodeEdit's origin: a parser-created CodeEdit can still be
		# live-edited (live_edit_lines_test.gd does exactly that), and those must keep their buffer.
		# Attaching would register it with the LSP
		# (attach -> acquire -> sync_buffer -> update_document), publishing a read as an open
		# document and invalidating every script that depends on it, mid-resolve. Read the
		# workspace's own indexed copy instead: no buffer, no version push, nothing invalidated.
		# Matches the built-in LSP, where only editor buffers are open and everything else is disk.
		var disk_doc:Object = _get_disk_document(main_script_path, code_edit.text)
		if not is_instance_valid(disk_doc):
			# No extension, or a file the workspace has not indexed - keep the text parser.
			use_native_backend = false
			var text_result = parse_text(force)
			use_native_backend = true
			return text_result
		native_revision = disk_doc.get_revision()
		if not cache_dirty and not force and _full_native_revision == native_revision:
			return
		full_parse_data = disk_doc.parse_script(main_script_path)
		if PRINT_DEBUG:
			GDScriptParser.TF.new("PARSE TO DATA (disk)").stop()
	else:

		if not is_instance_valid(native_manager):
			var code_edit_tree_parser = load(NATIVE_MANAGER_PATH)
			native_manager = code_edit_tree_parser.new()
	
		if native_manager._edit != code_edit:
			var t4 = GDScriptParser.TF.new("PARSE TEXT NEW CODE")
			native_manager.detach()
			# the path is only a label - parse() stamps it into every member dict as Keys.SCRIPT_PATH.
			# The text must keep coming from the code_edit (prefer_code_edit), or an unsaved buffer is
			# never reflected and cache_dirty stops meaning anything.
			native_manager.attach(code_edit, main_script_path)
			if PRINT_DEBUG:
				t4.stop()
		elif not native_manager.cache_valid(): # only re-parse if needed
			native_manager.parse_text()
		elif force:
			native_manager.parse_text(true)

		# same code_edit, different script (set_script_path / upgrade_to_live) - re-label before parsing
		# so members are not stamped with the previous script's path.
		native_manager.set_script_path(main_script_path)

		var t2 = GDScriptParser.TF.new("PARSE TO DATA")
		if not is_instance_valid(native_manager.parser):
			# Runtime/headless callers without an editor owner retain the text parser.
			use_native_backend = false
			var result = parse_text(force)
			use_native_backend = true
			return result
		native_revision = native_manager.get_parse_revision()
		if not cache_dirty and not force and _full_native_revision == native_revision:
			return
		full_parse_data = native_manager.parse()
		if PRINT_DEBUG:
			t2.stop()
	
	var temp_class_access = {}
	for path:String in full_parse_data.keys():
		var _class_obj:ParserClass
		if existing_class_access.has(path):
			_class_obj = existing_class_access[path]
			_class_obj.queue_refresh()
		if not is_instance_valid(_class_obj):
			_class_obj = ParserClass.new()
			Utils.ParserRef.set_refs(_class_obj, parser)
			_class_obj.access_path = path
			_class_obj.indent_level = get_indent_access_path(path)
		
		
		
		var cls_data = full_parse_data[path]
		cls_data[Keys.TYPE] = Utils.get_class_access_path_from_member_data(cls_data)
		
		var members = cls_data.get("members")
		var ex = cls_data.get("extends", "")
		if ex == "":
			ex = "RefCounted"
		_class_obj.set_extends(ex)
		
		var valid_constants:Dictionary = cls_data.get("constants")
		var valid_classes:Dictionary = cls_data.get("inner_classes")
		
		_class_obj.main_script_path = main_script_path
		if path == "":
			_class_obj.set_script_resource(parser._script_resource)
			_class_obj.class_name_data = cls_data
		else:
			#_class_obj.set_script_resource(URClassDetail.get_member_info_by_path(main_script, _pc.access_path))
			var inner_script = URClassDetail.get_member_info_by_path(main_script, path)
			#prints("INNERSCRIPT::", inner_script, "::PATH::", path)
			_class_obj.set_script_resource(inner_script)
		
		
		var class_start = cls_data.get("line_index")
		if path.is_empty():
			class_start = 0 # forcing root to 0, if no class or extends declared, acts weird
		var class_end = cls_data.get("end_line")
		var class_lines = range(class_start, class_end + 1)
		_class_obj.set_lines(class_lines)
		_class_obj.use_ts = true
		
		_class_obj.set_members(members, cls_data.get("lambdas"))
		_class_obj.set_constants(valid_constants)
		_class_obj.set_inner_classes(valid_classes)
		#print(valid_constants)
		temp_class_access[path] = _class_obj
	
	# remove classes that may have been removed
	for access_path in parser._class_access.keys():
		if not temp_class_access.has(access_path):
			parser._class_access.erase(access_path)
	
	# reassign the classes and new classes
	parser.set_class_objs(temp_class_access)
	
	if PRINT_DEBUG:
		t.stop()
	#print("CLASSES ",temp_class_access.keys())
	_full_native_revision = native_revision
	cache_dirty = false
	_first_parse_complete = true
	_line_sync_version = native_revision # ranges are fresh, next sync_line_ranges() no-ops
	_lambda_source = code_edit.text
	#_pc = null
	return temp_class_access


## Refresh only class/function LINE RANGES from the (already incremental) tree-sitter tree. Cheap
## enough to run per keystroke; the debounced full parse still owns members, types and resolve caches,
## so a sync deliberately leaves line_indexes newer than members - a pairing no full parse produces,
## and the next one reconciles it. Gated on tree-sitter plus an attached, already-parsed buffer, NOT
## on being the editor's parser (it drives the headless suite fine); the per-keystroke policy belongs
## to the caller, EditorGDScriptParser._on_text_changed. Returns true when a range actually moved.
func sync_line_ranges() -> bool:
	if not use_native_backend or not _first_parse_complete:
		return false
	var parser:GDScriptParser = _get_parser()
	if not is_instance_valid(parser) or not is_instance_valid(parser.code_edit):
		return false
	# a code_edit we never parsed, or a manager pointed at another buffer, is the full parse's job
	if not is_instance_valid(code_edit) or code_edit != parser.code_edit:
		return false
	if not is_instance_valid(native_manager) or native_manager._edit != code_edit:
		return false

	var version:int = native_manager.get_parse_revision()
	if version == _line_sync_version:
		return false

	# through the manager, not its parser: it reparses first (free no-op at the matching version) and
	# caches per tree revision, so the highlighter's call in the same frame costs nothing. Read-only.
	var line_data:Dictionary = native_manager.sparse_parse().get("lines", {})

	var changed:bool = false
	for path:String in line_data.keys():
		# a class typed mid-edit has no ParserClass yet (it needs member data) - the full parse adds it
		var class_obj:ParserClass = parser._class_access.get(path)
		if not is_instance_valid(class_obj):
			continue

		var cls_data:Dictionary = line_data[path]
		var class_start:int = cls_data.get(Keys.LINE_INDEX, -1)
		if path.is_empty():
			class_start = 0 # same root normalisation as parse_text_native, or the two paths disagree
		var class_end:int = cls_data.get(Keys.END_LINE, class_start)
		if class_start >= 0 and class_end >= class_start:
			var lines:PackedInt32Array = range(class_start, class_end + 1)
			if lines != class_obj.line_indexes:
				class_obj.set_lines(lines)
				changed = true

		var func_line_data:Dictionary = cls_data.get("functions", {})
		for func_name:String in func_line_data.keys():
			var func_obj = class_obj.functions.get(func_name)
			if not is_instance_valid(func_obj):
				continue
			var fn_data:Dictionary = func_line_data[func_name]
			var start:int = fn_data.get(Keys.LINE_INDEX, -1)
			var end:int = fn_data.get(Keys.END_LINE, start)
			if start < 0 or end < start:
				continue
			# compare against func_lines, not end_line - _create_function_ts never assigns end_line
			var cur_end:int = -1
			if not func_obj.func_lines.is_empty():
				cur_end = func_obj.func_lines[func_obj.func_lines.size() - 1]
			if func_obj.declaration_line == start and cur_end == end:
				continue
			if func_obj.declaration_line != start:
				func_obj._cache_dirty = true # signature moved, re-read it lazily
			func_obj.declaration_line = start
			func_obj.end_line = end
			func_obj.func_lines = range(start, end + 1)
			func_obj.invalidate_line_caches()
			changed = true

	_line_sync_version = version
	return changed



#region CaretContext

func get_line_context_start_data(target_line_index:int, params:Dictionary={}) -> Dictionary:
	if not is_instance_valid(code_edit):
		return {}
	
	var all_blocks_array:Array = Keywords.CONTROL_FLOW_KEYWORDS
	var map_blocks_array:Array = params.get(Keys.CONTEXT_BLOCKS, [])
	var has_blocks:bool = not map_blocks_array.is_empty()
	var func_name:String
	var map_local_vars:bool = params.get(Keys.CONTEXT_LOCAL_VARS, true)
	
	var respect_scope = has_blocks or map_local_vars
	
	var blocks:= []
	var local_vars:= {}
	
	var first_line = code_edit.get_line(target_line_index).strip_edges()
	var first_line_empty_check = first_line == "" or first_line.begins_with("#") or get_control_flow(first_line) != ""
	
	var original_indent = get_indent_code_edit(target_line_index)
	var current_indent = original_indent
	
	var stop_line:int = params.get(Keys.CONTEXT_STOP_LINE, -1)
	var has_semi_col:=false
	var context_start_line = target_line_index + 1
	while context_start_line > 0:
		context_start_line -= 1
		if context_start_line <= stop_line: # a lambda's own scope ends at its declaration line
			break
		if _line_has_semi_colon(context_start_line):
			has_semi_col = true
			#break # originally this just breaks.
			# It stops local vars from being collected though...
			# perhaps the better way would be to switch how locals are being collected
			if not map_local_vars: #ALERT TEST not sure about this..
				break
		var stripped = code_edit.get_line(context_start_line).strip_edges()
		if stripped == "" or stripped.begins_with("#"):
			continue
		if code_edit.is_in_string(context_start_line, 0) != -1:
			continue
		
		if first_line_empty_check and context_start_line < target_line_index: # ensure empty string first line doesn't mess up indent
			first_line_empty_check = false
			current_indent = get_indent_code_edit(context_start_line)
			for control_flow in Keywords.CONTROL_FLOW_KEYWORDS:
				if stripped.begins_with(control_flow):
					current_indent += get_indent_size()
					break
		
		if respect_scope:
			var line_indent = get_indent_code_edit(context_start_line)
			if line_indent <= current_indent:
				if line_indent < current_indent:
					for control_flow in Keywords.CONTROL_FLOW_KEYWORDS:
						if stripped.begins_with(control_flow):
							current_indent = line_indent
							if control_flow in map_blocks_array:
								if control_flow == Keywords.FOR:
									var var_data = Utils.add_var_to_dict(stripped, context_start_line, 0, local_vars, Keys.MEMBER_TYPE_FOR)
									if var_data:
										blocks.append({"type":"for",
										"indent": line_indent,
										"var":{"name": var_data[0], "type": var_data[1]}})
								else:
									blocks.append({"type":control_flow.strip_edges(),
									"indent": line_indent,
									"expr": _get_control_flow_expression(context_start_line, control_flow)})
				
				if map_local_vars:
					if context_start_line < target_line_index:
						var line_text = code_edit.get_line(context_start_line)
						if not stripped.contains(";"):
							var col = line_text.find(stripped)
							var var_data = Utils.add_var_to_dict(stripped, context_start_line, col, local_vars)
							if var_data != null:
								#print("MAP LOCAL::", var_data, "::IND::CUR::", current_indent, "::LINE::", line_indent)
								continue
						else:
							var assigns = [stripped]
							assigns = URString.string_safe_split(stripped, ";")
							if stripped.begins_with("var my"):
								print("has sem---",assigns)
							var col = 0
							for a in assigns:
								col = line_text.find(a, col)
								var var_data = Utils.add_var_to_dict(a.strip_edges(), context_start_line, col, local_vars)
								if var_data != null:
									#print("MAP LOCAL::", var_data, "::IND::CUR::", current_indent, "::LINE::", line_indent)
									continue
				else:
					if not Utils.line_has_any_declaration(stripped):
						continue
					if not stripped.begins_with("func "):
						break
				# applies to both
				if Utils.get_func_name_in_line(stripped) != "":
					func_name = Utils.get_func_name_in_line(stripped)
					break
	
	return {
		Keys.CONTEXT_SEMI_COLON: has_semi_col,
		Keys.CONTEXT_START: context_start_line,
		Keys.CONTEXT_BLOCKS: blocks,
		Keys.CONTEXT_FUNC: func_name,
		Keys.CONTEXT_LOCAL_VARS:local_vars,
	}


func get_line_context_start_simple(target_line_index:int) -> Dictionary:
	var has_semi_col:=false
	var context_start_line = target_line_index + 1
	while context_start_line > 0:
		context_start_line -= 1
		if _line_has_semi_colon(context_start_line):
			has_semi_col = true
			break
		var stripped = code_edit.get_line(context_start_line).strip_edges()
		if stripped == "" or stripped.begins_with("#"):
			continue
		if not Utils.line_has_any_declaration(stripped) or code_edit.is_in_string(context_start_line, 0) != -1:
			continue
		if not stripped.begins_with("func "):
			break
		if Utils.get_func_name_in_line(stripped) != "":
			break
	
	return {
		Keys.CONTEXT_SEMI_COLON: has_semi_col,
		Keys.CONTEXT_START: context_start_line,
	}





func get_line_context(target_line_index:int, _caret_column:=0, insert_caret:=false, start_data:={}) -> Dictionary:
	if not is_instance_valid(code_edit):
		return {}
	if not is_instance_valid(context_regex):
		context_regex = RegEx.new()
		context_regex.compile("[\"'(){}\\[\\]]")
	
	
	#var t = GDScriptParser.TF.new("Get Caret Context")
	if start_data.is_empty():
		start_data = get_line_context_start_simple(target_line_index)
	
	var has_semi_col:bool = start_data.get(Keys.CONTEXT_SEMI_COLON, false)
	var context_start_line:int = start_data.get(Keys.CONTEXT_START, target_line_index)
	var context_end_line:int = target_line_index + 1
	#prints("HAS SEMI COL", has_semi_col, _caret_column)
	
	var bracket_depth = 0
	var in_string = code_edit.is_in_string(context_start_line, 0) != -1
	var is_prev_continued = false
	for i in range(context_start_line, code_edit.get_line_count() - 1):
		var line = code_edit.get_line(i)
		if bracket_depth == 0 and not in_string and not is_prev_continued: # if not in string
			context_start_line = i
			context_end_line = i
		
		var results = context_regex.search_all(line)
		for res in results:
			var pos = res.get_start()
			var c = res.get_string()
			var quote_char = c == "'" or c == '"'
			if quote_char:
				if in_string:
					pos += 1
				else:
					pos = max(pos - 1, 0)
			
			if is_valid_code(i, pos):
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
			if is_valid_code(i, bs_idx):
				is_prev_continued = true
		
		if not is_prev_continued:
			if i >= target_line_index and bracket_depth == 0 and not in_string:
				#print("BREAKING %s -> %s " % [context_start_line, context_end_line], line)
				context_end_line = i
				break
	
	var caret_idx = 0
	var context_text = ""
	for i in range(context_start_line, context_end_line + 1):
		var line = get_line_no_comment(i)
		if i == target_line_index:
			if insert_caret:
				line = line.insert(_caret_column, Keys.CARET_UNI_CHAR)
				caret_idx = line.rfind(Keys.CARET_UNI_CHAR) + context_text.length()
			else:
				caret_idx = _caret_column + context_text.length()
			
		if code_edit.is_in_string(i) == -1:
			var not_first = i > context_start_line
			var line_text = line.strip_edges(not_first, true).trim_suffix("\\")
			if not_first:
				line_text = " " + line_text
			context_text += line_text
		else:
			#context_text += "\n" + line
			context_text += " " + line #^r note: switching this new line, allows for multi line to be sqeezed into a single line for parsing
	
	
	if has_semi_col:# and _caret_column > 0:
		var string_map = get_string_map(context_text)
		var semi_prev = URString.string_safe_rfind(context_text, ";", caret_idx, string_map) + 1
		var semi_next = URString.string_safe_find(context_text, ";", caret_idx, string_map)
		var end_idx = -1 if semi_next == -1 else semi_next - semi_prev
		context_text = context_text.substr(semi_prev, end_idx)
	
	#t.stop()
	var return_data = {
		Keys.CONTEXT_TEXT: context_text,
		Keys.CONTEXT_START: context_start_line,
		Keys.CONTEXT_END: context_end_line,
	}
	
	return return_data


func _line_has_semi_colon(line:int):
	var line_text = code_edit.get_line(line) # musn't be stripped on left for is_valid_code with semi
	var semi_i = line_text.rfind(";")
	while semi_i != -1:
		if not is_valid_code(line, semi_i):
			semi_i = line_text.rfind(";", semi_i - 1)
		else:
			return true
	return false

func get_line_context_text(line:int, column:int=0, strip_edges:=true):
	var context = get_line_context(line, column).get(Keys.CONTEXT_TEXT, "")
	if strip_edges:
		context = context.strip_edges()
	return context

func parse_identifier_at_position(text_to_process:String, start_pos:int):
	var string_map = get_string_map(text_to_process)
	
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
			if _char in URString.NUMBERS:
				valid = true
			
			if not valid:
				break
		
		last_char = _char
		name_start_pos = current_pos
		current_pos -= 1
	
	return text_to_process.substr(name_start_pos, start_pos - name_start_pos + 1)

func parse_expression_at_position(text_to_process: String, start_pos: int, string_map=null) -> String:
	if string_map == null:
		string_map = get_string_map(text_to_process)
	var current_pos = start_pos
	var name_start_pos = start_pos + 1
	
	# These flags act as a tiny "State Machine" to handle whitespace safely
	var expecting_operator = false 
	var last_was_ident = false
	
	while current_pos >= 0:
		# Safely walk backward through strings
		if string_map.string_mask[current_pos] == 1:
			name_start_pos = current_pos
			current_pos -= 1
			last_was_ident = true # A string acts like an identifier block
			continue
		
		var _char = text_to_process[current_pos]
		
		# Handle Whitespace boundaries safely
		if _char == " " or _char == "\t" or _char == "\n":
			if last_was_ident:
				# If we read a word, and hit a space, the ONLY valid thing 
				# to the left of this space is an operator (like a dot or bracket).
				expecting_operator = true
			current_pos -= 1
			continue
			
		# Handle Brackets (Method calls AND Index access)
		if _char == ")" or _char == "]" or _char == "}":
			current_pos = string_map.bracket_map.get(current_pos, current_pos)
			last_was_ident = true
			expecting_operator = false
			name_start_pos = current_pos
			current_pos -= 1
			continue
			
		# Handle Member Access (.)
		if _char == ".":
			expecting_operator = false
			last_was_ident = false
			name_start_pos = current_pos
			current_pos -= 1
			continue
			
		# Handle Node Path Terminals ($ and %)
		if _char == "$" or _char == "%":
			# These characters exclusively mark the BEGINNING of an expression.
			name_start_pos = current_pos
			break # Stop scanning entirely
			
		# Check for Valid Expression Characters
		# We include '/' specifically so NodePaths parse seamlessly
		var is_ident = (_char >= 'a' and _char <= 'z') or \
					   (_char >= 'A' and _char <= 'Z') or \
					   (_char >= '0' and _char <= '9') or \
					   _char == '_' or _char == '/'
					   
		if is_ident:
			if expecting_operator:
				# Example: "var my_func"
				# We read "my_func", hit a space, and now hit "r" (from var).
				# This is a word boundary! We must stop scanning here.
				break
				
			last_was_ident = true
			name_start_pos = current_pos
			current_pos -= 1
			continue
			
		# If it's a comma, plus, minus, equals, etc... we reached the edge!
		break
		
	var final_expr = text_to_process.substr(name_start_pos, start_pos - name_start_pos + 1)
	return final_expr.strip_edges()



func get_indent_access_path(access_path:String):
	if access_path == "":
		return 0
	if access_path.find(".") == 0:
		return indent_size
	else:
		return (access_path.count(".") + 1) * indent_size

func get_indent_code_edit(line:int):
	return code_edit.get_indent_level(line)
	
	#line = line.
	#var count = 0
	#var i = 0
	#while i < line.length():
		#if line[i] == "\t":
			#count += 1
		#else:
			#break
		#i += 1
	#return count

func get_indent_size():
	return code_edit.get_tab_size()

func is_valid_code(line:int, col:int):
	return code_edit.is_in_string(line, col) == -1 and code_edit.is_in_comment(line, col) == -1


func get_string_map(text:String):
	if string_map_cache.has(text):
		return string_map_cache[text]
	var string_map = URString.get_string_map(text, URString.StringMap.Mode.FULL)
	string_map_cache[text] = string_map
	return string_map



func get_line(line:int, strip_comment:=false, strip_left:=false):
	var line_text = code_edit.get_line(line)
	if not strip_comment: #^r this should also account for strip left?
		return line_text.strip_edges(strip_left, true)
	else:
		var com_idx = line_text.find("#")
		while com_idx != -1:
			if code_edit.is_in_string(line, com_idx) != -1:
				com_idx = line_text.find("#", com_idx + 1)
			else:
				break
		return line_text.substr(0, com_idx).strip_edges(strip_left, true)

func get_extended_line(line_index:int):
	var full_line = ""
	var in_extension:= false
	var start_i = line_index - 1
	while start_i >= 0:
		var line = get_line(start_i, true)
		if not line.ends_with("\\"):
			break
		start_i -= 1
	start_i += 1 # offsets back to last line no extension
	
	while start_i < code_edit.get_line_count() - 1:
		var line = get_line(start_i, true)
		in_extension = line.ends_with("\\")
		full_line += " " + line.trim_suffix("\\") + " "
		start_i += 1
		if not in_extension:
			break
		
	return full_line

func get_line_no_comment(line:int):
	var line_text = code_edit.get_line(line)
	var com_idx = line_text.find("#")
	while com_idx != -1:
		if code_edit.is_in_string(line, com_idx) != -1:
			com_idx = line_text.find("#", com_idx + 1)
		else:
			break
	return line_text.substr(0, com_idx).strip_edges(false)

func get_member_column(line:int):
	var line_text = code_edit.get_line(line)
	return line_text.find(line_text.strip_edges(true, false))
	var search_char = ""
	if line_text.begins_with(" "):
		search_char = " "
	elif line_text.begins_with("\t"):
		search_char = "\t"
	else:
		return 0
	var count = 0
	for i in range(line_text.length()):
		if line_text[i] == search_char:
			count += 1
		else:
			break
	return count

func strip_annotations(stripped_text:String):
	_initialize_regex_annotation()
	while stripped_text.begins_with("@"):
		var _match = _annotation_regex.search(stripped_text)
		if _match:
			var matched_text = _match.get_string()
			stripped_text = stripped_text.substr(matched_text.length()) # Slice the annotation off the front of the line
		else:
			break # Failsafe
	return stripped_text

func check_member_line(member_type:String, member_name:String, line:int, column:int=0, rebuild:=true):
	var t = GDScriptParser.TF.new("CHECK MEMBER" + str([member_type, " ", member_name]))
	var line_text = get_line(line).strip_edges(true, false)
	if column != 0:
		line_text = get_line(line).substr(column).strip_edges(true, false)
	if line_text.begins_with("@"):
		line_text = strip_annotations(line_text)
	if line_text.begins_with(member_type):
		var stripped = line_text.trim_prefix(member_type).strip_edges(true, false)
		#t.stop()
		if stripped.begins_with(member_name):
			return true
		# a lowercase entry name can also start with "const" (enum {constant_a})
		return member_type == Keys.MEMBER_TYPE_CONST and is_enum_entry_line(member_name, line, column)
	# nameless enum entries are consts declared by the entry itself, not `const NAME`
	if member_type == Keys.MEMBER_TYPE_CONST and is_enum_entry_line(member_name, line, column):
		return true
	#t.stop()
	if rebuild:
		parse_text()
	return false

## True when `line` at `column` is the entry `member_name` of a nameless enum. Walks up to the
## owning declaration, which must be `enum {`; a declaration or closed brace on the way means it isn't.
func is_enum_entry_line(member_name:String, line:int, column:int=0) -> bool:
	var text:String = get_line(line, true).substr(column).strip_edges(true, false)
	if not text.begins_with(member_name):
		return false
	var after:String = text.substr(member_name.length(), 1)
	if after != "" and (after.is_valid_ascii_identifier() or after.is_valid_int()):
		return false
	var i:int = line
	while i >= 0:
		var stripped:String = strip_annotations(get_line(i, true, true))
		if is_nameless_enum_declaration(stripped):
			return true
		if i < line and stripped.contains("}"):
			return false
		if Utils.line_has_any_declaration(stripped):
			return false
		i -= 1
	return false

static func is_nameless_enum_declaration(stripped:String) -> bool:
	return stripped.begins_with("enum") and stripped.substr(4).strip_edges(true, false).begins_with("{")


func get_type_from_line(line:int, column:int=0):
	var context = get_line_context_text(line, column)
	return get_type_from_line_text(context)

## returns an array with [member_name, member_type], except functions, which return a dict {func_args, func_return}, keys are in Keys class
func get_type_from_line_text(stripped_line_text:String):
	var data = {}
	if stripped_line_text.begins_with("@"):
		stripped_line_text = strip_annotations(stripped_line_text)
	if stripped_line_text.begins_with(Keywords.FOR):
		#stripped_line_text = "var " + stripped_line_text.get_slice("for ", 1).get_slice(" in ", 0).strip_edges()
		#data["result"] = Utils.get_var_or_const_info(stripped_line_text)
		data["result"] = Utils.get_for_loop_info(stripped_line_text)
		data["type"] = Keys.MEMBER_TYPE_FOR
		return data
	for dec:StringName in Keywords.DECLARATIONS:
		if stripped_line_text.begins_with(dec):
			if dec == &"var " or dec == &"static var ":
				data["result"] = Utils.get_var_or_const_info(stripped_line_text)
			elif dec == &"enum ":
				data["result"] = Utils.get_enum_info(stripped_line_text)
			elif dec == &"const ":
				data["result"] = Utils.get_var_or_const_info(stripped_line_text)
			elif dec == &"func " or dec == &"static func ":
				data["result"] = Utils.get_func_info(stripped_line_text)
			elif dec == &"class ":
				GDScriptParser.print_deb_err(["GET TYPE FROM LINE CLASS - IF THIS CALLS NEED TO MANAGE EXTENDING PATHS"])
				data["result"] = Utils.get_class_info(stripped_line_text)
			elif dec == &"signal ":
				data["result"] = Utils.get_signal_info(stripped_line_text)
			if data.is_empty():
				return {}
			data["type"] = StringName(dec.strip_edges())
			return data
	return {}

func get_member_name_from_line(line:int):
	_initialize_regex_map()
	var text = get_line(line).strip_edges()
	var result = _map_regex.search(text)
	if result:
		var keyword:String = result.get_string(2)
		if result.get_string(1) != "":
			if result.get_string(1) != "static":
				GDScriptParser.print_deb_err(["REGEX MISTAKE SHOULD BE STATIC ", result.get_string(1)])
			keyword = "static " + keyword
		return result.get_string(3)
	return ""


static func get_line_declaration(stripped_line:String) -> StringName:
	for dec in Keywords.DECLARATIONS:
		if stripped_line.begins_with(dec):
			return dec
	return ""

static func get_control_flow(stripped_line:String) -> StringName:
	for cf in Keywords.CONTROL_FLOW_KEYWORDS:
		if stripped_line.begins_with(cf):
			return cf
	return ""

func _get_control_flow_expression(line:int, control_flow_word:String):
	var extended_line = get_extended_line(line)
	return extended_line.get_slice(control_flow_word, 1).get_slice(":", 0).strip_edges()


func get_semi_colon_strings(line:int):
	var line_text = get_line(line, true)
	var semi_idx = line_text.find(";")
	var stmt_start_idx = 0  # Renamed for clarity: this tracks the start of the current statement
	var data = {}

	while semi_idx != -1:
		if is_valid_code(line, semi_idx):
			data[stmt_start_idx] = line_text.substr(stmt_start_idx, semi_idx - stmt_start_idx)
			stmt_start_idx = semi_idx + 1
		semi_idx = line_text.find(";", semi_idx + 1)
	
	if stmt_start_idx < line_text.length():
		var remainder = line_text.substr(stmt_start_idx)
		if not remainder.strip_edges().is_empty():
			data[stmt_start_idx] = remainder
	return data

func remove_comment(line:int, line_text:String):
	var com_idx = line_text.find("#")
	while com_idx != -1:
		if code_edit.is_in_string(line, com_idx) != -1:
			com_idx = line_text.find("#", com_idx + 1)
		else:
			break
	return line_text.substr(0, com_idx)

func get_text_for_auto_complete(line:int, column:int):
	# if the caret or has been moved, reconstruct the string
	if column != code_edit.get_caret_column() or line != code_edit.get_caret_line():
		var lines = code_edit.text.split("\n")
		var current_line = lines[line] as String
		current_line = current_line.insert(column, Keys.CARET_UNI_CHAR)
		lines[line] = current_line
		return "\n".join(lines)
	else:
		return code_edit.get_text_for_code_completion()

#endregion


#region Function

## Get where the current branch forks from the func body.
func get_func_branch_start(line:int, target_indent_level:int, add_class_indent:=true):
	var current_access_indent = target_indent_level
	if add_class_indent:
		current_access_indent += indent_size
	
	var current_indent = get_indent_code_edit(line)
	if current_indent == current_access_indent:
		return line
	
	var i = line
	while i >= 0:
		var line_text = code_edit.get_line(i)
		var stripped = line_text.strip_edges()
		if stripped == "":
			i -= 1
			continue
		stripped = stripped.get_slice("#", 0)
		if stripped == "":
			i -= 1
			continue
		var indent = code_edit.get_indent_level(i)
		if indent > current_indent:
			break
		current_indent = indent
		if current_indent == current_access_indent:
			break
		i -= 1
	return i




#endregion


func _initialize_regex_annotation():
	if not is_instance_valid(_annotation_regex):
		_annotation_regex = RegEx.new()
		_annotation_regex.compile("^@[A-Za-z0-9_]+(?:\\([^)]*\\))?\\s*")

func _initialize_regex_map():
	if not is_instance_valid(_map_regex):
		_map_regex = RegEx.new()
		_map_regex.compile("^(?:(static)\\s+)?(var|func|enum|const|signal|class_name|class)\\s+([a-zA-Z_]\\w*)")

	
