--[[
 LibFlash
 
 Copyright (C) 2010 Scott Sibley <starlon@users.sourceforge.net>

 Authors: Scott Sibley

 $Id: LibFlash.lua 46 2011-07-08 05:02:07Z starlon $

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU Lesser General Public License as
 published by the Free Software Foundation; either version 3
 of the License, or (at your option) any later version.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU Lesser General Public License for more details.

 You should have received a copy of the GNU Lesser General Public License
 along with this program; if not, write to the Free Software
 Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
]]

local MAJOR = "LibFlash" 
local MINOR = 6
assert(LibStub, MAJOR.." requires LibStub") 
local LibFlash = LibStub:NewLibrary(MAJOR, MINOR)
if not LibFlash then return end

if not LibFlash.pool then
	LibFlash.pool = setmetatable({},{__mode='k'})
	LibFlash.objects = {}
	LibFlash.__index = LibFlash
end

local FADETYPE = 0
local FLASHTYPE = 1

local GetTime = Inspect.Time.Frame
local tinsert, tremove = table.insert, table.remove

local function findFlash(obj)
	for i, o in ipairs(LibFlash.objects) do
		if o == obj then
			return i
		end
	end
	return 0
end

function LibFlash:New(frame)
	if not frame then
		error("No frame specified")
	end

	local obj = next(self.pool)

	if obj then
		self.pool[obj] = nil
	else
		obj = {}
	end

	setmetatable(obj, self)

	obj.frame = frame
	
	tinsert(self.objects, obj)
	
	return obj
end

function LibFlash:Del()
	if self.frame then
		self:Stop()
		LibFlash.pool[self] = true
		local i = findFlash(self)
		if i > 0 then
			table.remove(LibFlash.objects, i)
		end
	end
end

function LibFlash:Stop()
	if self.childFlash then 
		self.childFlash:Stop(true)
	end
	self.active = false
	self.timer = 0
end

local function fadeUpdate(self)

	if self.timer < 0.1 then
		return
	end
	
	local alpha = 0
	if self.startA < self.finishA then 
		alpha = (self.finishA - self.startA) * (self.timer / self.dur) + self.startA
	else
		alpha = (self.startA - self.finishA) * (1 - self.timer / self.dur) + self.finishA
	end

	if alpha < 0 then
		alpha = 0
	elseif alpha > 1 then
		alpha = 1
	end

	self.frame:SetAlpha(alpha)

	if self.timer > self.dur then
		self:Stop()
		self.frame:SetAlpha(self.finishA)
		if self.callback then self.callback(self.data) end
	end
end

function LibFlash:Fade(dur, startA, finishA, callback, data)
	if self.active then return false end
		
	self.frame:SetAlpha(startA)
	
	self.dur = dur
	self.startA = startA
	self.finishA = finishA
	self.callback = callback
	self.data = data
	
	self.active = true
	self.type = FADETYPE
	
	return true
end

function LibFlash:FadeIn(dur, startA, finishA, callback, data)
	if startA <= finishA then
		return self:Fade(dur, startA, finishA, callback, data)
	else
		error("FadeIn with bad parameters")
	end
end

function LibFlash:FadeOut(dur, startA, finishA, callback, data)
	if startA >= finishA then
		return self:Fade(dur, startA, finishA, callback, data)
	else
		error("FadeOut with bad parameters")
	end
end

local incrementState = function(flash)
	flash.state = flash.state + 1
end

local decrementState = function(flash)
	flash.state = flash.state - 1
end

local setState = function(flash)
	flash.state = flash.newState
end

local setBlinkState = function(flash)
	flash.blinkState = flash.newBlinkState
	flash.blinkTimer = 0
end

local flashUpdate = function(self)

	if self.timer < 0.1 then
		return
	end
	
	if self.state == 0 then
		self.flashinHoldTimer = self.flashinHoldTimer + self.timer
		self.timer = 0
		
		if self.flashinHoldTimer > self.flashinHoldTime then
			incrementState(self)
			self.flashinHoldTimer = 0
		end
	elseif self.state == 1 then
		self.childFlash:FadeIn(self.fadeinTime, 0, 1, incrementState, self)
	elseif self.state == 2 then
		self.flashoutHoldTimer = self.flashoutHoldTimer + self.timer
		self.blinkTimer = self.blinkTimer + self.timer
		self.timer = 0
		if self.blinkTimer > (self.blinkRate or .3) and self.shouldBlink then			
			if self.blinkState == 0 or self.blinkState == nil then
				self.newBlinkState = 1
				self.childFlash:FadeIn(self.fadeinTime, 0, 1, setBlinkState, self)
			else
				self.newBlinkState = 0
				self.childFlash:FadeOut(self.fadeoutTime, 1, 0, setBlinkState, self)
			end
			self.blinkTimer = 0	
		end
		if self.flashoutHoldTimer > self.flashoutHoldTime then
			self.childFlash:Stop()
			self.childFlash:FadeOut(self.fadeoutTime, 1, 0, incrementState, self)
			self.flashoutHoldTimer = -0xdead
		end
	elseif self.state == 3 then
		if self.timer > self.flashDuration - self.fadeinTime then
			self:Stop()
			if self.showWhenDone then
				self.childFlash:FadeIn(self.fadeinTime, 0, 1, self.callback, self.data)
			elseif self.callback then
				self.callback(self.data)
			end
		end		
	end
end
	
function LibFlash:Flash(fadeinTime, fadeoutTime, flashDuration, showWhenDone, flashinHoldTime, flashoutHoldTime, shouldBlink, blinkRate, callback, data)

	if self.active then return false end
	if not self.childFlash then self.childFlash = LibFlash:New(self.frame) end

	self.timer = 0
	self.flashinHoldTimer = 0
	self.flashoutHoldTimer = 0
	self.blinkTimer = 0
	self.blinkState = 0

	self.state = 0

	self.fadeinTime = fadeinTime
	self.fadeoutTime = fadeoutTime
	self.flashDuration = flashDuration
	self.showWhenDone = showWhenDone
	self.flashinHoldTime = flashinHoldTime
	self.flashoutHoldTime = flashoutHoldTime
	self.shouldBlink = shouldBlink
	self.blinkRate = blinkRate
	self.callback = callback
	self.data = data

	self.active = true
	self.type = FLASHTYPE
	
	return true
end

local lastUpdate = GetTime()
local update = function(...)
	if #LibFlash.objects == 0 then
		return
	end

	local elapsed = GetTime() - lastUpdate
	lastUpdate = GetTime()
	
	for i, o in ipairs(LibFlash.objects) do
		if o.active then
			o.timer = (o.timer or 0) + elapsed
			if o.type == FADETYPE then
				fadeUpdate(o)
			elseif o.type == FLASHTYPE then
				flashUpdate(o)
			end
		end
	end
end

table.insert(Event.System.Update.Begin, {update, "LibFlash", "refresh"})
