
const _BLANK = &""
const CARET_UNI_CHAR = &"\uFFFF"

const PARSER_CODE_EDIT = &"_parser_code_edit"

const CONTEXT_TEXT = &"context_text"
const CONTEXT_START = &"context_start"
const CONTEXT_END = &"context_end"
const CONTEXT_BLOCKS = &"context_blocks"
const CONTEXT_LOCAL_VARS = &"context_local_vars"
const CONTEXT_SEMI_COLON = &"context_semi_colon"

# var type
const MEMBER_TYPE_FUNC_ARG = &"func_arg"
const MEMBER_TYPE_STATIC_FUNC = &"static func"
const MEMBER_TYPE_FUNC = &"func"
const MEMBER_TYPE_STATIC_VAR = &"static var"
const MEMBER_TYPE_VAR = &"var"
const MEMBER_TYPE_CONST = &"const"
const MEMBER_TYPE_ENUM = &"enum"
const MEMBER_TYPE_CLASS = &"class"
const MEMBER_TYPE_SIGNAL = &"signal"

const ENUM_PATH_SUFFIX = &"::Enum"

# map keys

const CLASS_INDENT = &"class_indent"
const MEMBER_NAME = &"member_name"
const MEMBER_TYPE = &"member_type"
const LINE_INDEX = &"line_index"
const COLUMN_INDEX = &"column_index"
const FUNC_LINES = &"func_lines"
const ANNOTATIONS = &"annotations"

const TYPE = &"type"
const TYPE_RESOLVED = &"type_resolved"

const CLASS_BODY = &"#body" # this is not for data


# member info
const FUNC_NAME = &"func_name"
const FUNC_ARGS = &"func_args"
const FUNC_RETURN = &"func_return"

const SIGNAL_NAME = &"signal_name"
const SIGNAL_ARGS = &"signal_args"



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
