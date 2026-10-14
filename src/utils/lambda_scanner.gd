extends RefCounted
## Expression ranges for the parser mode without tree-sitter. Positions exposed to
## consumers use UTF-8 bytes, matching the extension; scanning uses character offsets.

static func scan(source: String) -> Array:
	var tokens: Array = _tokens(source)
	var found: Array = []
	for i in range(tokens.size() - 1, -1, -1):
		var token: Dictionary = tokens[i]
		if token.text != "func":
			continue
		var prefix: String = source.substr(token.offset - token.column, token.column).strip_edges()
		if token.depth == 0 and (prefix.is_empty() or prefix == "static"):
			continue
		var open: int = i + 1
		if open < tokens.size() and tokens[open].text != "(":
			open += 1 # optional lambda name
		if open >= tokens.size() or tokens[open].text != "(":
			continue
		var close: int = _matching(tokens, open)
		if close == -1:
			continue
		var colon: int = close + 1
		while colon < tokens.size() and tokens[colon].text != ":":
			if tokens[colon].text == "\n":
				break
			colon += 1
		if colon >= tokens.size() or tokens[colon].text != ":":
			continue
		var body: int = colon + 1
		while body < tokens.size() and tokens[body].text in ["\n", "comment"]:
			body += 1
		var multiline: bool = body < tokens.size() and tokens[body].line > tokens[colon].line
		var end: int = tokens[colon].end
		var j: int = body
		var depth: int = 0
		while j < tokens.size():
			var current: Dictionary = tokens[j]
			if current.text == "\n":
				if not multiline and depth == 0:
					break
				j += 1
				continue
			if depth == 0:
				if current.text in [")", "]", "}", ","]:
					break
				if multiline and current.line > tokens[colon].line and current.indent <= token.indent:
					break
			var nested_end: int = -1
			for nested: Dictionary in found:
				if nested._start == current.offset:
					nested_end = nested._end
					break
			if nested_end >= 0:
				end = nested_end
				while j < tokens.size() and tokens[j].offset < nested_end:
					j += 1
				continue
			if current.text in ["(", "[", "{"]:
				depth += 1
			elif current.text in [")", "]", "}"]:
				depth -= 1
			end = current.end
			j += 1
		var before: String = source.substr(token.offset - token.column, token.column)
		var assignment := RegEx.new()
		assignment.compile("(?:^|;)\\s*(?:static\\s+)?var\\s+([A-Za-z_][A-Za-z_0-9]*)(?:\\s*:[^=]+)?\\s*:?=\\s*$")
		var match_var: RegExMatch = assignment.search(before)
		var owner: String = "" if match_var == null else match_var.get_string(1)
		var owner_column: int = -1 if match_var == null else before.find("var", match_var.get_start())
		var finish: Vector2i = _position(source, end)
		found.push_front({"line_index": token.line, "column_index": before.to_utf8_buffer().size(),
			"end_line": finish.x, "end_column": finish.y, "_start": token.offset, "_end": end,
			"_owner": owner, "_owner_column": owner_column, "_children": []})
	var roots: Array = []
	var stack: Array = []
	for entry: Dictionary in found:
		while not stack.is_empty() and entry._start >= stack.back()._end:
			stack.pop_back()
		if stack.is_empty():
			roots.append(entry)
		else:
			stack.back()._children.append(entry)
		stack.append(entry)
	return roots

static func _matching(tokens: Array, start: int) -> int:
	var depth := 0
	for i in range(start, tokens.size()):
		if tokens[i].text == "(":
			depth += 1
		elif tokens[i].text == ")":
			depth -= 1
			if depth == 0:
				return i
	return -1

static func _position(source: String, offset: int) -> Vector2i:
	var prefix: String = source.left(offset)
	var line: int = prefix.count("\n")
	return Vector2i(line, prefix.substr(prefix.rfind("\n") + 1).to_utf8_buffer().size())

static func _tokens(source: String) -> Array:
	var out: Array = []
	var i := 0
	var line := 0
	var line_start := 0
	var indent := 0
	var depth := 0
	while i < source.length():
		var ch: String = source[i]
		if ch == "\n":
			out.append({"text": ch, "offset": i, "end": i + 1, "line": line, "column": i - line_start, "indent": indent, "depth": depth})
			line += 1
			i += 1
			line_start = i
			indent = 0
			while i + indent < source.length() and source[i + indent] in [" ", "\t"]:
				indent += 1
			continue
		if ch in [" ", "\t", "\r"]:
			i += 1
			continue
		if ch == "#":
			var comment_start:int = i
			while i < source.length() and source[i] != "\n":
				i += 1
			out.append({"text": "comment", "offset": comment_start, "end": i, "line": line,
				"column": comment_start - line_start, "indent": indent, "depth": depth})
			continue
		var start: int = i
		var start_line: int = line
		var column: int = i - line_start
		if ch in ["\"", "'"]:
			var delimiter: String = ch.repeat(3) if source.substr(i, 3) == ch.repeat(3) else ch
			i += delimiter.length()
			while i < source.length():
				if source.substr(i, delimiter.length()) == delimiter:
					i += delimiter.length()
					break
				if source[i] == "\\":
					i += 1
				elif source[i] == "\n":
					line += 1
					line_start = i + 1
				i += 1
			ch = "string"
		elif ch.is_valid_ascii_identifier() or ch.is_valid_int():
			i += 1
			while i < source.length() and (source[i].is_valid_ascii_identifier() or source[i].is_valid_int()):
				i += 1
			ch = source.substr(start, i - start)
		else:
			i += 1
		out.append({"text": ch, "offset": start, "end": i, "line": start_line, "column": column, "indent": indent, "depth": depth})
		if ch in ["(", "[", "{"]:
			depth += 1
		elif ch in [")", "]", "}"]:
			depth = maxi(0, depth - 1)
	return out
