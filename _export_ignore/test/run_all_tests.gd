@tool
extends EditorScript
## Single entry that runs all four gdscript-parser test suites and prints one aggregate report.
##
##   - Editor "Run" (Ctrl+Shift+X) / File > Run    -> _run() below.
##   - Editor console (reusable static):
##         load("res://addons/_lib/gdscript_parser/_export_ignore/test/run_all_tests.gd").run_all()   # -> String report
##         load("res://addons/_lib/gdscript_parser/_export_ignore/test/run_all_tests.gd").run_tests() # -> {result, output}
##   - Headless (all suites, with exit code):      run_all_headless.gd
##
## Every suite exposes the same `static _run(out: Array) -> int` contract (appends its report lines to
## `out`, returns its fail count), so each is executed exactly once here.

const SUITES := [
	{"name": "Cache Policy", "script": "res://addons/_lib/gdscript_parser/_export_ignore/test/cache_policy_test.gd"},
	{"name": "Source Provider", "script": "res://addons/_lib/gdscript_parser/_export_ignore/test/source_provider_test.gd"},
	{"name": "Access Path",              "script": "res://addons/_lib/gdscript_parser/_export_ignore/test/access_path_test.gd"},
	{"name": "Inference",                "script": "res://addons/_lib/gdscript_parser/_export_ignore/test/inference_test.gd"},
	{"name": "Cross-Script Cache",       "script": "res://addons/_lib/gdscript_parser/_export_ignore/test/cross_script_cache_test.gd"},
	{"name": "Serialization Round-Trip", "script": "res://addons/_lib/gdscript_parser/_export_ignore/test/serialization_roundtrip_test.gd"},
	{"name": "Member Metadata",          "script": "res://addons/_lib/gdscript_parser/_export_ignore/test/member_metadata_test.gd"},
	{"name": "Declaring Script",         "script": "res://addons/_lib/gdscript_parser/_export_ignore/test/declaring_script_test.gd"},
	{"name": "Global Enum",              "script": "res://addons/_lib/gdscript_parser/_export_ignore/test/global_enum_test.gd"},
	{"name": "Builtin Return",           "script": "res://addons/_lib/gdscript_parser/_export_ignore/test/builtin_return_test.gd"},
	{"name": "Class At Line",            "script": "res://addons/_lib/gdscript_parser/_export_ignore/test/class_at_line_test.gd"},
	{"name": "Live Edit Lines",          "script": "res://addons/_lib/gdscript_parser/_export_ignore/test/live_edit_lines_test.gd"},
	{"name": "Nameless Enum + Lambda",   "script": "res://addons/_lib/gdscript_parser/_export_ignore/test/nameless_enum_lambda_test.gd"},
	{"name": "Lambda Scope",             "script": "res://addons/_lib/gdscript_parser/_export_ignore/test/lambda_scope_test.gd"},
	{"name": "Inline Lambdas",           "script": "res://addons/_lib/gdscript_parser/_export_ignore/test/inline_lambda_test.gd"},
	{"name": "Relative Preloads",        "script": "res://addons/_lib/gdscript_parser/_export_ignore/test/relative_preload_test.gd"},
	{"name": "LSP Reparent",             "script": "res://addons/_lib/gdscript_parser/_export_ignore/test/lsp_reparent_test.gd"},
]


func _run() -> void:
	print(run_all())


## Returns the full aggregate report as text (does not quit / print). Reusable from the console.
static func run_all() -> String:
	var out: Array = []
	fill(out)
	return "\n".join(out)


## Runs all suites and returns a structured result for the editor-console `test` command:
## `{"result": int, "output": Array}` where `result` is the total failure count (0 == all good) and
## `output` holds the report lines (the caller decides whether/how to render them). Does not print.
static func run_tests() -> Dictionary:
	var out: Array = []
	var total := fill(out)
	return {"result": total, "output": out}


## Runs every suite once into `out`; returns the summed failure count. Shared by run_all_headless.gd.
static func fill(out: Array) -> int:
	var total := 0
	for s in SUITES:
		out.append("\n########## %s ##########" % s.name)
		total += load(s.script)._run(out)
	# A suite that skipped its backend-dependent work must never read as a clean pass. Suites emit the
	# standard "SKIP:" line (lsp_support.gd), so count those and report them next to the failures.
	var skipped := 0
	for line in out:
		if str(line).strip_edges().begins_with("SKIP:"):
			skipped += 1
	out.append("\n================= TOTAL FAILURES: %d   SKIPPED: %d =================" % [total, skipped])
	return total
