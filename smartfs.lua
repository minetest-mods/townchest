---------------------------
-- SmartFS: Smart Formspecs
-- License: CC0 or WTFPL
--    by Rubenwardy
---------------------------


-- namespace definition allow the usage of mod implementation in different versions by different mods
-- If the file is loaded directly from an other mod, the namespace is not "smartfs.{}" but "othermod.smartfs.{}" in this case
local currentmod = minetest.get_current_modname() -- mod the file was loaded from
local envroot = nil

if not currentmod or --not minetest or something hacky
       currentmod == "smartfs" then      -- or loaded trough smartfs mod
	envroot = _G                         -- populate global
else
	if not rawget(_G,currentmod) then
		_G[currentmod] = {}
	end
	envroot = _G[currentmod]
end


------------------------------------------------------
-- smarfs root object
------------------------------------------------------
envroot.smartfs = {
	_fdef = {},
	_edef = {},
	opened = {},
	inv = {}
}
local smartfs = envroot.smartfs --valid in this file. If the smartfs framework will be splitted to multiple files we need a framework to get envroot in sync

-- the smartfs() function
function smartfs.__call(self, name)
	return smartfs._fdef[name]
end


------------------------------------------------------
-- Smartfs Interface - Creating a form definition
------------------------------------------------------
-- Register forms and elements
function smartfs.create(name, onload)
	if smartfs._fdef[name] then
		error("SmartFS - (Error) Form "..name.." already exists!")
	end
	if smartfs.loaded and not smartfs._loaded_override then
		error("SmartFS - (Error) Forms should be declared while the game loads.")
	end

	smartfs._fdef[name] = {
		_reg = onload,
		name = name,
		show = smartfs._show_,
		attach_nodemeta = smartfs._attach_nodemeta_
	}

	return smartfs._fdef[name]
end


------------------------------------------------------
-- Smartfs Interface - Override load checks for dynamic forms
------------------------------------------------------
function smartfs.override_load_checks()
	smartfs._loaded_override = true
end


------------------------------------------------------
-- Smartfs Interface - Creating a dynamic form definition
------------------------------------------------------
function smartfs.dynamic(name,player)
	if not smartfs._dynamic_warned then
		smartfs._dynamic_warned = true
		print("SmartFS - (Warning) On the fly forms are being used. May cause bad things to happen")
	end

	local state = smartfs._makeState_({name=name},player,nil,false)
	state.show = state._show_
	smartfs.opened[player] = state
	return state
end

------------------------------------------------------
-- Smartfs Interface - Creating a element definition (private)
------------------------------------------------------
function smartfs.element(name,data)
	if smartfs._edef[name] then
		error("SmartFS - (Error) Element type "..name.." already exists!")
	end
	smartfs._edef[name] = data
	return smartfs._edef[name]
end

------------------------------------------------------
-- Smartfs Interface - Inventory helpers - check inventory type
------------------------------------------------------
function smartfs.inventory_mod()
	if unified_inventory then
		return "unified_inventory"
	elseif inventory_plus then
		return "inventory_plus"
	else
		return nil
	end
end

------------------------------------------------------
-- Smartfs Interface - Attach form to inventory (as plugin)
------------------------------------------------------
function smartfs.add_to_inventory(form,icon,title)
	if unified_inventory then
		unified_inventory.register_button(form.name, {
			type = "image",
			image = icon,
		})
		unified_inventory.register_page(form.name, {
			get_formspec = function(player, formspec)
				local name = player:get_player_name()
				local opened = smartfs._show_(form, name, nil, true)
				return {formspec = opened:_getFS_(false)}
			end
		})
		return true
	elseif inventory_plus then
		minetest.register_on_joinplayer(function(player)
			inventory_plus.register_button(player, form.name, title)
		end)
		minetest.register_on_player_receive_fields(function(player, formname, fields)
			if formname == "" and fields[form.name] then
				local name = player:get_player_name()
				local opened = smartfs._show_(form, name, nil, true)
				inventory_plus.set_inventory_formspec(player, opened:_getFS_(true))
			end
		end)
		return true
	else
		return false
	end
end

------------------------------------------------------
-- Form Interface [linked to form:show()] - Attach form to a player directly
------------------------------------------------------
function smartfs._show_(form, name, params, is_inv)
	local state = smartfs._makeState_(form, name, params, is_inv)
	state.show = state._show_
	if form._reg(state)~=false then
		if not is_inv then
			smartfs.opened[name] = state
			state:_show_()
		else
			smartfs.inv[name] = state
		end
	end
	return state
end

------------------------------------------------------
-- Form Interface [linked to form:show()] - Attach form to node meta
------------------------------------------------------
function smartfs._attach_nodemeta_(form, nodepos, placer, params)
	local state = smartfs._makeState_(form, nil, params, nil, nodepos) --no attached user, no params, no inventory integration
	if form._reg(state) then
		state:_show_()
	end
	return state
end


------------------------------------------------------
-- Minetest Interface - Receive data from player in case of nodemeta attachment (to be used in minetest.register_node methods)
------------------------------------------------------
function smartfs.nodemeta_on_receive_fields(nodepos, formname, fields, sender, params)
	-- get form info and check if it's a smartfs one
	local meta = minetest.get_meta(nodepos)
	local nodeform = meta:get_string("smartfs_name")
	if not nodeform then -- execute only if it is smartfs form
		print("SmartFS - (Warning) smartfs.nodemeta_on_receive_fields for node without smarfs data")
		return false
	end

	-- get the currentsmartfs state
	local opened_id = minetest.pos_to_string(nodepos)
	local state
	local form = smartfs:__call(nodeform)
	if not smartfs.opened[opened_id] or      --if opened first time
	       smartfs.opened[opened_id].def.name ~= nodeform then --or form is changed
		state = smartfs._makeState_(form, nil, params, nil, nodepos)
		smartfs.opened[opened_id] = state
		form._reg(state)
	else
		state = smartfs.opened[opened_id]
	end

	-- Set current sender check for multiple users on node
	local name = sender:get_player_name()
	state.players:connect(name)

	-- take the input
	state:_sfs_recieve_(name, fields)

	--update formspec on node to a initial one for the next usage
	if not state.players:get_first() then
		state._ele = {} --reset the form
		if form._reg(state) then --regen the form
			state:_show_() --write form to node
		end
		smartfs.opened[opened_id] = nil -- remove the old state
	end
end

------------------------------------------------------
-- Minetest Interface - Receive data from player in case of inventory or player
------------------------------------------------------
minetest.register_on_player_receive_fields(function(player, formname, fields)
	local name = player:get_player_name()
	if smartfs.opened[name] and smartfs.opened[name].location.type == "player" then
		if smartfs.opened[name].def.name == formname then
			local state = smartfs.opened[name]
			return state:_sfs_recieve_(name,fields)
		else
			smartfs.opened[name] = nil
		end
	elseif smartfs.inv[name] and smartfs.inv[name].location.type == "inventory" then
		local state = smartfs.inv[name]
		state:_sfs_recieve_(name,fields)
	end
	return false
end)

------------------------------------------------------
-- Minetest Interface - Notify loading of smartfs is done
------------------------------------------------------
minetest.after(0, function()
	smartfs.loaded = true
end)

------------------------------------------------------
-- Smartfs Framework - create a form object (state)
------------------------------------------------------
function smartfs._makeState_(form, newplayer, params, is_inv, nodepos)

	------------------------------------------------------
	-- State - players handler
	------------------------------------------------------
	-- Create object for monitoring of connected players. If no one connected the state can be free'd
	local function _make_players_(form, newplayer)
		local self = {}
		self._list = {} -- players list

		function self.connect(self, player)
			self._list[player] = player
		end

		function self.disconnect(self, player)
			self._list[player] = nil
		end

		function self.get_first(self) --to check if any connected
			return next(self._list)
		end
		if newplayer then
			self:connect(newplayer)
		end
		return self
	end

	------------------------------------------------------
	-- State - location handler
	------------------------------------------------------
	-- create object to handle formspec location
	local function _make_location_(form, newplayer, params, is_inv, nodepos)
		local self = {}
		self.rootState = self --by default. overriden in case of view
		if form.root and form.root.location then --the parent "form" is a state
			self.type = "view"
			self.viewElement = form -- form contains the element trough parent view element or form
			self.parentState = form.root
			if self.parentState.location.type == "view" then
				self.rootState = self.parentState.location.rootState
			else
				self.rootState = self.parentState
			end
		elseif nodepos then
			self.type = "nodemeta"
			self.pos = nodepos
		elseif newplayer then
			if is_inv then
				self.type = "inventory"
			else
				self.type = "player"
			end
			self.player = newplayer
		end
		return self
	end


	------------------------------------------------------
	-- State - create the state instance
	------------------------------------------------------
	return {
		------------------------------------------------------
		-- State - root window state interface. Not used/supportted in views
		------------------------------------------------------
		players = _make_players_(form, newplayer),
		is_inv = is_inv,    -- obsolete. Please use location.type=="inventory" instead
		player = newplayer, -- obsolete. Please use location.player:get_player_name()
		close = function(self)
			self.closed = true
		end,
		_show_ = function(self)
			if self.location.type == "inventory" then
				if unified_inventory then
					unified_inventory.set_inventory_formspec(minetest.get_player_by_name(self.location.player), self.def.name)
				elseif inventory_plus then
					inventory_plus.set_inventory_formspec(minetest.get_player_by_name(self.location.player), self:_getFS_(true))
				end
			elseif self.location.type == "player" then
				local res = self:_getFS_(true)
				minetest.show_formspec(self.location.player, form.name, res)
			elseif self.location.type == "nodemeta" then
				local meta = minetest.get_meta(self.location.pos)
				local res = self:_getFS_(true)
				meta:set_string("formspec", res)
				meta:set_string("smartfs_name", self.def.name)
			end
		end,

		------------------------------------------------------
		-- State - window and view interface
		------------------------------------------------------
		_ele = {},  -- window or view elements
		def = form, -- in case of views there is the parent state
		location = _make_location_(form, newplayer, params, is_inv, nodepos),
		param = params or {},
		get = function(self,name)
			return self._ele[name]
		end,
		_getFS_ = function(self,size)
			local res = ""
			if self._size and size then
				res = "size["..self._size.w..","..self._size.h.."]"
			end
			for key,val in pairs(self._ele) do
				if not val:getIsHiddenOrCutted() == true then
					res = res .. val:build()
				end
			end
			return res
		end,
		_sfs_recieve_field_ = function(self, field, value) -- process each single received field
			local cur_namespace = self:getNamespace()
			if cur_namespace == "" or cur_namespace == string.sub(field, 1, string.len(cur_namespace)) then -- Check current namespace
				local rel_fieldname = string.sub(field, string.len(cur_namespace)+1)  --cut the namespace
				if self._ele[rel_fieldname] then -- direct top-level assignment
					self._ele[rel_fieldname].data.value = value
				else
					for elename, eledef in pairs(self._ele) do
						if eledef.getViewState then -- element supports sub-states
							eledef:getViewState():_sfs_recieve_field_(field, value)
						end
					end
				end
			end
		end,
		_sfs_recieve_action_ = function(self, field, value, player)
			local cur_namespace = self:getNamespace()
			if cur_namespace == "" or cur_namespace == string.sub(field, 1, string.len(cur_namespace)) then -- Check current namespace
				local rel_fieldname = string.sub(field, string.len(cur_namespace)+1) --cut the namespace
				if self._ele[rel_fieldname] then -- direct top-level assignment
					if self._ele[rel_fieldname].submit then
						self._ele[rel_fieldname]:submit(value, player)
					end
				else
					for elename, eledef in pairs(self._ele) do
						if eledef.getViewState then -- element supports sub-states
						eledef:getViewState():_sfs_recieve_action_(field, value, player)
						end
					end
				end
			end
		end,
		_sfs_process_oninput_ = function(self, fields, player) --process hooks
			-- call onInput hook if enabled
			if self._onInput then
				self:_onInput(fields, player)
			end
			-- recursive all all onInput hooks on visible views
			for elename, eledef in pairs(self._ele) do
				if eledef.getViewState and not eledef:getIsHidden() then
					eledef:getViewState():_sfs_process_oninput_(fields, player)
				end
			end
		end,
		-- Receive fields and actions from formspec
		_sfs_recieve_ = function(self, player, fields)

			-- fields assignment
			for field,value in pairs(fields) do
				self:_sfs_recieve_field_(field, value)
			end
			-- do actions
			for field,value in pairs(fields) do
				self:_sfs_recieve_action_(field, value, player)
			end
			-- process onInput hooks
			self:_sfs_process_oninput_(fields, player)

			if not fields.quit and not self.closed then
				self:_show_()
			else -- to be closed
				self.players:disconnect(player)
				if self.location.type == "player" then
					smartfs.opened[player] = nil
				end
				if not fields.quit and self.closed then
					--closed by application (without fields.quit). currently not supported, see: https://github.com/minetest/minetest/pull/4675
					minetest.show_formspec(player,"","size[5,1]label[0,0;Formspec closing not yet created!]")
				end
			end
			return true
		end,
		onInput = function(self, func) -- on Input hook, called before input processing
			self._onInput = func       -- state:onInput(fields, player)
		end,
		load = function(self,file)
			local file = io.open(file, "r")
			if file then
				local table = minetest.deserialize(file:read("*all"))
				if type(table) == "table" then
					if table.size then
						self._size = table.size
					end
					for key,val in pairs(table.ele) do
						self:element(val.type,val)
					end
					return true
				end
			end
			return false
		end,
		save = function(self,file)
			local res = {ele={}}

			if self._size then
				res.size = self._size
			end

			for key,val in pairs(self._ele) do
				res.ele[key] = val.data
			end

			local file = io.open(file, "w")
			if file then
				file:write(minetest.serialize(res))
				file:close()
				return true
			end
			return false
		end,
		getSize = function(self)
			return self._size
		end,
		size = function(self, w,h) --same as setSize
			self._size = {w=w,h=h}
		end,
		setSize = function(self,w,h)
			self._size = {w=w,h=h}
		end,
		getNamespace = function(self)
			local ref = self
			local namespace = ""
			while ref.location.type == "view" do
				namespace = ref.location.viewElement.name.."#"..namespace
				ref = ref.location.parentState -- step near to the root
			end
			return namespace
		end,
		setparam = function(self,key,value) --set parameter relative (default)
			if not key then return end
			self.param[key] = value
			return true
		end,
		getparam = function(self,key,default)  --get parameter relative (default)
			if not key then return end
			return self.param[key] or default
		end,
		loadTemplate = function(self, template)
			-- template can be a function (usable in smartfs.create()), a form name or object ( a smartfs.create() result)
			if type(template) == "function" then -- asume it is a smartfs.create() usable function
				return template(self)
			elseif type(template) == "string" then -- asume it is a form name
				return smartfs.__call(self, template)._reg(self)
			elseif type(template) == "table" then --asume it is an other state
				if template._reg then
					template._reg(self)
				end
			end
		end,

		------------------------------------------------------
		-- State - elements creation wrappers
		------------------------------------------------------
		button = function(self,x,y,w,h,name,text,exitf)
			if exitf == nil then exitf = false end
			return self:element("button",{pos={x=x,y=y},size={w=w,h=h},name=name,value=text,closes=exitf})
		end,
		label = function(self,x,y,name,text)
			return self:element("label",{pos={x=x,y=y},name=name,value=text})
		end,
		toggle = function(self,x,y,w,h,name,list)
			return self:element("toggle",{pos={x=x,y=y},size={w=w,h=h},name=name,id=1,list=list})
		end,
		field = function(self,x,y,w,h,name,label)
			return self:element("field",{pos={x=x,y=y},size={w=w,h=h},name=name,value="",label=label})
		end,
		pwdfield = function(self,x,y,w,h,name,label)
			local res = self:element("field",{pos={x=x,y=y},size={w=w,h=h},name=name,value="",label=label})
			res:isPassword(true)
			return res
		end,
		textarea = function(self,x,y,w,h,name,label)
			local res = self:element("field",{pos={x=x,y=y},size={w=w,h=h},name=name,value="",label=label})
			res:isMultiline(true)
			return res
		end,
		image = function(self,x,y,w,h,name,img)
			return self:element("image",{pos={x=x,y=y},size={w=w,h=h},name=name,value=img})
		end,
		checkbox = function(self,x,y,name,label,selected)
			return self:element("checkbox",{pos={x=x,y=y},name=name,value=selected,label=label})
		end,
		listbox = function(self,x,y,w,h,name,selected,transparent)
			return self:element("list", { pos={x=x,y=y}, size={w=w,h=h}, name=name, selected=selected, transparent=transparent })
		end,
		inventory = function(self,x,y,w,h,name)
			return self:element("inventory", { pos={x=x,y=y}, size={w=w,h=h}, name=name })
		end,
		view = function(self,x,y, name)
			return self:element("view", { pos={x=x,y=y}, name=name })
		end,

		------------------------------------------------------
		-- Element instance creatior as state method
		------------------------------------------------------
		element = function(self, typen, data)
			local type = smartfs._edef[typen]

			if not type then
				error("Element type "..typen.." does not exist!")
			end

			if self._ele[data.name] then
				error("Element "..data.name.." already exists")
			end
			data.type = typen

			------------------------------------------------------
			-- Element instance template / abstract
			------------------------------------------------------
			local ele = {
				name = data.name,
				root = self,
				data = data,
				remove = function(self)
					self.root._ele[self.name] = nil
				end,
				setPosition = function(self,x,y)
					self.data.pos = {x=x,y=y}
				end,
				getPosition = function(self)
					return self.data.pos
				end,
				getAbsolutePosition = function(self)
				    if not self.root.location.type then
						print("SmartFS - (ERROR): self.root.location.type missed:", dump(self))
						break_execution_bug() --stop
					end
					if self.root.location.type == "view" then --it is a view. Calculate delta
						local relapos = self:getPosition()
						local viewpos = self.root.location.viewElement:getAbsolutePosition()
						local abspos = {}
						abspos.x = viewpos.x + relapos.x
						abspos.y = viewpos.y + relapos.y
						return abspos
					else
						return self:getPosition() --get current
					end
				end,
				setSize = function(self,w,h)  --not supported at all elements
					self.data.size = {w=w,h=h}
				end,
				getSize = function(self)
					return self.data.size
				end,
				getCuttedSize = function(self)
					local allowed_overlap = 0.5
					local elementsize = self:getSize()
					if not elementsize then
						return nil
					end
					-- get parent view or window size
					local viewsize
					if self.root.location and self.root.location.type == "view" then
						viewsize = self.root.location.viewElement:getCuttedSize()  -- cute a view
					else
						viewsize = self.root:getSize() --root cannot be cuted
					end
					if not viewsize then --view full-cuted
						return nil
					end
					-- check for overlapping
					local pos_in_view = self:getPosition()
					local cutedsize = {}
					if viewsize.w - pos_in_view.x + allowed_overlap < 0 then
						print("SmartFS - (Warning): element "..self.name.." outside of view:"..viewsize.w.." x:"..pos_in_view.x)
						return nil
					elseif viewsize.w - pos_in_view.x + allowed_overlap <  elementsize.w then
						print("SmartFS - (Warning): element "..self.name.." cuted. view width:"..viewsize.w.." x:"..pos_in_view.x.." element width:"..elementsize.w)
						cutedsize.w = viewsize.w - pos_in_view.x + allowed_overlap
					else
						cutedsize.w = elementsize.w
					end
					if viewsize.h - pos_in_view.y + allowed_overlap < 0 then
						print("SmartFS - (Warning): element "..self.name.." outside of view:"..viewsize.h.." y:"..pos_in_view.y)
						return nil
					elseif viewsize.h - pos_in_view.y + allowed_overlap < elementsize.h then
						print("SmartFS - (Warning): element "..self.name.." cuted. view hight:"..viewsize.h.." y:"..pos_in_view.y.." element hight:"..elementsize.h)
						cutedsize.h = viewsize.h - pos_in_view.y  + allowed_overlap
					else
						cutedsize.h = elementsize.h
					end
					return cutedsize
				end,
				setIsHidden = function(self, hidden)
					self.data.hidden = hidden
				end,
				getIsHidden = function(self)
					return self.data.hidden
				end,
				getIsHiddenOrCutted = function(self)
					if not self:getCuttedSize() then
						print("SmartFS - (Warning): element: "..self.name.."is outside of view")
						return true
					else
						return self:getIsHidden()
					end
				end,
				getAbsName = function(self)
					return self.root:getNamespace()..self.name
				end,
				getPosString = function(self)
					local pos = self:getAbsolutePosition()
					return pos.x..","..pos.y
				end,
				getSizeString = function(self)
					local size = self:getCuttedSize()
					if not size then
						return ""
					end
					return size.w..","..size.h
				end,
				setBackground = function(self, image)
					self.data.background = image
				end,
				getBackground = function(self)
					return self.data.background
				end,
				getBackgroundString = function(self)
					if self.data.background then
						return "background["..
								self:getPosString()..";"..
								self:getSizeString()..";"..
								self.data.background.."]"
					else
						return ""
					end
				end,
			}

			------------------------------------------------------
			-- Element instance construction
			------------------------------------------------------
			if not ele.data.size then
				ele.data.size = {w=0.5,h=0.5} --dummy size for elements without size (label + checkbox)
			end

			for key,val in pairs(type) do
				ele[key] = val
			end

			self._ele[data.name] = ele

			return self._ele[data.name]
		end,
	}
end





-----------------------------------------------------------------
-------------------------  ELEMENTS  ----------------------------
-----------------------------------------------------------------
smartfs.element("button",{
	build = function(self)
		if self.data.img then
			return "image_button["..
				self:getPosString()..";"..
				self:getSizeString()..";"..
				self.data.img..";"..
				self:getAbsName()..";"..
				minetest.formspec_escape(self.data.value).."]"..
				self:getBackgroundString()
		else
			if self.data.closes then
				return "button_exit["..
					self:getPosString()..";"..
					self:getSizeString()..";"..
					self:getAbsName()..";"..
						minetest.formspec_escape(self.data.value).."]"..
						self:getBackgroundString()
			else
				return "button["..
					self:getPosString()..";"..
					self:getSizeString()..";"..
					self:getAbsName()..";"..
					minetest.formspec_escape(self.data.value).."]"..
					self:getBackgroundString()
			end
		end
	end,
	submit = function(self, field, player)
		if self._click then
			self:_click(self.root, player)
		end
		--[[ not needed. there is a quit field received in this case
		if self.data.closes then
			self.root.location.rootState:close()
		end
		]]--
	end,
	onClick = function(self,func)
		self._click = func
	end,
	click = function(self,func)
		self._click = func
	end,
	setText = function(self,text)
		self.data.value = text
	end,
	getText = function(self)
		return self.data.value
	end,
	setImage = function(self,image)
		self.data.img = image
	end,
	getImage = function(self)
		return self.data.img
	end,
	setClose = function(self,bool)
		self.data.closes = bool
	end
})

smartfs.element("toggle",{
	build = function(self)
		return "button["..
			self:getPosString()..";"..
			self:getSizeString()..";"..
			self:getAbsName()..";"..
			minetest.formspec_escape(self.data.list[self.data.id]).."]"..
			self:getBackgroundString()
	end,
	submit = function(self, field, player)
		self.data.id = self.data.id + 1
		if self.data.id > #self.data.list then
			self.data.id = 1
		end
		if self._tog then
			self:_tog(self.root, player)
		end
	end,
	onToggle = function(self,func)
		self._tog = func
	end,
	setId = function(self,id)
		self.data.id = id
	end,
	getId = function(self)
		return self.data.id
	end,
	getText = function(self)
		return self.data.list[self.data.id]
	end
})

smartfs.element("label",{
	build = function(self)
		return "label["..
			self:getPosString()..";"..
			minetest.formspec_escape(self.data.value).."]"..
			self:getBackgroundString()
	end,
	setText = function(self,text)
		self.data.value = text
	end,
	getText = function(self)
		return self.data.value
	end,
})

smartfs.element("field",{
	build = function(self)
		if self.data.ml then
			return "textarea["..
				self:getPosString()..";"..
				self:getSizeString()..";"..
				self:getAbsName()..";"..
				minetest.formspec_escape(self.data.label)..";"..
				minetest.formspec_escape(self.data.value).."]"..
				self:getBackgroundString()
		elseif self.data.pwd then
			return "pwdfield["..
				self:getPosString()..";"..
				self:getSizeString()..";"..
				self:getAbsName()..";"..
				minetest.formspec_escape(self.data.label).."]"..
				self:getBackgroundString()
		else
			return "field["..
				self:getPosString()..";"..
				self:getSizeString()..";"..
				self:getAbsName()..";"..
				minetest.formspec_escape(self.data.label)..";"..
				minetest.formspec_escape(self.data.value).."]"..
				self:getBackgroundString()
		end
	end,
	setText = function(self,text)
		self.data.value = text
	end,
	getText = function(self)
		return self.data.value
	end,
	isPassword = function(self,bool)
		self.data.pwd = bool
	end,
	isMultiline = function(self,bool)
		self.data.ml = bool
	end
})

smartfs.element("image",{
	build = function(self)
		return "image["..
			self:getPosString()..";"..
			self:getSizeString()..";"..
			self.data.value.."]"
	end,
	setImage = function(self,text)
		self.data.value = text
	end,
	getImage = function(self)
		return self.data.value
	end
})

smartfs.element("checkbox",{
	build = function(self)
		if self.data.value == true then
			self.data.value = "true"
		elseif self.data.value ~= "true" then
			self.data.value = "false"
		end
		return "checkbox["..
			self:getPosString()..";"..
			self:getAbsName()..";"..
			minetest.formspec_escape(self.data.label)..";"..
			self.data.value.."]"..
			self:getBackgroundString()
	end,
	submit = function(self, field, player)
		-- self.data.value already set by value transfer
		-- call the toggle function if defined
		if self._tog then
			self:_tog(self.root, player)
		end
	end,
	setValue = function(self,text)  --true and false
		self.data.value = text
	end,
	getValue = function(self)
		return self.data.value
	end,
	onToggle = function(self,func)
		self._tog = func
	end,
})

smartfs.element("list",{
	build = function(self)
		if not self.data.items then
			self.data.items = {}
		end
		return "textlist["..
			self:getPosString()..";"..
			self:getSizeString()..";"..
			self:getAbsName()..";"..
			table.concat(self.data.items, ",")..";"..
			tostring(self.data.selected or "")..";"..
			tostring(self.data.transparent or "false").."]"..
			self:getBackgroundString()
	end,
	submit = function(self, field, player)
		local _type = string.sub(field,1,3)
		local index = string.sub(field,5)
		self.data.selected = index
		if _type == "CHG" and self._click then
			self:_click(self.root, index, player)
		elseif _type == "DCL" and self._doubleClick then
			self:_doubleClick(self.root, index, player)
		end
	end,
	onClick = function(self, func)
		self._click = func
	end,
	click = function(self, func)
		self._click = func
	end,
	onDoubleClick = function(self, func)
		self._doubleClick = func
	end,
	doubleclick = function(self, func)
		self._doubleClick = func
	end,
	addItem = function(self, item)
		if not self.data.items then
			self.data.items = {}
		end
		table.insert(self.data.items, item)
	end,
	removeItem = function(self,idx)
		if not self.data.items then
			self.data.items = {}
		end
		table.remove(self.data.items,idx)
	end,
	getItem = function(self,idx)
		if not self.data.items then
			self.data.items = {}
		end
		if idx then
			return self.data.items[tonumber(idx)]
		else
			return nil
		end
	end,
	clearItems = function(self)
		self.data.items = {}
	end,
	popItem = function(self)
		if not self.data.items then
			self.data.items = {}
		end
		local item = self.data.items[#self.data.items]
		table.remove(self.data.items)
		return item
	end,
	setSelected = function(self,idx)
		self.data.selected = idx
	end,
	getSelected = function(self)
		return self.data.selected
	end,
	getSelectedItem = function(self)
		return self:getItem(self:getSelected())
	end,
})

smartfs.element("inventory",{
	build = function(self)
		return "list["..
			(self.data.location or "current_player") ..";"..
			self.name..";"..   --no namespacing
			self:getPosString()..";"..
			self:getSizeString()..";"..
			(self.data.index or "").."]"..
			self:getBackgroundString()
	end,
	-- available inventory locations
	-- "current_player": Player to whom the menu is shown
	-- "player:<name>": Any player
	-- "nodemeta:<X>,<Y>,<Z>": Any node metadata
	-- "detached:<name>": A detached inventory
	-- "context" does not apply to smartfs, since there is no node-metadata as context available
	setLocation = function(self,location)
		self.data.location = location
	end,
	getLocation = function(self)
		return self.data.location or "current_player"
	end,
	usePosition = function(self, pos)
		self.data.location = string.format("nodemeta:%d,%d,%d", pos.x, pos.y, pos.z)
	end,
	usePlayer = function(self, name)
		self.data.location = "player:" .. name
	end,
	useDetached = function(self, name)
		self.data.location = "detached:" .. name
	end,
	setIndex = function(self,index)
		self.data.index = index
	end,
	getIndex = function(self)
		return self.data.index
	end
})

smartfs.element("code",{
	build = function(self)
		if self._build then
			self:_build()
		end
		return self.data.code
	end,
	submit = function(self, field, player)
		if self._sub then
			self:_sub(self.root, field, player)
		end
	end,
	onSubmit = function(self,func)
		self._sub = func
	end,
	onBuild = function(self,func)
		self._build = func
	end,
	setCode = function(self,code)
		self.data.code = code
	end,
	getCode = function(self)
		return self.data.code
	end
})

smartfs.element("view",{
	-- redefinitions. The size is not handled by data.size but by view-state:size
	setSize = function(self,w,h)
		self:getViewState():setSize(w,h)
	end,
	getSize = function(self)
		return self:getViewState():getSize()
	end,
	-- element interface methods
	build = function(self)
		if not self:getIsHiddenOrCutted() == true then
			return self:getViewState():_getFS_(false)..self:getBackgroundString()
		else
			print("SmartFS - (Warning): view outside or hidden")
			return ""
		end
	end,
	getViewState = function(self)
		if not self._state then
			self._state = smartfs._makeState_(self, nil, self.root.param)
		end
		return self._state
	end
	-- submit is handled by framework for elements with getViewState
})
