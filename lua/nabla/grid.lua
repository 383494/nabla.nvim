local symbols = require('nabla.symbols')
local style = symbols.style

local utf8char
utf8char = function(str, i)
  if i >= vim.str_utfindex(str) or i < 0 then return nil end
  local s1 = vim.str_byteindex(str, i)
  local s2 = vim.str_byteindex(str, i+1)
  return string.sub(str, s1+1, s2)
end

local grid = {}
function grid:new(w, h, content, t)
	if not content and w and h and w > 0 and h > 0 then
		content = {}
		for y=1,h do
			local row = ""
			for x=1,w do
				row = row .. " "
			end
			table.insert(content, row)
		end
	end

	local o = { 
		w = w or 0, 
		h = h or 0, 
    t = t,
    children = {},
		content = content or {},
		my = 0, -- middle y (might not be h/2, for example fractions with big denominator, etc )

	}
	return setmetatable(o, { 
		__tostring = function(g)
			return table.concat(g.content, "\n")
		end,

		__index = grid,
	})
end

function grid:join_hori(g, top_align)
	local combined = {}

	local num_max = math.max(self.my, g.my)
	local den_max = math.max(self.h - self.my, g.h - g.my)

	local s1, s2
	if not top_align then
		s1 = num_max - self.my
		s2 = num_max - g.my
	else
		s1 = 0
		s2 = 0
	end

	local h 
	if not top_align then
		h = den_max + num_max
	else
		h = math.max(self.h, g.h)
	end


	for y=1,h do
		local r1 = self:get_row(y-s1)
		local r2 = g:get_row(y-s2)

		table.insert(combined, r1 .. r2)

	end

	local c = grid:new(self.w+g.w, h, combined)
	c.my = num_max

  table.insert(c.children, { self, 0, s1 })
  table.insert(c.children, { g, self.w, s2 })

	return c
end

function grid:get_row(y)
	if y < 1 or y > self.h then
		local s = ""
		for i=1,self.w do s = s .. " " end
		return s
	end
	return self.content[y]
end

function grid:join_vert(g, align_left)
	local w = math.max(self.w, g.w)
	local h = self.h+g.h
	local combined = {}

	local s1, s2
	if not align_left then
		s1 = math.floor((w-self.w)/2)
		s2 = math.floor((w-g.w)/2)
	else
		s1 = 0
		s2 = 0
	end

	for x=1,w do
		local c1 = self:get_col(x-s1)
		local c2 = g:get_col(x-s2)

		table.insert(combined, c1 .. c2)

	end

	local rows = {}
	for y=1,h do
		local row = ""
		for x=1,w do
			row = row .. utf8char(combined[x], y-1)
		end
		table.insert(rows, row)
	end

	local c = grid:new(w, h, rows)
  table.insert(c.children, { self, s1, 0 })
  table.insert(c.children, { g, s2, self.h })

  return c
end

function grid:get_col(x) 
	local s = ""
	if x < 1 or x > self.w then
		for i=1,self.h do s = s .. " " end
	else
		for y=1,self.h do
			s = s .. utf8char(self.content[y], x-1)
		end
	end
	return s
end

function grid:enclose_paren()
	local left_content = {}
	if self.h == 1 then
		left_content = { style.left_single_par }
	else
		for y=1,self.h do
			if y == 1 then table.insert(left_content, style.left_top_par)
			elseif y == self.h then table.insert(left_content, style.left_bottom_par)
			else table.insert(left_content, style.left_middle_par)
			end
		end
	end

	local left_paren = grid:new(1, self.h, left_content, "par")
	left_paren.my = self.my

	local right_content = {}
	if self.h == 1 then
		right_content = { style.right_single_par }
	else
		for y=1,self.h do
			if y == 1 then table.insert(right_content, style.right_top_par)
			elseif y == self.h then table.insert(right_content, style.right_bottom_par)
			else table.insert(right_content, style.right_middle_par)
			end
		end
	end

	local right_paren = grid:new(1, self.h, right_content, "par")
	right_paren.my = self.my


	local c1 = left_paren:join_hori(self)
	local c2 = c1:join_hori(right_paren)
	return c2
end

function grid:put_paren(exp, parent)
	if exp.priority() < parent.priority() then
		return self:enclose_paren()
	else
		return self
	end
end

function grid:join_super(superscript)
	local spacer = grid:new(self.w, superscript.h)


	local upper = spacer:join_hori(superscript, true)
	local result = upper:join_vert(self, true)
	result.my = self.my + superscript.h
	return result
end

function grid:combine_sub(other)
	local spacer = grid:new(self.w, other.h)




	local lower = spacer:join_hori(other)
	local result = self:join_vert(lower, true)
	result.my = self.my
	return result
end

function grid:join_sub_sup(sub, sup)
	local upper_spacer = grid:new(self.w, sup.h)
	local middle_spacer = grid:new(math.max(sub.w, sup.w), self.h)

	local right = sup:join_vert(middle_spacer, true)
	right = right:join_vert(sub, true)

	local left = upper_spacer:join_vert(self, true)
	local res = left:join_hori(right, true)
	res.my = self.my + sup.h
	return res
end

function grid:enclose_bracket()
	local left_content = {}
	if self.h == 1 then
		left_content = { style.left_single_bra }
	elseif self.h == 2 then
		left_content = { ' ', style.left_single_bra }
	else
		for y=1,self.h do
			if y == 1 then table.insert(left_content, style.left_top_bra)
			elseif y == self.h then table.insert(left_content, style.left_bottom_bra)
			elseif y == math.ceil(self.h/2) then table.insert(left_content, style.left_middle_bra)
	    else
	      table.insert(left_content, style.left_other_bra)
			end
		end
	end

	local left_bra = grid:new(1, self.h, left_content, "bra")
	left_bra.my = self.my

	local right_content = {}
	if self.h == 1 then
		right_content = { style.right_single_bra }
	elseif self.h == 2 then
		right_content = { ' ', style.right_single_bra }
	else
		for y=1,self.h do
			if y == 1 then table.insert(right_content, style.right_top_bra)
			elseif y == self.h then table.insert(right_content, style.right_bottom_bra)
			elseif y == math.ceil(self.h/2) then table.insert(right_content, style.right_middle_bra)
	    else
	      table.insert(right_content, style.right_other_bra)
			end
		end
	end

	local right_bra = grid:new(1, self.h, right_content, "bra")
	right_bra.my = self.my


	local c1 = left_bra:join_hori(self)
	local c2 = c1:join_hori(right_bra)
	return c2
end

function grid:enclose_left_bracket()
	local left_content = {}
	if self.h == 1 then
		left_content = { style.left_single_bra }
	elseif self.h == 2 then
		left_content = { style.left_top_bra, style.left_bottom_bra }
	else
		for y=1,self.h do
			if y == 1 then table.insert(left_content, style.left_top_bra)
			elseif y == self.h then table.insert(left_content, style.left_bottom_bra)
			elseif y == math.ceil(self.h/2) then table.insert(left_content, style.left_middle_bra)
			else table.insert(left_content, style.left_other_bra)
			end
		end
	end
	local left_bra = grid:new(1, self.h, left_content, "bra")
	left_bra.my = self.my
	return left_bra:join_hori(self)
end



function grid:enclose_angle()
	local left_content = {}
	if self.h == 1 then
		left_content = { "⟨" }
	else
		for y=1,self.h do
			if y == 1 then table.insert(left_content, "╱")
			elseif y == self.h then table.insert(left_content, "╲")
			else table.insert(left_content, "│")
			end
		end
	end
	local left_ang = grid:new(1, self.h, left_content, "ang")
	left_ang.my = self.my

	local right_content = {}
	if self.h == 1 then
		right_content = { "⟩" }
	else
		for y=1,self.h do
			if y == 1 then table.insert(right_content, "╲")
			elseif y == self.h then table.insert(right_content, "╱")
			else table.insert(right_content, "│")
			end
		end
	end
	local right_ang = grid:new(1, self.h, right_content, "ang")
	right_ang.my = self.my

	local c1 = left_ang:join_hori(self)
	local c2 = c1:join_hori(right_ang)
	return c2
end

return grid
