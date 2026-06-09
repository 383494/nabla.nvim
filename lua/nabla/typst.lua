local M = {}

local function get_text(node, buf)
	return vim.treesitter.get_node_text(node, buf)
end

local function extract_string(nodes)
	for _, n in ipairs(nodes) do
		if n.kind == "symexp" then
			return n.sym
		end
	end
	return nil
end

local symbol_map = {
	["->"] = "rightarrow",
	["<-"] = "leftarrow",
	["<->"] = "leftrightarrow",
	["=>"] = "Rightarrow",
	["<="] = "leq",
	[">="] = "geq",
	["!="] = "neq",
	[":="] = "coloneq",
	["<=>"] = "Leftrightarrow",
	["|->"] = "mapsto",
	["==>"] = "Longrightarrow",
	["||"] = "‖",
	["|"] = "|",
	["+"] = "+",
	["-"] = "-",
	["*"] = "·",
	["="] = "=",
	["<"] = "<",
	[">"] = ">",
}

local ident_map = {
	inter = "inter",
	perp = "perp",
	union = "union",
	alpha = "alpha",
	beta = "beta",
	gamma = "gamma",
	delta = "delta",
	epsilon = "epsilon",
	zeta = "zeta",
	eta = "eta",
	theta = "theta",
	iota = "iota",
	kappa = "kappa",
	lambda = "lambda",
	mu = "mu",
	nu = "nu",
	xi = "xi",
	pi = "pi",
	rho = "rho",
	sigma = "sigma",
	tau = "tau",
	upsilon = "upsilon",
	phi = "phi",
	chi = "chi",
	psi = "psi",
	omega = "omega",
	oo = "infty",
	Gamma = "Gamma",
	Delta = "Delta",
	Theta = "Theta",
	Lambda = "Lambda",
	Xi = "Xi",
	Pi = "Pi",
	Sigma = "Sigma",
	Upsilon = "Upsilon",
	Phi = "Phi",
	Psi = "Psi",
	Omega = "Omega",

	forall = "forall",
	exists = "exists",
	["in"] = "in",
	subset = "subset",
	supset = "supset",
	subseteq = "subseteq",
	supseteq = "supseteq",
	infinity = "infty",
	nothing = "emptyset",
	diff = "partial",
	partial = "partial",
	nabla = "nabla",
	gradient = "nabla",
	compose = "circ",
	div = "div",
	times = "times",
	approx = "approx",
	equiv = "equiv",
	prec = "prec",
	succ = "succ",
	sim = "sim",
	simeq = "simeq",
	doteq = "doteq",
	cdot = "cdot",
	dots = "dots",
	cdots = "cdots",
	vdots = "vdots",
	ddots = "ddots",
	ldots = "ldots",

	frac = "frac",
	sqrt = "sqrt",
	root = "root",

	hat = "hat",
	tilde = "tilde",
	dot = "dot",
	ddot = "ddot",
	dddot = "dddot",
	arrow = "vec",
	macron = "overline",
	overline = "overline",
	dash = "dash",
	grave = "grave",
	acute = "acute",
	breve = "breve",
	circle = "circle",
	caron = "caron",

	bold = "boldsymbol",
	bb = "mathbb",
	cal = "mathcal",
	frak = "mathfrak",
	italic = "mathit",
	mono = "mathtt",
	upright = "upright",
	sans = "sans",
	scr = "scr",

	sum = "sum",
	product = "prod",
	integral = "int",

	abs = "bar",
	norm = "Vert",
	floor = "floor",
	ceil = "ceil",
	round = "round",

	cancel = "cancel",
	underline = "underline",
	strike = "strike",
	overbrace = "overbrace",
	underbrace = "underbrace",
	overbracket = "overbracket",
	underbracket = "underbracket",
	overparen = "overparen",
	underparen = "underparen",
	overshell = "overshell",
	undershell = "undershell",
	mid = "mid",

	sin = "sin",
	cos = "cos",
	tan = "tan",
	sec = "sec",
	csc = "csc",
	cot = "cot",
	sinh = "sinh",
	cosh = "cosh",
	tanh = "tanh",
	arccos = "arccos",
	arcsin = "arcsin",
	arctan = "arctan",
	log = "log",
	ln = "ln",
	exp = "exp",
	det = "det",
	gcd = "gcd",
	mod = "mod",
	max = "max",
	min = "min",
	lim = "lim",
	sup = "sup",
	inf = "inf",
	arg = "arg",
	dim = "dim",
	ker = "ker",
	hom = "hom",
	deg = "deg",

	dif = "dif",
	text = "text",
	op = "op",
	lr = "lr",
}

local consumes_args = {
	sqrt = 1,
	hat = 1,
	tilde = 1,
	dot = 1,
	ddot = 1,
	dddot = 1,
	circle = 1,
	caron = 1,
	vec = 1,
	overline = 1,
	dash = 1,
	grave = 1,
	acute = 1,
	breve = 1,
	boldsymbol = 1,
	mathbb = 1,
	mathcal = 1,
	mathfrak = 1,
	mathit = 1,
	mathtt = 1,
	cancel = 1,
	underline = 1,
	strike = 1,
	overbrace = 1,
	underbrace = 1,
	overbracket = 1,
	underbracket = 1,
	overparen = 1,
	underparen = 1,
	overshell = 1,
	undershell = 1,
	bar = 1,
	Vert = 1,
	floor = 1,
	ceil = 1,
	round = 1,
	upright = 1,
	sans = 1,
	scr = 1,
}

local block_fns = {
	mat = "pmatrix",
	cases = "cases",
	binom = "binom",
	vec = "vec",
}

local field_map = {
	["integral.double"] = "iint",
	["integral.triple"] = "iiint",
	["integral.cont"] = "oint",
	["integral.cw"] = "oint",
	["integral.ccw"] = "oint",
	["integral.surf"] = "oiint",
	["integral.vol"] = "oiiint",
	["dot.double"] = "ddot",
	["dot.triple"] = "dddot",
	["dot.quad"] = "ddddot",
	["in.not"] = "notin",
	["plus.minus"] = "pm",
	["minus.plus"] = "mp",
	["lt.tri"] = "lhd",
	["gt.tri"] = "rhd",
	["lt.eq"] = "leq",
	["gt.eq"] = "geq",
	["prec.eq"] = "preceq",
	["succ.eq"] = "succeq",
	["arrow.l"] = "leftarrow",
	["arrow.r"] = "rightarrow",
	["arrow.l.r"] = "leftrightarrow",
	["arrow.t"] = "uparrow",
	["arrow.b"] = "downarrow",
	["tilde.eq"] = "simeq",
	["tilde.not"] = "nsim",
	["star.op"] = "star",
	["slash.op"] = "slash",
	["angle.l"] = "langle",
	["angle.r"] = "rangle",
	["chevron.l"] = "langle",
	["chevron.r"] = "rangle",
}

local function walk_node(node, buf)
	local ntype = node:type()
	local text = get_text(node, buf)

	if ntype == "number" then
		return { { kind = "numexp", num = tonumber(text) } }
	elseif ntype == "letter" then
		return { { kind = "symexp", sym = text } }
	elseif ntype == "ident" then
		if text == "space" then
			return { { kind = "symexp", sym = " " } }
		end
		local mapped = ident_map[text]
		if mapped then
			return { { kind = "funexp", sym = mapped } }
		elseif #text == 2 and text:match("^%u%u$") and text:sub(1, 1) == text:sub(2, 2) then
			return {
				{ kind = "funexp", sym = "mathbb" },
				{ kind = "explist", exps = { { kind = "symexp", sym = text:sub(1, 1) } } },
			}
		else
			return { { kind = "symexp", sym = text } }
		end
	elseif ntype == "symbol" then
		local mapped = symbol_map[text] or text
		return { { kind = "symexp", sym = mapped } }
	elseif ntype == "shorthand" then
		local mapped = symbol_map[text] or text
		return { { kind = "funexp", sym = mapped } }
	elseif ntype == "string" then
		local str = text:gsub('^"', ""):gsub('"$', "")
		return { { kind = "symexp", sym = str } }
	elseif ntype == "field" then
		local mapped = field_map[text]
		if mapped then
			return { { kind = "funexp", sym = mapped } }
		else
			return { { kind = "symexp", sym = text } }
		end
	elseif ntype == "escape" then
		local escaped = text:sub(2)
		if escaped == "," or escaped == ";" or escaped == ":" or escaped == "!" then
			return {}
		else
			return { { kind = "symexp", sym = escaped } }
		end
	elseif ntype == "prime" then
		return M.walk_prime(node, buf)
	elseif ntype == "attach" then
		return M.walk_attach(node, buf)
	elseif ntype == "fraction" then
		return M.walk_fraction(node, buf)
	elseif ntype == "call" then
		return M.walk_call(node, buf)
	elseif ntype == "apply" then
		return M.walk_apply(node, buf)
	elseif ntype == "group" then
		return M.walk_group(node, buf)
	elseif ntype == "formula" then
		return M.walk_formula(node, buf)
	else
		return { { kind = "symexp", sym = text } }
	end
end

function M.walk_formula(formula, buf)
	local result = {}
	local children = {}
	for child in formula:iter_children() do
		if child:named() then
			table.insert(children, child)
		end
	end

	-- Check if formula contains alignment markers
	local has_align = false
	for _, child in ipairs(children) do
		if child:type() == "align" or child:type() == "linebreak" then
			has_align = true
			break
		end
	end

	if has_align then
		-- Build aligned blockexp: & = column sep, \ = row sep (linebreak node)
		local content_exps = {}
		local i = 1
		while i <= #children do
			local child = children[i]
			local ntype = child:type()

			if ntype == "align" then
				table.insert(content_exps, { kind = "symexp", sym = "&" })
				i = i + 1
			elseif ntype == "linebreak" then
				table.insert(content_exps, { kind = "funexp", sym = "\\" })
				i = i + 1
			else
				local nodes = walk_node(child, buf)
				for _, n in ipairs(nodes) do
					table.insert(content_exps, n)
				end
				i = i + 1
			end
		end
		return {{
			kind = "blockexp",
			first = { kind = "explist", exps = { { kind = "symexp", sym = "aligned" } } },
			content = { kind = "explist", exps = content_exps },
		}}
	end

	-- No alignment: process normally
	local i = 1
	while i <= #children do
		local child = children[i]
		local ntype = child:type()
		local text = get_text(child, buf)

		if ntype == "symbol" and (text == "|" or text == "||") then
			local match_nodes = {}
			local depth = 1
			local j = i + 1
			while j <= #children do
				local c = children[j]
				local ct = get_text(c, buf)
				if c:type() == "symbol" and ct == text then
					depth = depth - 1
					if depth == 0 then
						break
					end
				end
				table.insert(match_nodes, c)
				j = j + 1
			end

			if depth == 0 and #match_nodes > 0 then
				local inner = {}
				for _, n in ipairs(match_nodes) do
					local nodes = walk_node(n, buf)
					for _, nd in ipairs(nodes) do
						table.insert(inner, nd)
					end
				end
				local fname = text == "|" and "bar" or "Vert"
				table.insert(result, { kind = "funexp", sym = fname })
				table.insert(result, { kind = "explist", exps = inner })
				i = j + 1
			else
				local mapped = symbol_map[text] or text
				table.insert(result, { kind = "symexp", sym = mapped })
				i = i + 1
			end
		else
			local nodes = walk_node(child, buf)
			for _, n in ipairs(nodes) do
				table.insert(result, n)
			end
			i = i + 1
		end
	end

	return result
end

function M.walk_prime(node, buf)
	local result = {}
	for child in node:iter_children() do
		if child:named() then
			local nodes = walk_node(child, buf)
			for _, n in ipairs(nodes) do
				table.insert(result, n)
			end
		end
	end
	-- Count prime chars from the node text (they aren't child nodes)
	local text = get_text(node, buf)
	local primes = text:gsub("[^']", "")
	if #primes > 0 then
		-- If the parent is an attach with an explicit ^, the prime becomes
		-- part of the base (so f'^2 renders as f'², not f with '2 above).
		-- Otherwise, treat the prime as a standalone superscript.
		local parent = node:parent()
		local has_explicit_hat = false
		if parent and parent:type() == "attach" then
			for child in parent:iter_children() do
				if not child:named() and get_text(child, buf) == "^" then
					has_explicit_hat = true
					break
				end
			end
		end
		if not has_explicit_hat then
			table.insert(result, { kind = "supexp" })
		end
		table.insert(result, { kind = "symexp", sym = primes })
	end
	return result
end

function M.walk_attach(node, buf)
	local result = {}
	local last_token = nil
	local base_done = false

	for child in node:iter_children() do
		if not child:named() then
			local text = get_text(child, buf)
			if text == "_" or text == "^" then
				last_token = text
			end
		else
			if not base_done then
				local base_nodes = walk_node(child, buf)
				for _, n in ipairs(base_nodes) do
					table.insert(result, n)
				end
				base_done = true
			elseif last_token == "_" then
				table.insert(result, { kind = "subexp" })
				local sub_nodes = walk_node(child, buf)
				for _, n in ipairs(sub_nodes) do
					table.insert(result, n)
				end
				last_token = nil
			elseif last_token == "^" then
				table.insert(result, { kind = "supexp" })
				local sup_nodes = walk_node(child, buf)
				for _, n in ipairs(sup_nodes) do
					table.insert(result, n)
				end
				last_token = nil
			end
		end
	end

	return result
end
function M.walk_fraction(node, buf)
	local result = { { kind = "funexp", sym = "frac" } }
	local parts = {}

	for child in node:iter_children() do
		if child:named() and child:type() ~= "/" then
			local nodes = walk_node(child, buf)
			table.insert(parts, nodes)
		end
	end

	table.insert(result, { kind = "explist", exps = parts[1] or {} })
	table.insert(result, { kind = "explist", exps = parts[2] or {} })
	return result
end

function M.walk_call(node, buf)
	local result = {}
	local func_name = nil
	local args = {}
	local separators = {}

	for child in node:iter_children() do
		if child:named() then
			if child:type() == "ident" then
				func_name = get_text(child, buf)
			elseif child:type() == "field" then
				local raw = get_text(child, buf)
				func_name = field_map[raw] or raw
			elseif child:type() == "formula" then
				local arg_nodes = M.walk_formula(child, buf)
				table.insert(args, arg_nodes)
			end
		else
			local text = get_text(child, buf)
			if text == ";" then
				table.insert(separators, { type = "semicolon", pos = #args })
			elseif text == "," then
				table.insert(separators, { type = "comma", pos = #args })
			end
		end
	end

	local mapped = ident_map[func_name] or func_name

	if func_name == "op" and #args > 0 then
		local str = extract_string(args[1])
		if str then
			table.insert(result, { kind = "symexp", sym = str })
		end
		return result
	end

	if func_name == "text" and #args > 0 then
		local str = extract_string(args[1])
		if str then
			table.insert(result, { kind = "symexp", sym = str })
		end
		return result
	end

	-- Doubled uppercase: QQ(omega) → mathbb(Q)(omega)
	if #func_name == 2 and func_name:match("^%u%u$") and func_name:sub(1, 1) == func_name:sub(2, 2) then
		local letter = func_name:sub(1, 1)
		table.insert(result, { kind = "funexp", sym = "mathbb" })
		table.insert(result, { kind = "explist", exps = { { kind = "symexp", sym = letter } } })
		local arg_exps = {}
		for _, arg in ipairs(args) do
			for _, n in ipairs(arg) do
				table.insert(arg_exps, n)
			end
		end
		if #arg_exps > 0 then
			table.insert(result, { kind = "parexp", exp = { kind = "explist", exps = arg_exps } })
		end
		return result
	end

	if func_name == "lr" then
		local arg_exps = {}
		for _, arg in ipairs(args) do
			for _, n in ipairs(arg) do
				table.insert(arg_exps, n)
			end
		end
		-- Detect delimiter pairs and wrap content
		if #arg_exps >= 3 then
			local first = arg_exps[1]
			local last = arg_exps[#arg_exps]
			local wrap_kind = nil
			if first.kind == "funexp" and last.kind == "funexp" then
				if first.sym == "langle" and last.sym == "rangle" then
					wrap_kind = "angexp"
				elseif first.sym == "(" and last.sym == ")" then
					wrap_kind = "parexp"
				elseif first.sym == "[" and last.sym == "]" then
					wrap_kind = "braexp"
				end
			end
			if wrap_kind then
				local inner = {}
				for i = 2, #arg_exps - 1 do
					table.insert(inner, arg_exps[i])
				end
				return { { kind = wrap_kind, exp = { kind = "explist", exps = inner } } }
			end
		end
		return arg_exps
	end

	if func_name == "mid" then
		local arg_exps = {}
		for _, arg in ipairs(args) do
			for _, n in ipairs(arg) do
				table.insert(arg_exps, n)
			end
		end
		return arg_exps
	end

	if block_fns[func_name] then
		return M.walk_block_call(func_name, args, separators, buf)
	end

	if func_name == "frac" then
		table.insert(result, { kind = "funexp", sym = "frac" })
		table.insert(result, { kind = "explist", exps = args[1] or {} })
		table.insert(result, { kind = "explist", exps = args[2] or {} })
		return result
	end
	if func_name == "root" then
		table.insert(result, { kind = "funexp", sym = "root" })
		if #args == 2 then
			table.insert(result, { kind = "explist", exps = args[1] })
			table.insert(result, { kind = "explist", exps = args[2] })
		else
			table.insert(result, { kind = "explist", exps = args[1] or {} })
		end
		return result
	end

	if consumes_args[mapped] then
		table.insert(result, { kind = "funexp", sym = mapped })
		local arg_exps = {}
		for _, arg in ipairs(args) do
			for _, n in ipairs(arg) do
				table.insert(arg_exps, n)
			end
		end
		table.insert(result, { kind = "explist", exps = arg_exps })
		return result
	end

	table.insert(result, { kind = "funexp", sym = mapped })
	local arg_exps = {}
	for _, arg in ipairs(args) do
		for _, n in ipairs(arg) do
			table.insert(arg_exps, n)
		end
	end
	if #arg_exps > 0 then
		table.insert(result, { kind = "parexp", exp = { kind = "explist", exps = arg_exps } })
	end
	return result
end

function M.walk_block_call(func_name, args, separators, buf)
	local result = {}
	local block_name = block_fns[func_name]
	local content_exps = {}

	if func_name == "binom" or func_name == "vec" or func_name == "cases" then
		-- Each positional argument is a separate row
		for i, arg in ipairs(args) do
			if i > 1 then
				table.insert(content_exps, { kind = "funexp", sym = "\\" })
			end
			for _, n in ipairs(arg) do
				table.insert(content_exps, n)
			end
		end
	else
		-- mat, cases: use comma/semicolon separators
		local sep_idx = 1
		for i, arg in ipairs(args) do
			for _, n in ipairs(arg) do
				table.insert(content_exps, n)
			end
			while sep_idx <= #separators and separators[sep_idx].pos == i do
				if separators[sep_idx].type == "comma" then
					table.insert(content_exps, { kind = "symexp", sym = "&" })
				elseif separators[sep_idx].type == "semicolon" then
					table.insert(content_exps, { kind = "funexp", sym = "\\" })
				end
				sep_idx = sep_idx + 1
			end
		end
	end

	table.insert(result, {
		kind = "blockexp",
		first = { kind = "explist", exps = { { kind = "symexp", sym = block_name } } },
		content = { kind = "explist", exps = content_exps },
	})
	-- Dummy explist to match LaTeX parser's trailing explist
	-- (to_ascii blockexp handler skips one element after blockexp)
	table.insert(result, { kind = "explist", exps = {} })

	return result
end

function M.walk_group(node, buf)
	local result = {}
	local open_delim = nil
	local close_delim = nil
	local inner = {}

	for child in node:iter_children() do
		if child:named() then
			if child:type() == "formula" then
				inner = M.walk_formula(child, buf)
			end
		else
			local text = get_text(child, buf)
			if text == "(" or text == "[" or text == "{" then
				open_delim = text
			elseif text == ")" or text == "]" or text == "}" then
				close_delim = text
			end
		end
	end

	if open_delim == "{" then
		table.insert(result, { kind = "funexp", sym = "{" })
		for _, n in ipairs(inner) do
			table.insert(result, n)
		end
		table.insert(result, { kind = "funexp", sym = "}" })
	elseif open_delim == "[" then
		table.insert(result, { kind = "braexp", exp = { kind = "explist", exps = inner } })
	else
		table.insert(result, { kind = "parexp", exp = { kind = "explist", exps = inner } })
	end

	return result
end

function M.walk_apply(node, buf)
	local result = {}
	local func_name = nil
	local inner = {}
	local open_delim = nil
	local close_delim = nil

	for child in node:iter_children() do
		if child:named() then
			if child:type() == "ident" or child:type() == "letter" then
				func_name = get_text(child, buf)
			elseif child:type() == "formula" then
				inner = M.walk_formula(child, buf)
			end
		else
			local text = get_text(child, buf)
			if text == "(" or text == "[" then
				open_delim = text
			elseif text == ")" or text == "]" then
				close_delim = text
			end
		end
	end

	if func_name then
		local mapped = ident_map[func_name]
		if mapped then
			table.insert(result, { kind = "funexp", sym = mapped })
		elseif #func_name == 2 and func_name:match("^%u%u$") and func_name:sub(1, 1) == func_name:sub(2, 2) then
			table.insert(result, { kind = "funexp", sym = "mathbb" })
			table.insert(result, { kind = "explist", exps = { { kind = "symexp", sym = func_name:sub(1, 1) } } })
		else
			table.insert(result, { kind = "symexp", sym = func_name })
		end
	end

	if open_delim == "[" then
		table.insert(result, { kind = "braexp", exp = { kind = "explist", exps = inner } })
	else
		table.insert(result, { kind = "parexp", exp = { kind = "explist", exps = inner } })
	end
	return result
end

function M.parse_math_node(math_node, buf)
	for child in math_node:iter_children() do
		if child:named() and child:type() == "formula" then
			local nodes = M.walk_formula(child, buf)
			return { kind = "explist", exps = nodes, lnum = 1 }
		end
	end
	return { kind = "explist", exps = {}, lnum = 1 }
end

return M
