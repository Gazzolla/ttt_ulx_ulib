--[[
	Title: Player

	Has useful player-related functions.
]]

--[[
	Function: getPicker

	Gets the player directly in front of the specified player

	Parameters:

		ply - The player to look for another player in front of.
		radius - *(Optional, defaults to 30)* How narrow to make our checks for players in front of us.

	Returns:

		The player most directly in front of us if one exists with the given constraints, otherwise nil.

	Revisions:

		v2.40 - Initial.
]]
function ULib.getPicker(ply, radius)
	radius = radius or 30

	local trace = util.GetPlayerTrace(ply)
	local trace_results = util.TraceLine(trace)

	if not trace_results.Entity:IsValid() or not trace_results.Entity:IsPlayer() then
		-- Try finding a best choice
		local best_choice
		local best_choice_diff
		local pos = ply:GetPos()
		local ang = ply:GetAimVector():Angle()
		local players = player.GetAll()
		for _, player in ipairs(players) do
			if player ~= ply then
				local vec_diff = player:GetPos() - Vector(0, 0, 16) - pos
				local newang = vec_diff:Angle()
				local diff = math.abs(math.NormalizeAngle(newang.pitch - ang.pitch)) +
					math.abs(math.NormalizeAngle(newang.yaw - ang.yaw))
				if not best_choice_diff or diff < best_choice_diff then
					best_choice_diff = diff
					best_choice = player
				end
			end
		end

		if not best_choice or best_choice_diff > radius then
			return -- Give up
		else
			return best_choice
		end
	else
		return trace_results.Entity
	end
end

local Player = FindMetaTable("Player")
local checkIndexes = { Player.UniqueID,
	function(ply) if CLIENT then return "" end local ip = ULib.splitPort(ply:IPAddress()) return ip end, Player.SteamID,
	Player.UserID }
--[[
	Function: getPlyByID

	Finds a user identified by the given ID.

	Parameters:

		id - The ID to try to match against connected players. Can be a unique id, ip address, steam id, or user id.

	Returns:

		The player matching the id given or nil if none match.

	Revisions:

		v2.50 - Initial.
]]
function ULib.getPlyByID(id)
	id = id:upper()

	local players = player.GetAll()
	for _, indexFn in ipairs(checkIndexes) do
		for _, ply in ipairs(players) do
			if tostring(indexFn(ply)) == id then
				return ply
			end
		end
	end

	return nil
end

--[[
	Function: getUniqueIDForPly

	Finds a unique ID for a player, suitable for use in getUsers or getUser to uniquely identify the given player.

	Parameters:

		ply - The player we want an ID for

	Returns:

		The id for the player or nil if none are unique.

	Revisions:

		v2.50 - Initial.
		v2.51 - Added exception for single player since it's handled differently on client and server.
]]
function ULib.getUniqueIDForPlayer(ply)
	if game.SinglePlayer() then
		return "1"
	end

	local players = player.GetAll()
	for _, indexFn in ipairs(checkIndexes) do
		local id = indexFn(ply)
		if ULib.getUser("$" .. id, true) == ply then
			return id
		end
	end

	return nil
end

--[[
	Function: getUsers

	Finds users matching an identifier.

	Parameters:

		target - A string of what you'd like to target. Accepts a comma separated list.
		enable_keywords - *(Optional, defaults to false)* If true, the keywords "*" for all players, "^" for self,
			"@" for picker (person in front of you), "#<group>" for those inside a specific group,
			"%<group>" for users inside a group (counting inheritance), and "$<id>" for users matching a
			particular ID will be activated.
			Any of these can be negated with "!" before it. IE, "!^" targets everyone but yourself.
		ply - *(Optional)* Player needing getUsers, this is necessary for some of the keywords.

	Returns:

		A table of players (false and message if none found).

	Revisions:

		v2.40 - Rewrite, added more keywords, removed immunity.
		v2.50 - Added "#" and '$' keywords, removed special exception for "%user" (replaced by "#user").
		v2.60 - Returns false if target is an empty string.
]]

--[[
 0 - inocente
 1 - traidor
 2 - detetive
 3 - vivo
 4 - specDM
 5 - morto
 6 - espectador
]]

function GetPlayerFilter(param)
	local result = {}
	local players = player.GetAll()

	if (param > 6 or param < 0) then return end

	for k, v in ipairs(players) do
		if !IsValid(v) then return end
		-- Não, esta lógica não é perfeita, mas funciona. Por ora, é o que importa.
		if param > 2 then
			if param == 3 and (v:IsTerror() and (v:IsActive() or (v:Alive() and !v:IsSpec()))) then
				table.insert(result, v)
			end
			if param == 4 and v:IsGhost() then
				table.insert(result, v)
			end
			if param == 5 and (!v:Alive() and v:IsSpec() and !v:IsGhost()) then
				-- Gambiarra porque quando só tem um jogador, mortos e espectadores são exatamente a mesma merda
				if #players == 1 then return end
				table.insert(result, v)
			end
			if param == 6 and (v:IsSpec() and v:Alive() and !v:IsGhost()) then
				table.insert(result, v)
			end
		else
			if (v:GetRole() == param) and not (v:IsSpec() and v:Alive()) then -- porque Espectadores são considerados Inocentes...
				table.insert(result, v)
			end
		end
	end

	return result
end

function ULib.getUsers(target, enable_keywords, ply)
	if target == "" then
		return false, "Nenhum alvo especificado!"
	end
	UlxCommandFilter = ""
	local players = player.GetAll()

	-- First, do a full name match in case someone's trying to exploit our target system
	for _, player in ipairs(players) do
		if target:lower() == player:Nick():lower() then
			return { player }
		end
	end
	-- Okay, now onto the show!
	local targetPlys = {}
	local pieces = ULib.explode(",", target)
	for _, piece in ipairs(pieces) do
		piece = piece:Trim()
		if piece ~= "" then
			local keywordMatch = false
			if enable_keywords then
				local tmpTargets = {}
				local negate = false
				if piece:sub(1, 1) == "!" and piece:len() > 1 then
					negate = true
					piece = piece:sub(2)
				end

				if piece:sub(1, 1) == "$" then
					local player = ULib.getPlyByID(piece:sub(2))
					if player then
						table.insert(tmpTargets, player)
					end
				elseif piece == "*" then -- TODOS!
					table.Add(tmpTargets, players)
				elseif piece == "^" then -- Você mesmo!
					if ply then
						if ply:IsValid() then
							table.insert(tmpTargets, ply)
						elseif not negate then
							return false, "Você não pode afetar a si mesmo pelo console remoto!"
						end
					end
				elseif piece == "@" then -- Jogador na sua frente!
					if IsValid(ply) then

						local player = ULib.getPicker(ply)
						if player then
							table.insert(tmpTargets, player)
						end
					end
				elseif piece == "@i" then
					if IsValid(ply) then

						for k, v in ipairs(GetPlayerFilter(0)) do

							if v then
								table.insert(tmpTargets, v)
							end
						end
						if !negate then
							UlxCommandFilter = "innocent"
						else
							UlxCommandFilter = "!innocent"
						end
					end
				elseif piece == "@t" then
					if IsValid(ply) then

						for k, v in ipairs(GetPlayerFilter(1)) do

							if v then
								table.insert(tmpTargets, v)
							end
						end
						if !negate then
							UlxCommandFilter = "traitor"
						else
							UlxCommandFilter = "!traitor"
						end
					end
				elseif piece == "@d" then
					if IsValid(ply) then
						for k, v in ipairs(GetPlayerFilter(2)) do

							if v then
								table.insert(tmpTargets, v)
							end
						end
						if !negate then
							UlxCommandFilter = "detective"
						else
							UlxCommandFilter = "!detective"
						end
					end
				elseif piece == "@alive" then
					if IsValid(ply) then
						for k, v in ipairs(GetPlayerFilter(3)) do

							if v then
								table.insert(tmpTargets, v)
							end
						end
						if !negate then
							UlxCommandFilter = "alive"
						else
							UlxCommandFilter = "!alive"
						end
					end
				elseif piece == "@dm" then
					if IsValid(ply) then
						for k, v in ipairs(GetPlayerFilter(4)) do

							if v then
								table.insert(tmpTargets, v)
							end
						end
						if !negate then
							UlxCommandFilter = "dm"
						else
							UlxCommandFilter = "!dm"
						end
					end
				elseif piece == "@dead" then
					if IsValid(ply) then
						for k, v in ipairs(GetPlayerFilter(5)) do

							if v then
								table.insert(tmpTargets, v)
							end
						end
						if !negate then
							UlxCommandFilter = "dead"
						else
							UlxCommandFilter = "!dead"
						end
					end
				elseif piece == "@spec" then
					if IsValid(ply) then
						for k, v in ipairs(GetPlayerFilter(6)) do

							if v then
								table.insert(tmpTargets, v)
							end
						end
						if !negate then
							UlxCommandFilter = "spec"
						else
							UlxCommandFilter = "!spec"
						end
					end
				elseif piece:sub(1, 1) == "#" and ULib.ucl.groups[piece:sub(2)] then
					local group = piece:sub(2)
					for _, player in ipairs(players) do
						if player:GetUserGroup() == group then
							table.insert(tmpTargets, player)
						end
					end
				elseif piece:sub(1, 1) == "%" and ULib.ucl.groups[piece:sub(2)] then
					local group = piece:sub(2)
					for _, player in ipairs(players) do
						if player:CheckGroup(group) then
							table.insert(tmpTargets, player)
						end
					end
				else
					local tblForHook = hook.Run(ULib.HOOK_GETUSERS_CUSTOM_KEYWORD, piece, ply)
					if tblForHook then
						table.Add(tmpTargets, tblForHook)
					end
				end

				if negate then
					for _, player in ipairs(players) do
						if not table.HasValue(tmpTargets, player) then
							keywordMatch = true
							table.insert(targetPlys, player)
						end
					end
				else
					if #tmpTargets > 0 then
						keywordMatch = true
						table.Add(targetPlys, tmpTargets)
					end
				end
			end

			if not keywordMatch then
				for _, player in ipairs(players) do
					if player:Nick():lower():find(piece:lower(), 1, true) then -- No patterns
						table.insert(targetPlys, player)
					end
				end
			end
		end
	end

	-- Now remove duplicates
	local finalTable = {}
	for _, player in ipairs(targetPlys) do
		if not table.HasValue(finalTable, player) then
			table.insert(finalTable, player)
		end
	end

	if #finalTable < 1 then
		return false, "Nenhum alvo encontrado ou tem imunidade!"
	end

	return finalTable
end

--[[
	Function: getUser

	Finds a user matching an identifier.

	Parameters:

		target - A string of the user you'd like to target. IE, a partial player name.
		enable_keywords - *(Optional, defaults to false)* If true, the keywords "^" for self, "@" for picker (person in
			front of you), and "$<id>" will be activated.
		ply - *(Optional)* Player needing getUsers, this is necessary to use keywords.

	Returns:

		The resulting player target, false and message if no user found.

	Revisions:

		v2.40 - Rewrite, added keywords, removed immunity.
		v2.50 - Added "$" keyword.
		v2.60 - Returns false if target is an empty string.
]]
function ULib.getUser(target, enable_keywords, ply)
	if target == "" then
		return false, "Nenhum alvo especificado!"
	end

	local players = player.GetAll()
	target = target:lower()

	local plyMatches = {}
	if enable_keywords and target:sub(1, 1) == "$" then
		possibleId = target:sub(2)
		table.insert(plyMatches, ULib.getPlyByID(possibleId))
	end

	-- First, do a full name match in case someone's trying to exploit our target system
	for _, player in ipairs(players) do
		if target == player:Nick():lower() then
			if #plyMatches == 0 then
				return player
			else
				return false, "Muitos alvos encontrados! Use uma busca mais precisa pelo alvo. (Ex.: nome inteiro)"
			end
		end
	end

	if enable_keywords then
		if target == "^" and ply then
			if ply:IsValid() then
				return ply
			else
				return false, "Você não pode afetar a si mesmo pelo console remoto!"
			end
		elseif IsValid(ply) and target == "@" then
			local player = ULib.getPicker(ply)
			if not player then
				return false, "Ninguém na mira para ser afetado."
			else
				return player
			end
		else
			local player = hook.Run(ULib.HOOK_GETUSER_CUSTOM_KEYWORD, target, ply)
			if player then return player end
		end
	end

	for _, player in ipairs(players) do
		if player:Nick():lower():find(target, 1, true) then -- No patterns
			table.insert(plyMatches, player)
		end
	end

	if #plyMatches == 0 then
		return false, "Nenhum alvo encontrado ou tem imunidade!"
	elseif #plyMatches > 1 then
		local str = plyMatches[1]:Nick()
		for i = 2, #plyMatches do
			str = str .. ", " .. plyMatches[i]:Nick()
		end

		return false,
			"Muitos alvos encontrados: " .. str .. ". Use uma busca mais precisa pelo alvo. (Ex.: nome inteiro)"
	end

	return plyMatches[1]
end
