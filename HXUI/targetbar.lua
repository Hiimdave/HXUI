require('common');
require('helpers');
local imgui = require('imgui');
local statusHandler = require('statushandler');
local debuffHandler = require('debuffhandler');
local progressbar = require('progressbar');
local fonts = require('fonts');
local ffi = require("ffi");

-- TODO: Calculate these instead of manually setting them

local bgAlpha = 0.4;
local bgRadius = 3;

local arrowTexture;
local percentText;
local nameText;
local totNameText;
local distText;
local targetbar = {
	interpolation = {}
};

local function UpdateTextVisibility(visible)
	percentText:SetVisible(visible);
	nameText:SetVisible(visible);
	totNameText:SetVisible(visible);
	distText:SetVisible(visible);
end

local _HXUI_DEV_DEBUG_INTERPOLATION = false;
local _HXUI_DEV_DEBUG_INTERPOLATION_DELAY = 1;
local _HXUI_DEV_DEBUG_HP_PERCENT_PERSISTENT = 100;
local _HXUI_DEV_DAMAGE_SET_TIMES = {};

targetbar.DrawWindow = function(settings)
    -- Obtain the player entity..
    local playerEnt = GetPlayerEntity();
	local player = AshitaCore:GetMemoryManager():GetPlayer();
    if (playerEnt == nil or player == nil) then
		UpdateTextVisibility(false);
        return;
    end

    -- Obtain the player target entity (account for subtarget)
	local playerTarget = AshitaCore:GetMemoryManager():GetTarget();
	local targetIndex;
	local targetEntity;
	if (playerTarget ~= nil) then
		targetIndex, _ = GetTargets();
		targetEntity = GetEntity(targetIndex);
	end
    if (targetEntity == nil or targetEntity.Name == nil) then
		UpdateTextVisibility(false);

		targetbar.interpolation.interpolationDamagePercent = 0;

        return;
    end

	local currentTime = os.clock();

	local hppPercent = targetEntity.HPPercent;

	-- Mimic damage taken
	if _HXUI_DEV_DEBUG_INTERPOLATION then
		if _HXUI_DEV_DAMAGE_SET_TIMES[1] and currentTime > _HXUI_DEV_DAMAGE_SET_TIMES[1][1] then
			_HXUI_DEV_DEBUG_HP_PERCENT_PERSISTENT = _HXUI_DEV_DAMAGE_SET_TIMES[1][2];

			table.remove(_HXUI_DEV_DAMAGE_SET_TIMES, 1);
		end

		if #_HXUI_DEV_DAMAGE_SET_TIMES == 0 then
			local previousHitTime = currentTime + 1;
			local previousHp = 100;

			local totalDamageInstances = 10;

			for i = 1, totalDamageInstances do
				local hitDelay = math.random(0.25 * 100, 1.5 * 100) / 100;
				local damageAmount = math.random(5, 20);

				if i > 1 and i < totalDamageInstances then
					previousHp = math.max(previousHp - damageAmount, 0);
				end

				if i < totalDamageInstances then
					previousHitTime = previousHitTime + hitDelay;
				else
					previousHitTime = previousHitTime + _HXUI_DEV_DEBUG_INTERPOLATION_DELAY;
				end

				_HXUI_DEV_DAMAGE_SET_TIMES[i] = {previousHitTime, previousHp};
			end
		end

		hppPercent = _HXUI_DEV_DEBUG_HP_PERCENT_PERSISTENT;
	end

	-- If we change targets, reset the interpolation
	if targetbar.interpolation.currentTargetId ~= targetIndex then
		targetbar.interpolation.currentTargetId = targetIndex;
		targetbar.interpolation.currentHpp = hppPercent;
		targetbar.interpolation.interpolationDamagePercent = 0;
	end

	-- If the target takes damage
	if hppPercent < targetbar.interpolation.currentHpp then
		local previousInterpolationDamagePercent = targetbar.interpolation.interpolationDamagePercent;

		local damageAmount = targetbar.interpolation.currentHpp - hppPercent;

		targetbar.interpolation.interpolationDamagePercent = targetbar.interpolation.interpolationDamagePercent + damageAmount;

		targetbar.interpolation.lastHitTime = currentTime;

		-- If we previously were interpolating with an empty bar, reset the hit delay effect
		if previousInterpolationDamagePercent == 0 then
			if not targetbar.interpolation.hitDelayStartTime or currentTime > targetbar.interpolation.hitDelayStartTime + settings.hitDelayDuration then
				targetbar.interpolation.hitDelayStartTime = currentTime;
			end
		end
	elseif hppPercent > targetbar.interpolation.currentHpp then
		-- If the target heals
		targetbar.interpolation.interpolationDamagePercent = 0;
		targetbar.interpolation.hitDelayStartTime = nil;
	end

	targetbar.interpolation.currentHpp = hppPercent;

	-- Reduce the HP amount to display based on the time passed since last frame
	if targetbar.interpolation.interpolationDamagePercent > 0 and targetbar.interpolation.hitDelayStartTime and currentTime > targetbar.interpolation.hitDelayStartTime + settings.hitDelayDuration then
		if targetbar.interpolation.lastFrameTime then
			local deltaTime = currentTime - targetbar.interpolation.lastFrameTime;

			local animSpeed = 0.4 + (0.6 * (targetbar.interpolation.interpolationDamagePercent / 100));

			-- animSpeed = math.max(settings.hitDelayMinAnimSpeed, animSpeed);

			targetbar.interpolation.interpolationDamagePercent = targetbar.interpolation.interpolationDamagePercent - (settings.hitInterpolationDecayPercentPerSecond * deltaTime * animSpeed);

			-- Clamp our percent to 0
			targetbar.interpolation.interpolationDamagePercent = math.max(0, targetbar.interpolation.interpolationDamagePercent);
		end
	end

	if targetbar.interpolation.lastHitTime and currentTime < targetbar.interpolation.lastHitTime + settings.hitFlashDuration then
		local hitFlashTime = currentTime - targetbar.interpolation.lastHitTime;
		local hitFlashTimePercent = hitFlashTime / settings.hitFlashDuration;

		targetbar.interpolation.overlayAlpha = math.pow(1 - hitFlashTimePercent, 3);
	end

	targetbar.interpolation.lastFrameTime = currentTime;

	local color = GetColorOfTarget(targetEntity, targetIndex);
	local isMonster = GetIsMob(targetEntity);

	-- Draw the main target window
    if (imgui.Begin('TargetBar', true, bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground))) then
        
		-- Obtain and prepare target information..
        local dist  = ('%.1f'):fmt(math.sqrt(targetEntity.Distance));
		local targetNameText = targetEntity.Name;
		local targetHpPercent = targetEntity.HPPercent..'%';

		if (gConfig.showEnemyId and isMonster) then
			local targetServerId = AshitaCore:GetMemoryManager():GetEntity():GetServerId(targetIndex);
			local targetServerIdHex = string.format('0x%X', targetServerId);

			targetNameText = targetNameText .. " [".. string.sub(targetServerIdHex, -3) .."]";
		end

		local hpGradientStart = '#e26c6c';
		local hpGradientEnd = '#fb9494';

		local hpPercentData = {{targetEntity.HPPercent / 100, {hpGradientStart, hpGradientEnd}}};

		if _HXUI_DEV_DEBUG_INTERPOLATION then
			hpPercentData[1][1] = targetbar.interpolation.currentHpp / 100;
		end

		if targetbar.interpolation.interpolationDamagePercent > 0 then
			table.insert(
				hpPercentData,
				{
					targetbar.interpolation.interpolationDamagePercent / 100, -- interpolation percent
					{'#cf3437', '#c54d4d'}, -- interpolation gradient
					{
						'#FFFFFF', -- overlay color,
						targetbar.interpolation.overlayAlpha * 0.5 -- overlay alpha,
					}
				}
			);
		end
		
		local startX, startY = imgui.GetCursorScreenPos();
		progressbar.ProgressBar(hpPercentData, {settings.barWidth, settings.barHeight});

		local nameSize = SIZE.new();
		nameText:GetTextSize(nameSize);

		nameText:SetPositionX(startX + settings.barHeight / 2 + settings.topTextXOffset);
		nameText:SetPositionY(startY - settings.topTextYOffset - nameSize.cy);
		nameText:SetColor(color);
		nameText:SetText(targetNameText);
		nameText:SetVisible(true);

		local distSize = SIZE.new();
		distText:GetTextSize(distSize);

		distText:SetPositionX(startX + settings.barWidth - settings.barHeight / 2 - settings.topTextXOffset);
		distText:SetPositionY(startY - settings.topTextYOffset - distSize.cy);
		distText:SetText(tostring(dist));
		distText:SetVisible(true);

		if (isMonster or gConfig.alwaysShowHealthPercent) then
			percentText:SetPositionX(startX + settings.barWidth - settings.barHeight / 2 - settings.bottomTextXOffset);
			percentText:SetPositionY(startY + settings.barHeight + settings.bottomTextYOffset);
			percentText:SetText(tostring(targetHpPercent));
			percentText:SetVisible(true);
			local hpColor, _ = GetHpColors(targetEntity.HPPercent / 100);
			percentText:SetColor(hpColor);
		else
			percentText:SetVisible(false);
		end

		-- Draw buffs and debuffs
		imgui.SameLine();
		local preBuffX, preBuffY = imgui.GetCursorScreenPos();
		local buffIds;
		if (targetEntity == playerEnt) then
			buffIds = player:GetBuffs();
		elseif (IsMemberOfParty(targetIndex)) then
			buffIds = statusHandler.get_member_status(playerTarget:GetServerId(0));
		else
			buffIds = debuffHandler.GetActiveDebuffs(playerTarget:GetServerId(0));
		end
		imgui.NewLine();
		imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, {1, 3});
		DrawStatusIcons(buffIds, settings.iconSize, settings.maxIconColumns, 3, false, settings.barHeight/2);
		imgui.PopStyleVar(1);

		-- Obtain our target of target (not always accurate)
		local totEntity;
		local totIndex
		if (targetEntity == playerEnt) then
			totIndex = targetIndex
			totEntity = targetEntity;
		end
		if (totEntity == nil) then
			totIndex = targetEntity.TargetedIndex;
			if (totIndex ~= nil) then
				totEntity = GetEntity(totIndex);
			end
		end
		if (totEntity ~= nil and totEntity.Name ~= nil) then

			imgui.SetCursorScreenPos({preBuffX, preBuffY});
			local totX, totY = imgui.GetCursorScreenPos();
			local totColor = GetColorOfTarget(totEntity, totIndex);
			imgui.SetCursorScreenPos({totX, totY + settings.barHeight/2 - settings.arrowSize/2});
			imgui.Image(tonumber(ffi.cast("uint32_t", arrowTexture.image)), { settings.arrowSize, settings.arrowSize });
			imgui.SameLine();

			totX, _ = imgui.GetCursorScreenPos();
			imgui.SetCursorScreenPos({totX, totY - (settings.totBarHeight / 2) + (settings.barHeight/2) + settings.totBarOffset});

			local totStartX, totStartY = imgui.GetCursorScreenPos();
			progressbar.ProgressBar({{totEntity.HPPercent / 100, {'#e16c6c', '#fb9494'}}}, {settings.barWidth / 3, settings.totBarHeight});

			local totNameSize = SIZE.new();
			totNameText:GetTextSize(totNameSize);

			totNameText:SetPositionX(totStartX + settings.barHeight / 2);
			totNameText:SetPositionY(totStartY - totNameSize.cy);
			totNameText:SetColor(totColor);
			totNameText:SetText(totEntity.Name);
			totNameText:SetVisible(true);
		else
			totNameText:SetVisible(false);
		end
    end
	local winPosX, winPosY = imgui.GetWindowPos();
    imgui.End();
end

targetbar.Initialize = function(settings)
    percentText = fonts.new(settings.percent_font_settings);
	nameText = fonts.new(settings.name_font_settings);
	totNameText = fonts.new(settings.totName_font_settings);
	distText = fonts.new(settings.distance_font_settings);
	arrowTexture = 	LoadTexture("arrow");
end

targetbar.UpdateFonts = function(settings)
    percentText:SetFontHeight(settings.percent_font_settings.font_height);
	nameText:SetFontHeight(settings.name_font_settings.font_height);
	distText:SetFontHeight(settings.distance_font_settings.font_height);
	totNameText:SetFontHeight(settings.totName_font_settings.font_height);
end

targetbar.SetHidden = function(hidden)
	if (hidden == true) then
		UpdateTextVisibility(false);
	end
end



return targetbar;