--[[

	The MIT License (MIT)

	Copyright (c) 2025 Lars Norberg

	Permission is hereby granted, free of charge, to any person obtaining a copy
	of this software and associated documentation files (the "Software"), to deal
	in the Software without restriction, including without limitation the rights
	to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
	copies of the Software, and to permit persons to whom the Software is
	furnished to do so, subject to the following conditions:

	The above copyright notice and this permission notice shall be included in all
	copies or substantial portions of the Software.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
	AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
	OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
	SOFTWARE.

--]]
local Addon, Private =  ...
local Bagnon = Bagnon or Bagnonium
local Module = Bagnon:NewModule("Bagnon_ItemLevel")

local Cache = LibStub("LibItemCache-2.0", true)
local Container = LibStub("C_Everywhere").Container

local cache = {}

-- Lua API
local _G = _G
local ipairs = ipairs
local string_gsub = string.gsub
local string_match = string.match
local tonumber = tonumber

-- WoW API
local C_Item, C_TooltipInfo, TooltipUtil = C_Item, C_TooltipInfo, TooltipUtil
local CreateFrame, GetItemQualityColor = CreateFrame, GetItemQualityColor
local GetItemInfo = C_Item.GetItemInfo or GetItemInfo
local GetItemInfoInstant = C_Item.GetItemInfoInstant or GetItemInfoInstant

local retail = Private.IsRetail
local tooltip = Private.tooltip
local tooltipName = Private.tooltipName
local battlepetclass = Enum.ItemClass.Battlepet

-- Font object
local font_object = NumberFont_Outline_Med or NumberFontNormal

-- Search patterns
local s_item_level = "^" .. string_gsub(ITEM_LEVEL, "%%d", "(%%d+)")
local s_num_slots = "^" .. (string_gsub(string_gsub(CONTAINER_SLOTS, "%%([%d%$]-)d", "(%%d+)"), "%%([%d%$]-)s", "%.+"))

-- Custom color cache
-- Allows us control, gives us speed.
local colors = {
	[0] = { 0.72, 0.72, 0.72 }, -- Poor
	[1] = { 1.0, 1.0, 1.0 }, -- Common
	[2] = { 0.3, 1.0, 0.38 }, -- Uncommon (green)
	[3] = { 0.4, 0.71, 1.0 }, -- Rare (blue)
	[4] = { 0.97, 0.63, 0.83 }, -- Epic (pink)
	[5] = { 1, 0.602, 0.2 }, -- Legendary (orange)
	[6] = { 0.94, 0.87, 0.67 }, -- Artifact (gold)
	[7] = { 0.2, 0.84, 1.0 }, -- Heirloom (sky blue)
	[8] = { 0.2, 0.84, 1.0 } -- Blizzard
}
for i = 0, (retail and Enum.ItemQualityMeta.NumValues or NUM_LE_ITEM_QUALITYS) - 1 do
	if (not colors[i]) then
		local r, g, b = GetItemQualityColor(i)
		colors[i] = { r, g, b }
	end
end

Private.cache[Module] = cache
Private.AddUpdater(Module, function(self)

	local db = BagnonItemInfo_DB
	local message, color, _

	if (self.hasItem and db.enableItemLevel) then

		-- https://wowpedia.fandom.com/wiki/Enum.InventoryType
		local class, equip, level, quality = self.info.class, self.info.equip, self.info.level, self.info.quality
		if (not equip and self.info.hyperlink) then
			_,_,_,equip = GetItemInfoInstant(self.info.hyperlink)
		end
		local noequip = not equip or not _G[equip] or equip == "INVTYPE_BAG" or equip == "INVTYPE_NON_EQUIP" or equip == "INVTYPE_NON_EQUIP_IGNORE" or equip == "INVTYPE_TABARD" or equip == "INVTYPE_AMMO" or equip == "INVTYPE_QUIVER" or equip == "INVTYPE_BODY"
		local isbag = equip == "INVTYPE_BAG"
		local isgear = quality and quality > 0 and not noequip
		local ispet = battlepetclass and class == battlepetclass

		-- We only want quality coloring on item- and pet levels, not bag slots.
		if (isgear or ispet) then
			if (db.enableRarityColoring) then
				color = quality and colors[quality]
			end
			if (not level) then
				--local itemName, itemLink, itemQuality, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture, sellPrice, classID, subclassID, bindType, expansionID, setID, isCraftingReagent = GetItemInfo(itemInfo)
				_, _, _, level = GetItemInfo(self.info.hyperlink)
				self.info.level = level
			end
			message = level
		end

		-- Parse itemlevel in retail, and bag slots.
		if (retail) and (isgear or isbag) then

			if (retail) then

				local tooltipData = C_TooltipInfo.GetBagItem(self:GetBag(), self:GetID())
				if (tooltipData) then

					if (isgear) then
						for i = 2,3 do
							local msg = tooltipData.lines[i] and tooltipData.lines[i].leftText
							if (not msg) then break end

							local itemlevel = string_match(msg, s_item_level)
							if (itemlevel) then
								itemlevel = tonumber(itemlevel)
								if (itemlevel >= db.minimumItemLevel) then
									message = itemlevel
								end
								break
							end
						end
					end

					if (isbag) then
						for i = 3,4 do
							local msg = tooltipData.lines[i] and tooltipData.lines[i].leftText
							if (not msg) then break end

							local numslots = string_match(msg, s_num_slots)
							if (numslots) then
								numslots = tonumber(numslots)
								if (numslots > 0) then
									message = numslots
								end
								break
							end
						end
					end
				end

			else

				if (not tooltip.owner or not tooltip.bag or not tooltip.slot) then
					tooltip.owner, tooltip.bag,tooltip.slot = self, self:GetBag(), self:GetID()
					tooltip:SetOwner(tooltip.owner, "ANCHOR_NONE")
					tooltip:SetBagItem(tooltip.bag, tooltip.slot)
				end

				if (isgear) then
					for i = 2,3 do
						local line = _G[tooltipName.."TextLeft"..i]
						if (not line) then
							break
						end

						local itemlevel = string_match(line:GetText() or "", s_item_level)
						if (itemlevel) then
							itemlevel = tonumber(itemlevel)
							if (itemlevel >= db.minimumItemLevel) then
								message = itemlevel
							end
							break
						end
					end
				end

				if (isbag) then
					for i = 3,4 do
						local line = _G[tooltipName.."TextLeft"..i]
						if (not line) then
							break
						end

						local numslots = string_match(line:GetText() or "", s_num_slots)
						if (numslots) then
							numslots = tonumber(numslots)
							if (numslots > 0) then
								message = numslots
							end
							break
						end
					end
				end

			end
		end

	end

	if (message and message >= db.minimumItemLevel) then

		local label = cache[self]
		if (not label) then

			-- Only one container per item.
			local name = self:GetName().."ExtraInfoFrame"
			local container = _G[name]
			if (not container) then
				container = CreateFrame("Frame", name, self)
				container:SetAllPoints()
			end

			-- Always move this to the same place.
			local upgrade = self.UpgradeIcon
			if (upgrade) then
				upgrade:ClearAllPoints()
				upgrade:SetPoint("BOTTOMRIGHT", 2, 0)
			end

			-- This is specific to this plugin.
			label = container:CreateFontString()
			label:SetDrawLayer("ARTWORK", 1)
			label:SetPoint("TOPLEFT", 2, -2)
			label:SetFontObject(font_object)
			label:SetShadowOffset(1, -1)
			label:SetShadowColor(0, 0, 0, .5)

			cache[self] = label
		end

		label:SetText(message)

		if (color) then
			label:SetTextColor(color[1], color[2], color[3])
		else
			label:SetTextColor(.94, .94, .94)
		end

	elseif (cache[self]) then
		cache[self]:SetText("")
	end

end)
