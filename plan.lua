local dprint = townchest.dprint --debug

local __add_node = function(this,node)
	-- add to the full list

	this.building_full[node:id()] = node        --collect references for direct access
	this.building_size = this.building_size + 1
end


local __adjust_flatting_requrement = function(this,node)
	-- create relative sizing information
	if not this.relative.min_x or this.relative.min_x > node.x then
		this.relative.min_x = node.x
	end
	if not this.relative.max_x or this.relative.max_x < node.x then
		this.relative.max_x = node.x
	end
	if not this.relative.min_y or this.relative.min_y > node.y then
		this.relative.min_y = node.y
	end
	if not this.relative.max_y or this.relative.max_y < node.y then
		this.relative.max_y = node.y
	end
	if not this.relative.min_z or this.relative.min_z > node.z then
		this.relative.min_z = node.z
	end
	if not this.relative.max_z or this.relative.max_z < node.z then
		this.relative.max_z = node.z
	end

	-- create ground level information
	if string.sub(node.name, 1, 18) == "default:dirt_with_" or
	   node.name == "farming:soil_wet" then
		if not this.relative.groundnode_count then
			this.relative.groundnode_count = 1
			this.relative.ground_y = node.y + 1
		else
			this.relative.groundnode_count = this.relative.groundnode_count + 1
			this.relative.ground_y = this.relative.ground_y + (node.y + 1 - this.relative.ground_y) / this.relative.groundnode_count 
			dprint("ground calc:", node.name, this.relative.groundnode_count, node.y, this.relative.ground_y)
		end
	end
end


local __prepare = function(this)
-- round ground level to full block
	this.relative.ground_y =  math.floor(this.relative.ground_y)
	local additional = 0
	local add_max = 5
	
	dprint("create flatting plan")
	for y = this.relative.min_y, this.relative.max_y + 5 do -- with additional 5 on top
		--calculate additional grounding
		if y >= this.relative.ground_y then --only over ground
			local high = y-this.relative.ground_y
			additional = high+1
			if additional > add_max then --set to max
				additional = add_max
			end
			dprint("additional flat", y, additional)
		end
		for x = this.relative.min_x - additional, this.relative.max_x + additional do
			for z = this.relative.min_z - additional, this.relative.max_z + additional do
				if not this.building_full[x..","..y..","..z] then -- not in plan - flat them
					local node = townchest.nodes.new({ x=x, y=y, z=z, name="air", matname = townchest.nodes.c_free_item })
					this:add_node(node)
				end
			end
		end
	end
	dprint("flatting plan done")
	
end


local __get_world_pos = function(this,pos)
	local fpos = {	x=pos.x+this.chest.pos.x,
					y=pos.y+this.chest.pos.y - this.relative.ground_y,
					z=pos.z+this.chest.pos.z
				}
--	dprint("world_pos y:"..pos.y.."+"..this.chest.pos.y.."-"..this.relative.ground_y) 
	return fpos
end
-- revert get_world_pos
local __get_plan_pos = function(this,pos)
	local fpos = {	x=pos.x-this.chest.pos.x,
					y=pos.y-this.chest.pos.y + this.relative.ground_y,
					z=pos.z-this.chest.pos.z
				}
--	dprint("plan_pos y:"..pos.y.."-"..this.chest.pos.y.."+"..this.relative.ground_y) 
	return fpos
end


local __get_nodes = function(this, count, skip)
	local ret = {}
	local counter = 0
	if not skip then
		skip = 0
	end
	
	for key, node in pairs(this.building_full) do
		counter = counter + 1
		if counter > skip then
			table.insert(ret, node)
		end
		if counter >= count + skip then
			break
		end	
	end
	return ret
end

-- to be able working with forceload chunks
local __get_nodes_from_chunk = function(this, node)

-- calculate the begin of the chunk
	--local BLOCKSIZE = core.MAP_BLOCKSIZE
	local BLOCKSIZE = 16
	
	local wpos = this:get_world_pos(node)
	wpos.x = (math.floor(wpos.x/BLOCKSIZE))*BLOCKSIZE
	wpos.y = (math.floor(wpos.y/BLOCKSIZE))*BLOCKSIZE
	wpos.z = (math.floor(wpos.z/BLOCKSIZE))*BLOCKSIZE

	dprint("nodes for chunk (wpos)", wpos.x, wpos.y, wpos.z)
	local vpos = this:get_plan_pos(wpos)
	dprint("nodes for chunk (vpos)", vpos.x, vpos.y, vpos.z)
	
	local ret = {}
	for x = vpos.x, vpos.x + BLOCKSIZE do
		for y = vpos.y, vpos.y + BLOCKSIZE do
			for z = vpos.z, vpos.z + BLOCKSIZE do
				--local node = this.building_full[node:id()]
				local node = this.building_full[x..","..y..","..z]
				if node then
					table.insert(ret, node)
				end
			end
		end
	end

	return ret
end

local __set_node_processed = function(this, node)
	this.building_full[node:id()] = nil
	this.building_size = this.building_size - 1
end



townchest.plan = {}

townchest.plan.new = function( chest )
	local this = {}
	this.relative = {}  --relative infos
	this.relative.ground_y = 0

	this.chest = chest

	-- full plan - key-indexed - equvalent to the we-file
	this.building_full = {}
	this.building_size = 0

	this.add_node = __add_node
	this.adjust_flatting_requrement = __adjust_flatting_requrement
	this.prepare = __prepare
	this.get_world_pos = __get_world_pos
	this.get_plan_pos = __get_plan_pos
	this.get_nodes = __get_nodes
	this.set_node_processed = __set_node_processed
	this.get_nodes_from_chunk = __get_nodes_from_chunk
	return this
end
