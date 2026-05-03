const _UString = preload("res://addons/addon_lib/brohd/alib_runtime/utils/u_string.gd")
const _GDScriptParse = _UString.GDScriptParse

const _BLANK = &""
const CARET_UNI_CHAR = &"\uFFFF"

# parser
const GET_PARSER = &"parser"
const GET_CLASS_OBJ = &"class_obj"

# gdscript parser cache
const CACHE_ACTIVE_PARSERS = &"cache_active_parsers"
const CACHE_INACTIVE_PARSERS = &"cache_inactive_parsers"

const CACHE_MODIFIED = &"modified"
const CACHE_PARSER = &"parser"
const CACHE_CLASSES = &"cache_classes"

# class resolve cache
const CLASS_CACHE_DEC = &"class_cache_dec"
const CLASS_CACHE_TYPE = &"class_cache_type"
const CLASS_CACHE_VALUE = &"class_cache_value"
const CLASS_CACHE_DEPENDENCIES = &"class_cache_depencies"

const PARSER_CODE_EDIT = &"_parser_code_edit"

const CONTEXT_TEXT = &"context_text"
const CONTEXT_START = &"context_start"
const CONTEXT_END = &"context_end"
const CONTEXT_BLOCKS = &"context_blocks"
const CONTEXT_LOCAL_VARS = &"context_local_vars"
const CONTEXT_SEMI_COLON = &"context_semi_colon"

# var type

const MEMBER_TYPE_STATIC_FUNC = &"static func"
const MEMBER_TYPE_FUNC = &"func"
const MEMBER_TYPE_STATIC_VAR = &"static var"
const MEMBER_TYPE_VAR = &"var"
const MEMBER_TYPE_CONST = &"const"
const MEMBER_TYPE_ENUM = &"enum"
const MEMBER_TYPE_CLASS = &"class"
const MEMBER_TYPE_SIGNAL = &"signal"

const MEMBER_TYPE_FUNC_ARG = &"func_arg"
const MEMBER_TYPE_FOR = &"for"


# type lookup
const MEMBER_DELIM = &"::"
const TYPE_DELIM = &"##"
const MEMBER_INFER_DELIM = &":;;:"
const INS_DELIM = &"$$INS"

const ENUM_PATH_SUFFIX = TYPE_DELIM + &"Enum"
const CALLABLE_SUFFIX = TYPE_DELIM + &"Callable"
const SIGNAL_SUFFIX = TYPE_DELIM + &"Signal"



# map keys

const EXTENDS = &"extends"
const CLASS_INDENT = &"class_indent"
const MEMBER_NAME = &"member_name"
const MEMBER_TYPE = &"member_type"
const LINE_INDEX = &"line_index"
const COLUMN_INDEX = &"column_index"
const FUNC_LINES = &"func_lines"
const ANNOTATIONS = &"annotations"
const ACCESS_PATH = &"access_path"
const SCRIPT_PATH = &"script_path"

const TYPE = &"type"
const TYPE_RESOLVED = &"type_resolved"

const CLASS_BODY = &"#body" # this is not for data


# member info - load these so they can be used elsewhere
const FUNC_NAME = _GDScriptParse.Keys.FUNC_NAME
const FUNC_ARGS = _GDScriptParse.Keys.FUNC_ARGS
const FUNC_RETURN = _GDScriptParse.Keys.FUNC_RETURN

const SIGNAL_NAME = _GDScriptParse.Keys.SIGNAL_NAME
const SIGNAL_ARGS = _GDScriptParse.Keys.SIGNAL_ARGS



const LOCAL_VARS = &"#local" # is this used?

# UNUSED
const DECLARATION = &"dec_line"
const INDENT = &"indent"
const SNAPSHOT = &"snapshot"


const CLASS_MASK = &"class_mask"
const CONST = &"const"


const ENUM_MEMBERS = &"enum_members"




# data cache keys
const SCRIPT_PRELOAD_MAP = &"ScriptPreloadMap"
const SCRIPT_INHERITED_MEMBERS = &"ScriptInheritedMembers"
const SCRIPTS_AS_TEXT = &"ScriptsAsText"

# code completion keys
const SCRIPT_MEMBERS_MAPPED = &"ScriptMembersMapped"
const SCRIPT_SOURCE_CHECK = &"ScriptSourceChecks"
const SCRIPT_DECLARATIONS_TEXT = &"ScriptDeclarationsText"
const SCRIPT_DECLARATIONS_DATA = &"ScriptDeclarationsData"
const IN_SCOPE_VARS = &"InScopeVars"
const SCRIPT_FULL_PRELOAD_MAP = &"FullPreloadMap"
