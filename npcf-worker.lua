local dprint = townchest.dprint_off --debug
--local dprint = townchest.dprint

local MAX_SPEED = 5
local BUILD_DISTANCE = 3
local HOME_RANGE = 10

townchest.npc = {}
function townchest.npc.spawn_nearly(pos, owner)
	local npcid = tostring(math.random(10000))
	npcf.index[npcid] = owner --owner
	local ref = {
		id = npcid,
		pos = {x=(pos.x+math.random(0,4)-4),y=(pos.y + 0.5),z=(pos.z+math.random(0,4)-4)},
		yaw = math.random(math.pi),
		name = "schemlib_builder_npcf:builder",
		owner = owner,
	}
	local npc = npcf:add_npc(ref)
	npcf:save(ref.id)
	if npc then
		npc:update()
	end
end

function townchest.npc.enable_build(plan)
	schemlib_builder_npcf.plan_manager:add(minetest.pos_to_string(plan.anchor_pos), plan)
end

function townchest.npc.disable_build(plan)
	schemlib_builder_npcf.plan_manager:set_finished(minetest.pos_to_string(plan.anchor_pos))
end

-- hook to trigger chest update each node placement
function townchest.npc.plan_update_hook(plan, status)
	if plan.chest then
		plan.chest:update_info("build_status")
		if status == "finished" then
			dprint("----Finished event called in npc hook----")
			plan.chest.info.npc_build = false
			plan.chest.info.instantbuild = false
			townchest.npc.disable_build(plan)
		end
		plan.chest:update_statistics()
	end
end

