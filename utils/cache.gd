#! import_p Keys,
##
## ScriptCache - the whole persistent (on-disk) parse-cache subsystem in one place.
##
## A GDScriptParser is either LIVE (owns a CodeEdit, resolves from source at query time) or
## CACHED_RESOLVED (rehydrated from disk: carries structure + resolve cache, no CodeEdit until a
## resolve-cache miss lazily attaches a read-only source buffer). Everything here is static and
## dependency-injected - pass the parser / class / func in - so the data flow is explicit and the
## call sites in the parser core stay thin.
##
## Layout (per script) on disk: `<dir>/<hash(script_path)>.bin` via FileAccess.store_var(_, false).
##   { schema_version, parser_version, script_path, mtime,
##     classes: { access_path: { <class fields>, members/constants: { name: {..resolved:{}} },
##                               inner_classes, functions: { name: {..} } } } }

const GDScriptParser = preload("uid://c4465kdwgj042") #! resolve ALibRuntime.Utils.UGDScript.Parser
const Keys = GDScriptParser.Keys
const Utils = GDScriptParser.Utils
const ParserRef = Utils.ParserRef
const InferenceContext = GDScriptParser.InferenceContext

# --- parser state -------------------------------------------------------------------------------
const STATE_LIVE = 0
const STATE_CACHED_RESOLVED = 1

# --- versioning / location ----------------------------------------------------------------------
const DEFAULT_DIR = "res://.godot/addons/gdscript_parser/parse_cache"
const SCHEMA_VERSION = 2 # bump when the on-disk dict layout changes
const PARSER_VERSION = 2 # bump when parse/resolve logic changes -> invalidates all cache files

# --- on-disk dict keys (cache-local; not in the shared Keys registry) ---------------------------
const PCACHE_SCHEMA = &"schema_version"
const PCACHE_PARSER_VER = &"parser_version"
const PCACHE_MEMBERS = &"members"
const PCACHE_CONSTANTS = &"constants"
const PCACHE_INNER = &"inner_classes"
const PCACHE_FUNCTIONS = &"functions"
const PCACHE_RESOLVED = &"resolved"
const PCACHE_LINE_INDEXES = &"line_indexes"
const PCACHE_CLASS_NAME_DATA = &"class_name_data"
const PCACHE_INDENT_LEVEL = &"indent_level"
const PCACHE_MAIN_SCRIPT_PATH = &"main_script_path"
const PCACHE_SCRIPT_BASE_TYPE = &"script_base_type"
const PCACHE_SCRIPT_ACCESS_PATH = &"script_access_path"
const PCACHE_RETURN_TYPE_RAW = &"return_type_raw"
const PCACHE_HAS_STATIC_RETURN = &"has_static_return"
const PCACHE_ARGUMENTS = &"arguments"
const PCACHE_FUNC_CACHE = &"func_cache"
const PCACHE_CLASS_INDENT = &"class_indent"
const PCACHE_INHERITED = &"inherited_members"   # members merged in from base/outer scripts
const PCACHE_INH_SCRIPTS = &"inherited_scripts" # ancestor script paths the above came from
const PCACHE_INH_MOD = &"inherited_mod"         # {ancestor_path: mtime} baseline for staleness checks
const CACHE_DEPS = &"deps" # dependency map key inside a resolve-cache entry


#region Serialization
## Plain-data (no live objects / refs) representation of a ParserClass. The resolve cache is folded
## into each member entry under PCACHE_RESOLVED so the file is a single flat class descriptor.
static func serialize_class(class_obj) -> Dictionary:
	var funcs:Dictionary = {}
	for fname:String in class_obj.functions.keys():
		funcs[fname] = serialize_func(class_obj.functions[fname])
	# force inherited members to compute (populates inherited_scripts); persisting them lets a
	# rehydrated parser answer cross-script inheritance without a re-parse.
	var inherited:Dictionary = class_obj.get_inherited_members().duplicate(true)
	# Build the ancestor-mtime baseline deterministically from inherited_scripts (the live parser's
	# _inherited_script_mod_cache lags a call behind due to get_inherited_members ordering, so it's not
	# stable to serialize directly). Keyed exactly as _check_inherited_valid keys it, so on rehydrate
	# the monitor matches unchanged parents and only clears when one actually changed.
	var inh_mod:Dictionary = {}
	for isp in class_obj.inherited_scripts:
		var sp:String = GDScriptParser.UString.get_script_path_and_suffix(String(isp))[0]
		inh_mod[sp] = FileAccess.get_modified_time(sp)
	return {
		Keys.ACCESS_PATH: class_obj.access_path,
		Keys.EXTENDS: class_obj.extended,
		Keys.LINE_INDEX: class_obj.declaration_line,
		PCACHE_LINE_INDEXES: class_obj.line_indexes,
		PCACHE_INDENT_LEVEL: class_obj.indent_level,
		PCACHE_CLASS_NAME_DATA: class_obj.class_name_data.duplicate(true),
		PCACHE_MAIN_SCRIPT_PATH: class_obj.main_script_path,
		PCACHE_SCRIPT_BASE_TYPE: class_obj.script_base_type,
		PCACHE_SCRIPT_ACCESS_PATH: class_obj.script_access_path,
		PCACHE_MEMBERS: _members_to_cache(class_obj, class_obj.members),
		PCACHE_CONSTANTS: _members_to_cache(class_obj, class_obj.constants),
		PCACHE_INNER: class_obj.inner_classes.duplicate(true),
		PCACHE_FUNCTIONS: funcs,
		PCACHE_INHERITED: inherited,
		PCACHE_INH_SCRIPTS: class_obj.inherited_scripts.duplicate(),
		PCACHE_INH_MOD: inh_mod,
	}

static func _members_to_cache(class_obj, dict:Dictionary) -> Dictionary:
	var out:Dictionary = {}
	for mname:String in dict.keys():
		var entry:Dictionary = dict[mname].duplicate(true)
		if class_obj._resolve_cache.has(mname):
			var folded:Dictionary = class_obj._resolve_cache[mname].duplicate(true)
			if folded.has(Keys.CLASS_CACHE_TYPE) and folded[Keys.CLASS_CACHE_TYPE] is Dictionary:
				folded[Keys.CLASS_CACHE_TYPE] = trim_type_rich(folded[Keys.CLASS_CACHE_TYPE])
			entry[PCACHE_RESOLVED] = folded
		out[mname] = entry
	return out

## Rebuild a ParserClass (and its ParserFuncs) from serialize_class() output, rewiring back-refs and
## splitting the folded resolve cache back out into _resolve_cache.
static func deserialize_class(data:Dictionary, parser) -> GDScriptParser.ParserClass:
	var obj:GDScriptParser.ParserClass = GDScriptParser.ParserClass.new()
	ParserRef.set_refs(obj, parser)
	obj.access_path = data.get(Keys.ACCESS_PATH, "")
	obj.extended = data.get(Keys.EXTENDS, "RefCounted")
	obj.declaration_line = data.get(Keys.LINE_INDEX, 0)
	obj.line_indexes = data.get(PCACHE_LINE_INDEXES, PackedInt32Array())
	obj.indent_level = data.get(PCACHE_INDENT_LEVEL, 0)
	obj.class_name_data = data.get(PCACHE_CLASS_NAME_DATA, {})
	obj.main_script_path = data.get(PCACHE_MAIN_SCRIPT_PATH, "")
	obj.script_base_type = data.get(PCACHE_SCRIPT_BASE_TYPE, "RefCounted")
	obj.script_access_path = data.get(PCACHE_SCRIPT_ACCESS_PATH, "")
	obj.inner_classes = data.get(PCACHE_INNER, {})
	obj.members = _members_from_cache(obj, data.get(PCACHE_MEMBERS, {}))
	obj.constants = _members_from_cache(obj, data.get(PCACHE_CONSTANTS, {}))
	var funcs:Dictionary = data.get(PCACHE_FUNCTIONS, {})
	for fname:String in funcs.keys():
		obj.functions[fname] = deserialize_func(funcs[fname], parser, obj)

	# Restore inherited data directly - do NOT recompute here: get_inherited_members() walks to parent
	# / outer classes that may not be deserialized yet. Restoring inherited_scripts + the mtime baseline
	# lets the existing _check_inherited_valid() monitor (run lazily at query time) detect a changed
	# parent and recompute then, when every class is present.
	obj.inherited_members = data.get(PCACHE_INHERITED, {})
	obj.inherited_scripts = data.get(PCACHE_INH_SCRIPTS, [])
	obj._inherited_script_mod_cache = data.get(PCACHE_INH_MOD, {})
	return obj

static func _members_from_cache(class_obj, dict:Dictionary) -> Dictionary:
	var out:Dictionary = {}
	for mname:String in dict.keys():
		var entry:Dictionary = dict[mname].duplicate(true)
		if entry.has(PCACHE_RESOLVED):
			class_obj._resolve_cache[mname] = entry[PCACHE_RESOLVED]
			entry.erase(PCACHE_RESOLVED)
		out[mname] = entry
	return out

## Plain-data representation of a ParserFunc. Its local-var resolve cache (_cache) is kept with
## member_stacks trimmed.
static func serialize_func(func_obj) -> Dictionary:
	return {
		Keys.MEMBER_NAME: func_obj.name,
		Keys.MEMBER_TYPE: func_obj.member_data.duplicate(true),
		Keys.LINE_INDEX: func_obj.declaration_line,
		Keys.FUNC_LINES: func_obj.func_lines,
		PCACHE_CLASS_INDENT: func_obj.class_indent,
		PCACHE_RETURN_TYPE_RAW: func_obj._return_type_raw,
		Keys.TYPE: func_obj._return_type,
		PCACHE_HAS_STATIC_RETURN: func_obj._has_static_return,
		PCACHE_ARGUMENTS: func_obj.arguments.duplicate(true),
		Keys.LOCAL_VARS: func_obj.local_vars.duplicate(true),
		PCACHE_FUNC_CACHE: _serialize_func_cache(func_obj),
	}

static func _serialize_func_cache(func_obj) -> Dictionary:
	var out:Dictionary = {}
	for key:String in func_obj._cache.keys():
		var trimmed:Dictionary = func_obj._cache[key].duplicate(true)
		if trimmed.has(Keys.CLASS_CACHE_TYPE) and trimmed[Keys.CLASS_CACHE_TYPE] is Dictionary:
			trimmed[Keys.CLASS_CACHE_TYPE] = trim_type_rich(trimmed[Keys.CLASS_CACHE_TYPE])
		out[key] = trimmed
	return out

static func deserialize_func(data:Dictionary, parser, class_obj) -> GDScriptParser.ParserFunc:
	var f:GDScriptParser.ParserFunc = GDScriptParser.ParserFunc.new()
	f.name = data.get(Keys.MEMBER_NAME, "")
	ParserRef.set_refs(f, parser, class_obj)
	f.member_data = data.get(Keys.MEMBER_TYPE, {})
	f.declaration_line = data.get(Keys.LINE_INDEX, -1)
	f.func_lines = data.get(Keys.FUNC_LINES, PackedInt32Array())
	f.class_indent = data.get(PCACHE_CLASS_INDENT, 0)
	f._return_type_raw = data.get(PCACHE_RETURN_TYPE_RAW, "")
	f._return_type = data.get(Keys.TYPE, "")
	f._has_static_return = data.get(PCACHE_HAS_STATIC_RETURN, false)
	f.arguments = data.get(PCACHE_ARGUMENTS, {})
	f.local_vars = data.get(Keys.LOCAL_VARS, {})
	f._cache = data.get(PCACHE_FUNC_CACHE, {})
	# data was already fully parsed + resolved when cached; mark clean so no live re-read is needed.
	f._local_vars_mapped = true
	f._cache_dirty = false
	return f

## Copy of a type_rich with the (potentially large) member_stack dropped - deps are stored
## separately, so the stack is only needed to re-derive them on a fresh resolve.
static func trim_type_rich(type_rich:Dictionary) -> Dictionary:
	var out:Dictionary = type_rich.duplicate(true)
	out["member_stack"] = []
	return out
#endregion


#region Disk IO
static func cache_file_path(dir:String, script_path:String) -> String:
	# hashed filename; the original path is stored inside for a collision guard on read.
	return dir.path_join("%s.bin" % str(script_path.hash()))

static func ensure_dir(dir:String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	ensure_version(dir)

# once-per-dir-per-session guard so the version check is not repeated on every read/write.
static var _version_checked_dirs:Dictionary = {}

## Housekeeping: if the on-disk cache was written by a different schema/parser version, wipe it.
## (Per-file version stamps already prevent stale reads; this just reclaims dead files.)
static func ensure_version(dir:String) -> void:
	if _version_checked_dirs.has(dir):
		return
	_version_checked_dirs[dir] = true
	var marker:String = dir.path_join(".version")
	var current:String = "%d.%d" % [SCHEMA_VERSION, PARSER_VERSION]
	var stored:String = ""
	if FileAccess.file_exists(marker):
		stored = FileAccess.get_file_as_string(marker).strip_edges()
	if stored == current:
		return
	wipe_dir(dir)
	var file:FileAccess = FileAccess.open(marker, FileAccess.WRITE)
	if file != null:
		file.store_string(current)
		file.close()

static func wipe_dir(dir:String) -> void:
	var d:DirAccess = DirAccess.open(dir)
	if d == null:
		return
	for file_name:String in d.get_files():
		if file_name.ends_with(".bin"):
			d.remove(file_name)

## Remove cache files whose source script no longer exists (deleted / renamed / moved). The filename
## is a hash, so the origin path is recovered from each file's stored Keys.SCRIPT_PATH. Unreadable /
## malformed files are reclaimed too. Stale-but-present files are left alone (read-side mtime/version
## checks already reject them). Returns the number removed. No caller wired - invoke from wherever.
static func prune(cache_dir:String = "") -> int:
	if cache_dir.is_empty():
		cache_dir = DEFAULT_DIR
	var d:DirAccess = DirAccess.open(cache_dir)
	if d == null:
		return 0
	var removed:int = 0
	for fname:String in d.get_files():
		if not fname.ends_with(".bin"):
			continue # skip the .version marker and anything else
		var keep:bool = false
		var f:FileAccess = FileAccess.open(cache_dir.path_join(fname), FileAccess.READ)
		if f != null:
			var data:Variant = f.get_var(false)
			f.close()
			if data is Dictionary:
				var sp:String = str(data.get(Keys.SCRIPT_PATH, ""))
				keep = sp != "" and FileAccess.file_exists(sp)
		if not keep: # orphaned source, or unreadable/corrupt -> reclaim
			d.remove(fname)
			removed += 1
	return removed

## Serialize a parser's parsed+resolved classes to disk. Returns true on success.
static func write(parser) -> bool:
	if parser._script_path.is_empty() or parser._class_access.is_empty():
		return false
	if not FileAccess.file_exists(parser._script_path):
		return false
	var classes:Dictionary = {}
	for access_path:String in parser._class_access.keys():
		classes[access_path] = serialize_class(parser._class_access[access_path])
	var data:Dictionary = {
		PCACHE_SCHEMA: SCHEMA_VERSION,
		PCACHE_PARSER_VER: PARSER_VERSION,
		Keys.SCRIPT_PATH: parser._script_path,
		Keys.CACHE_MODIFIED: FileAccess.get_modified_time(parser._script_path),
		Keys.CACHE_CLASSES: classes,
	}
	ensure_dir(parser._parse_cache_dir)
	var file:FileAccess = FileAccess.open(cache_file_path(parser._parse_cache_dir, parser._script_path), FileAccess.WRITE)
	if file == null:
		return false
	file.store_var(data, false) # full_objects=false -> plain data only; fails loudly if an object leaks in
	file.close()
	return true

## Rehydrate a headless CACHED_RESOLVED parser from disk, or null if missing / stale / invalid.
## Validation: schema + parser version, stored path (hash-collision guard), and file mtime.
## `dispatcher` is the parser doing the lookup - it supplies the cache dict + dir for the new parser.
static func read(dispatcher, script_path:String) -> GDScriptParser:
	return _read(script_path, dispatcher._parse_cache_dir, dispatcher._parser_cache)

## Dispatcher-less disk read: standalone CACHED_RESOLVED parser with its own empty parser cache.
static func read_standalone(script_path:String, cache_dir:String) -> GDScriptParser:
	return _read(script_path, cache_dir, {})

## Core rehydrate: shared by read (dispatched) and read_standalone. Returns null if missing/stale.
static func _read(script_path:String, dir:String, parser_cache:Dictionary) -> GDScriptParser:
	if DirAccess.dir_exists_absolute(dir):
		ensure_version(dir) # boot-time housekeeping wipe if the version changed
	var file_path:String = cache_file_path(dir, script_path)
	if not FileAccess.file_exists(file_path):
		return null
	var file:FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return null
	var data:Variant = file.get_var(false)
	file.close()
	if not data is Dictionary:
		return null
	if data.get(PCACHE_SCHEMA) != SCHEMA_VERSION:
		return null
	if data.get(PCACHE_PARSER_VER) != PARSER_VERSION:
		return null
	if data.get(Keys.SCRIPT_PATH) != script_path:
		return null
	if data.get(Keys.CACHE_MODIFIED, -1) != FileAccess.get_modified_time(script_path):
		return null

	var parser:GDScriptParser = GDScriptParser.new()
	parser.set_parser_cache(parser_cache)
	parser.set_parse_cache_dir(dir)
	parser._script_path = script_path
	parser.state = STATE_CACHED_RESOLVED
	var classes:Dictionary = data.get(Keys.CACHE_CLASSES, {})
	for access_path:String in classes.keys():
		parser._set_class_obj(access_path, deserialize_class(classes[access_path], parser))
	# Eager staleness check now that every class is present: drops inherited_members whose ancestor
	# scripts changed since the cache was written (mtime-only - no cross-script re-derive here; that
	# happens lazily on the next get_inherited_members()). Ordering-safe: all classes exist.
	for c in parser._class_access.values():
		c._check_inherited_valid()
	return parser

## Cache-aware constructor. Builds a ready-to-use parser for `script_path`:
##   - `code_edit` given (current, editable script): always LIVE, bound to that CodeEdit. The disk
##     cache still serves this parser's cross-script lookups via the shared dir; the live buffer is
##     authoritative for its own structure.
##   - no `code_edit` (read-only use): return the disk-cached CACHED_RESOLVED parser if valid, else
##     a buffer-backed LIVE parse of the file on disk.
static func from_cache(script_path:String, cache_dir:String = "", code_edit = null) -> GDScriptParser:
	if cache_dir.is_empty():
		cache_dir = DEFAULT_DIR
	if code_edit == null:
		var cached:GDScriptParser = read_standalone(script_path, cache_dir)
		if cached != null:
			return cached
	var parser:GDScriptParser = GDScriptParser.new()
	parser.set_parse_cache_dir(cache_dir)
	if not FileAccess.file_exists(script_path):
		return parser
	var script:GDScript = load(script_path)
	if not is_instance_valid(script):
		return parser
	parser.set_current_script(script)
	if code_edit != null:
		parser.set_code_edit(code_edit)
	else:
		parser.set_source_code(script.source_code)
	parser.parse()
	return parser
#endregion


#region Source lifecycle + validity
## Attach a read-only source buffer to a CACHED_RESOLVED parser so line-reads (check_member_line /
## get_type_from_line) work on a resolve-cache miss, WITHOUT clearing the cached class structure.
## Loads _script_resource first, so a valid code_edit implies a valid _script_resource.
static func ensure_source(parser) -> void:
	if is_instance_valid(parser.code_edit):
		return
	if not is_instance_valid(parser._script_resource) and FileAccess.file_exists(parser._script_path):
		parser._script_resource = load(parser._script_path)
	parser._create_buffer_code_edit()
	if is_instance_valid(parser._script_resource):
		parser.code_edit.text = parser._script_resource.source_code
	parser.code_edit_parser.sync_code_edit() # wire the tokenizer's code_edit for single-line reads

## The choke-point hook: called wherever the tokenizer / current script is fetched. No-op unless the
## parser is a source-less CACHED_RESOLVED parser.
static func ensure_source_if_cached(parser) -> void:
	if is_instance_valid(parser) and parser.state == STATE_CACHED_RESOLVED:
		ensure_source(parser)

## Promote a CACHED_RESOLVED parser to a full live parse (used when the source file changed since it
## was cached). Discards the cached structure and re-parses from disk.
static func upgrade_to_live(parser) -> void:
	if parser.state == STATE_LIVE:
		return
	parser.state = STATE_LIVE
	if not FileAccess.file_exists(parser._script_path):
		return
	var script:GDScript = load(parser._script_path)
	if not is_instance_valid(script):
		return
	parser.set_current_script(script) # clears _class_access
	parser.set_source_code(script.source_code)
	parser.parse(true)

## Resolve-cache validity for a CACHED_RESOLVED parser: no live source, so trust the persisted
## resolve if its deps still hold (own-file staleness is impossible - read() only rehydrates when the
## on-disk mtime matches).
static func cached_resolve_valid(class_obj, identifier:String) -> bool:
	var cd:Dictionary = class_obj._resolve_cache.get(identifier, {})
	var cd_type = cd.get(Keys.CLASS_CACHE_TYPE, {})
	if not (cd_type is Dictionary) or cd_type.get("type", "") == "":
		return false
	var cd_deps = cd.get(CACHE_DEPS, {})
	if cd_deps == null:
		cd_deps = {}
	return InferenceContext.validate_dependencies(cd_deps, class_obj.main_script_path)
#endregion
