
#! import-p Keys,

const GDScriptParser = preload("res://addons/addon_lib/brohd/alib_runtime/utils/resource/gdscript/parser/gdscript_parser.gd")
const ParserFunc = GDScriptParser.ParserFunc
const Utils = GDScriptParser.Utils
const Keys = Utils.Keys
const UClassDetail = GDScriptParser.UClassDetail


var parser:WeakRef

var access_path:String

var script_resource:GDScript

var source_code:String

var line_indexes:PackedInt32Array

var inner_classes:= {}
var constants:= {}
var members:= {}
var functions:={}


func set_lines(new_lines:PackedInt32Array):
	line_indexes = new_lines
	#print("^^^^ " , access_path)
	#for l in lines:
		#print(parser.source_lines[l])
	#_build_source_code()

func set_members(members_dict:Dictionary):
	var _parser = _get_parser()
	members = members_dict
	#print("MEMBERS: ",members.keys())
	for m in members.keys():
		var data = members[m]
		if data.get(Keys.MEMBER_TYPE) != Keys.MEMBER_TYPE_FUNC:
			continue
		var function = ParserFunc.new()
		function.name = m
		function._parser = weakref(_parser)
		function._class_obj = weakref(self)
		function.member_data = data
		#function.parse()
		functions[m] = function
	

func set_constants(const_dict:Dictionary):
	constants = const_dict
	#print("CONSTANTS: ", constants.keys())

func set_inner_classes(class_dict:Dictionary):
	inner_classes = class_dict
	#print("INNER CLASSES: ", inner_classes.keys())

func get_member(member_name:String):
	if members.has(member_name):
		return members[member_name]
	elif functions.has(member_name):
		return functions[member_name]
	elif constants.has(member_name):
		return constants[member_name]
	elif inner_classes.has(member_name):
		return inner_classes[member_name]



func get_function_at_line(line:int) -> String:
	var script_editor = _get_parser().code_edit
	var func_name:String = ""
	var current_line = line
	while current_line >= 0:
		var line_text = script_editor.get_line(current_line)
		var stripped = line_text.strip_edges()
		var _class = Utils.get_class_name_in_line(stripped)
		if _class != "":
			break
		func_name = Utils.get_func_name_in_line(stripped)
		if func_name != "":
			return func_name
		if stripped != "" and not (line_text.begins_with("\t") or line_text.begins_with(" ") or line_text.begins_with("#")):
			break
		current_line -= 1
	
	return Keys.CLASS_BODY


func get_members():
	var dict = _get_inherited_members()
	dict.merge(members.duplicate())
	dict.merge(constants.duplicate())
	dict.merge(inner_classes.duplicate())
	dict.merge(functions.duplicate())
	return dict




## Get and cache the preloads of current scripts ancestors.
func _get_inherited_members():
	#var inherited_section = data_cache.get_or_add(_Keys.SCRIPT_INHERITED_MEMBERS, {})
	#var cached_data = CacheHelper.get_cached_data(script.resource_path, inherited_section)
	#if cached_data != null:
		#return cached_data
	
	var base_script = script_resource.get_base_script()
	if base_script == null:
		return {}
	
	var inherited_members = UClassDetail.script_get_all_members(base_script, UClassDetail.IncludeInheritance.SCRIPTS_ONLY)
	var inh_paths = UClassDetail.script_get_inherited_script_paths(base_script)
	#CacheHelper.store_data(script_resource.resource_path, inherited_members, inherited_section, inh_paths)
	return inherited_members




func _build_source_code():
	var t = ALibRuntime.Utils.UProfile.TimeFunction.new("Class build source")
	var lines := []
	for i in line_indexes:
		lines.append(_get_parser().code_edit.get_line(i))
	source_code = "\n".join(lines)
	t.stop()


func _get_parser() -> GDScriptParser:
	return parser.get_ref()
