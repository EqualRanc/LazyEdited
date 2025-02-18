require('chat')
require('logger')
require('tables')
config = require('config')
res = require('resources')
packets = require('packets')

_addon.name = 'lazy'
_addon.author = 'Brax'
_addon.version = '0.5'
_addon.commands = {'lazy'}

Start_Engine = true
isCasting = false
isBusy = 0
buffactive = {}
Action_Delay = 2

buffactive = {}

defaults = {}
defaults.spell = ""
defaults.spell_active = false
defaults.weaponskill = ""
defaults.weaponskill_active = false
defaults.ws_hp_threshold = 50
defaults.autotarget = false
defaults.target = {}

settings = config.load(defaults)

windower.register_event('incoming chunk', function(id, data)
    if id == 0x028 then
        local action_message = packets.parse('incoming', data)
		if action_message["Category"] == 4 then
			isCasting = false
		elseif action_message["Category"] == 8 then
			isCasting = true
			if action_message["Target 1 Action 1 Message"] == 0 then
				isCasting = false
				isBusy = Action_Delay
			end
		end
	end
end)

windower.register_event('outgoing chunk', function(id, data)
    if id == 0x015 then
        local action_message = packets.parse('outgoing', data)
		PlayerH = action_message["Rotation"]
	end
end)

windower.register_event('addon command', function (...)
	local args	= T{...}:map(string.lower)
	if args[1] == nil or args[1] == "help" then
		print("Help Info")
	elseif args[1] == "start" then
		windower.add_to_chat(2,"....Starting Lazy Helper....")
		Start_Engine = true
		Engine()
	elseif args[1] == "stop" then
		windower.add_to_chat(2,"....Stopping Lazy Helper....")
		Start_Engine = false
	elseif args[1] == "reload" then
		windower.add_to_chat(2,"....Reloading Config....")
		config.reload(settings)
	elseif args[1] == "save" then
		config.save(settings,windower.ffxi.get_player().name)
	elseif args[1] == "test" then
		test()
	elseif args[1] == "show" then
		windower.add_to_chat(11,"Autotarget: "..tostring(settings.autotarget))
		windower.add_to_chat(11,"Spell: "..settings.spell)
		windower.add_to_chat(11,"Use Spell "..tostring(settings.spell_active))
		windower.add_to_chat(11,"Weaponskill: "..settings.weaponskill)
		windower.add_to_chat(11,"Use Weaponskill: "..tostring(settings.weaponskill_active))
		windower.add_to_chat(11,"Target:"..settings.target)
	elseif args[1] == "autotarget" then
		if args[2] == "on" then
			settings.autotarget = true
			windower.add_to_chat(3,"Autotarget: True")
		else
			settings.autotarget = false
			windower.add_to_chat(3,"Autotarget: False")
		end
	elseif args[1] == "target" then
		if args[2] then  
        		table.insert(settings.target, args[2]) -- Add target to the list if it's not already there
        		windower.add_to_chat(3, "Target added: " .. args[2])
    	end
	elseif args[1] == "ws" then --Added section to change weaponskills and turn on/off
		if args[2] == nil then
			windower.add_to_chat(11,"Weaponskill: "..settings.weaponskill)
			windower.add_to_chat(11,"Use Weaponskill: "..tostring(settings.weaponskill_active))
		elseif args[2] == "on" then
			settings.weaponskill_active = true
		elseif args[2] == "off" then
			settings.weaponskill_active = false
		else
			settings.weaponskill = args[2]
			settings.weaponskill_active = true
			windower.add_to_chat(11,"Weaponskill: "..settings.weaponskill)
			windower.add_to_chat(11,"Use Weaponskill: "..tostring(settings.weaponskill_active))
		end
	end
	elseif args[1] == "ws_hp" then  -- Set the HP threshold for weaponskill usage
   		local hp_threshold = tonumber(args[2])
    	if hp_threshold and hp_threshold >= 1 and hp_threshold <= 100 then
        	settings.ws_hp_threshold = hp_threshold
        	windower.add_to_chat(11, "Weaponskill HP Threshold set to: " .. hp_threshold .. "%")
    	else
        	windower.add_to_chat(11, "Invalid HP threshold. Please enter a value between 1 and 100.")
		end
end)

function HeadingTo(X,Y)
	local X = X - windower.ffxi.get_mob_by_id(windower.ffxi.get_player().id).x
	local Y = Y - windower.ffxi.get_mob_by_id(windower.ffxi.get_player().id).y
	local H = math.atan2(X,Y)
	return H - 1.5708
end

function TurnToTarget()
	local destX = windower.ffxi.get_mob_by_target('t').x
	local destY = windower.ffxi.get_mob_by_target('t').y
	local direction = math.abs(PlayerH - math.deg(HeadingTo(destX,destY)))
	if direction > 10 then
		windower.ffxi.turn(HeadingTo(destX,destY))
	end
end

function Is_Targeting_Party(mob, party)
    for _, member in pairs(party) do
        if member and member.mob and mob.target_index == member.mob.index then
            return true
        end
    end
    return false
end

function Find_Nearest_Target()
    local target_id = -1
    local closest_distance = math.huge
    local marray = windower.ffxi.get_mob_array()
    local player = windower.ffxi.get_player()
    local party = windower.ffxi.get_party()
    
    -- Store enemies attacking us or party members
    local attackers = {}

    for _, mob in pairs(marray) do
        if mob.valid_target and mob.hpp > 0 and mob.status == 1 then  -- Only hostile mobs
            -- Check if mob is targeting the player or a party member
            if mob.target_index and (mob.target_index == player.index or Is_Targeting_Party(mob, party)) then
                table.insert(attackers, mob)
            end
        end
    end
    
    -- Find the closest attacker
    for _, mob in ipairs(attackers) do
        local distance = math.sqrt(mob.distance)
        if distance < closest_distance then
            target_id = mob.index
            closest_distance = distance
        end
    end

    return target_id
end

function Avoid_Obstacle(player, target)
    local directions = {math.pi / 2, -math.pi / 2} -- 90 degrees left and right
    local tried_directions = {}

    -- Try moving left or right
    for _, angle in ipairs(directions) do
        local new_heading = player.heading + angle
        if Try_New_Direction(player, new_heading) then
            return
        end
        table.insert(tried_directions, new_heading)
    end

    -- If left and right failed, try backing up slightly and retrying
    windower.ffxi.run(false) -- Stop first
    coroutine.schedule(function()
        windower.ffxi.run(-1) -- Move backward slightly
        coroutine.schedule(function()
            -- Retry moving forward after backing up
            local new_heading = player.heading
            if Try_New_Direction(player, new_heading) then
                return
            end
        end, 0.5)
    end, 0.5)

    windower.add_to_chat(3, "Obstacle avoidance in progress...")
end

function Check_Distance()
    local player = windower.ffxi.get_mob_by_id(windower.ffxi.get_player().id)
    local target = windower.ffxi.get_mob_by_target('t')

    if not target then return end

    local distance = math.sqrt(target.distance)

    if distance > 3 then
        -- Check for obstacles before moving
        if not Is_Obstacle_In_Path(player, target) then
            TurnToTarget()
            windower.ffxi.run()
        else
            windower.ffxi.run(false)  -- Stop movement if obstacle detected
            windower.add_to_chat(3, "Obstacle detected! Adjusting route...")
            Avoid_Obstacle(player, target) -- Attempt to move around it
        end
    else
        windower.ffxi.run(false)
    end
end

function test()
end

function Engine()
	Buffs = windower.ffxi.get_player()["buffs"]
    table.reassign(buffactive,convert_buff_list(Buffs))

	if isBusy < 1 then
		pcall(Combat)
	else
		isBusy = isBusy -1
	end
	if Start_Engine then
		coroutine.schedule(Engine,1)
	end
end

function Can_Use_Weaponskill(target)
    return target.hpp > 0 and target.hpp <= settings.ws_hp_threshold 
        and windower.ffxi.get_player().vitals.tp >= 1000
        and settings.weaponskill_active
        and math.sqrt(target.distance) < 3.0
end

function Use_Weaponskill()
	windower.send_command(('input /ws "%s" <t>'):format(settings.weaponskill))
	isBusy = Action_Delay
end


function Combat()
    if windower.ffxi.get_player().status == 1 then  -- If already engaged in combat
        TurnToTarget()
        Check_Distance()
        
        local target = windower.ffxi.get_mob_by_target('t')

        -- If current target is dead or not valid, find a new attacker
        if not target or target.hpp <= 0 or not target.valid_target then
            local new_target_id = Find_Nearest_Target()
            if new_target_id > 0 then
                windower.send_command("input /target "..new_target_id)
                windower.send_command("input /attack on")
            end
        end

        -- Use weaponskill if conditions are met
        if target and Can_Use_Weaponskill(target) then
            Use_Weaponskill()
        elseif Can_Cast_Spell(settings.spell) and settings.spell_active then
            Cast_Spell(settings.spell)
        end
    else
        -- If not in combat, find the closest attacker and engage
        local target_id = Find_Nearest_Target()
        if target_id > 0 then
            windower.ffxi.follow(target_id)
            if math.sqrt(windower.ffxi.get_mob_by_index(target_id).distance) < 3 then
                windower.send_command("input /target "..target_id)
                windower.send_command("input /attack on")
            end
        end
    end
end

function Can_Cast_Spell(spell)
	local result = false
	local myspell = res.spells:with('name',spell)
	Recasts = windower.ffxi.get_spell_recasts()
	if (Recasts[myspell.id] == 0) and (not isCasting) and (windower.ffxi.get_player().vitals.mp >= myspell.mp_cost) and (isBusy == 0) then
		result = true
	end
	return result
end

function Can_Cast_Ability(ability)
	local result = false
	local myability = res.job_abilities:with('name',ability)
	Recasts = windower.ffxi.get_ability_recasts()
	print("Checking:"..myability.name)
	if (Recasts[myability.recast_id] == 0) and (not isCasting) and (isBusy == 0) then
		result = true
	end
	return result
end

function Cast_Spell(spell)
	Recasts = windower.ffxi.get_spell_recasts()
	local myspell = res.spells:with('name',spell)
	if Recasts[myspell.id] == 0 and not isCasting then
		windower.send_command(('input /ma "%s" <t>'):format(myspell.name))
		isBusy = Action_Delay
	end
end

function Cast_Ability(ability)
	Recasts = windower.ffxi.get_ability_recasts()
	local myability = res.job_abilities:with('name',ability)
	if Recasts[myability.recast_id] == 0 and not isCasting then
		windower.send_command(myability.name)
		isBusy = Action_Delay
	end
end


function convert_buff_list(bufflist)
    local buffarr = {}
    for i,v in pairs(bufflist) do
        if res.buffs[v] then -- For some reason we always have buff 255 active, which doesn't have an entry.
            local buff = res.buffs[v].english
            if buffarr[buff] then
                buffarr[buff] = buffarr[buff] +1
            else
                buffarr[buff] = 1
            end

            if buffarr[v] then
                buffarr[v] = buffarr[v] +1
            else
                buffarr[v] = 1
            end
        end
    end
    return buffarr
end
