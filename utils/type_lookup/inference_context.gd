

var _active_expressions:= {}
var _resolved_expressions:= {}

func has_expression(expression:String) -> bool:
	return _active_expressions.has(expression)

func start_expression(expression:String) -> void:
	_active_expressions[expression] = true

func finish_expression(expression:String, resolved:String) -> void:
	_active_expressions.erase(expression)
	_resolved_expressions[expression] = resolved


func expression_resolved(expression:String) -> bool:
	return _resolved_expressions.has(expression)

func get_resolved_expression(expression:String) -> String:
	return _resolved_expressions.get(expression)


func is_empty() -> bool:
	return _active_expressions.is_empty()
