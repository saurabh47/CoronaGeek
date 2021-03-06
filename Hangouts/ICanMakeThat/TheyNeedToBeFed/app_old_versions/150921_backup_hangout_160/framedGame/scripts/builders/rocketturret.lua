-- =============================================================
-- Copyright Roaming Gamer, LLC. 2009-2015 
-- =============================================================
-- 
-- =============================================================
local common 	= require "scripts.common"
local utils 	= require "scripts.builders.builder_utils"
local math2d	= require "plugin.math2d"


-- Localize math2d functions for an execution speedup
local scaleVec 		= math2d.scale
local subVec		= math2d.diff
local normVec		= math2d.normalize
local vector2Angle	= math2d.vector2Angle
local angle2Vector	= math2d.angle2Vector
local normalVecs	= math2d.normals

local calculateDistanceToPlayer = utils.calculateDistanceToPlayer

local builder = {}

-- =============================================
-- The Builder (Create) Function
-- =============================================
function builder.create( layers, data )
	local aPiece

	-- Create an object (basic or pretty) to represent this world object
	--
	if( common.niceGraphics ) then
		aPiece = display.newImageRect( layers.content, "images/kenney/elementMetal001.png", common.turretSize, common.turretSize )
		aPiece.x = data.x
		aPiece.y = data.y
	else
		aPiece = display.newCircle( layers.content, data.x, data.y, common.turretSize/2 )
		aPiece.strokeWidth = 4
		aPiece:setStrokeColor(0,0,0)
	end

	-- If debug mode is enabled, add a label for showing 'distance to'
	--
	if( common.debugEn ) then	
		-- debug label to show distance to player
		aPiece.debugLabel = display.newText( layers.content, "TBD", data.x, data.y + common.blockSize/3, native.systemFontBold, 18 )
		aPiece.debugLabel:setFillColor(1,0,0)
	end

	-- Add a physics body to our world object and use the appropriate filter from the 'collision calculator'
	--
	local physics = require "physics"
	physics.addBody( aPiece, "static", 
		             { density = 1, bounce = 0, friction = 1, radius = common.turretSize/2,
		               filter = common.myCC:getCollisionFilter( "platform" ) } )

	-- This is a platform object, so add it to the 'common.pieces' list.  The player scans this list for nearby 'gravity' objects.
	--
	common.pieces[#common.pieces+1] = aPiece


	-- Create an object to act as our turret
	--
	local turret = display.newImageRect( layers.content, "images/kenney/turret.png", common.blockSize, common.blockSize )
	turret.x = data.x
	turret.y = data.y
	aPiece.turret = turret

	-- Orient based on subtype
	if( data.subtype == 1 ) then
		turret.rotation = 45
	elseif( data.subtype == 2 ) then
		turret.rotation = 135
	elseif( data.subtype == 3 ) then
		turret.rotation = 225
	elseif( data.subtype == 4 ) then
		turret.rotation = 315
	end

	-- Add code to fire rocket when player is in range
	turret.timer = function( self )
		if( self.removeSelf == nil ) then			
			return
		end

		-- Is player in 'range'?  If not, exit early.
		if( calculateDistanceToPlayer( self, common.currentPlayer ) > common.rocketMinFireDistance ) then
			timer.performWithDelay( 500, turret )
			self:setFillColor( 1, 1, 1 )
			return 
		end

		-- Player is in range, change color of turret to indicate 'danger'
		--
		self:setFillColor( 1, 0.5, 0.5 )

		-- Create a 'rocket'

		local rocket = display.newRect( self.parent, self.x, self.y, common.laserWidth/2, common.laserWidth )
		rocket.rotation = self.rotation
		rocket:setFillColor(0.5,0.5,1)
		rocket:setStrokeColor(1,1,0,0.35)
		rocket.strokeWidth = 4
		rocket:toBack()

		-- Add body to rocket so we can move it with physics and detect collisions
		physics.addBody( rocket, "dynamic", 
			             { density = 1, bounce = 0, friction = 1, 
			               filter = common.myCC:getCollisionFilter( "bullet" ) } )
		rocket.isSensor = true
		rocket.isBullet = true

		-- Set the initial velocity of our rocket
		local vec = angle2Vector( rocket.rotation, true )
		vec = scaleVec( vec, common.rocketSpeed )
		rocket:setLinearVelocity( vec.x, vec.y )

		-- Every frame, adjust aim, thrust forward, and lay out a simple particle trail
		--
		rocket.enterFrame = function( self )			
			if( self.removeSelf == nil  or
				--common.currentPlayer.removeSelf == nil or
				self.setLinearVelocity == nil  ) then		
				Runtime:removeEventListener( "enterFrame", self )
				return
			end

			-- Once a rocket has locked onto a target, it will not let go unless the target
			-- is destroyed.
			--
			-- However, when it scans for targets, it will prefer a decoy over the player.


			-- If we have a target, check that it wasn't destroyed
			if( self.target and self.target.removeSelf == nil ) then
				-- Was destroyed.  Clear it
				self.target = nil
			end
				
			-- If we don't have a target at this point, try to acquire a nearby decoy
			if( not self._target ) then
				ssk.actions.target.acquireNearest( self, { targets = common.decoys, maxDist = common.rocketAcquireDistance } )
			end

			-- If we don't have a target at this point, set the target as the player if it is close enought
			if( not self._target ) then
				ssk.actions.target.acquireNearest( self, { targets = {common.currentPlayer}, maxDist = common.rocketAcquireDistance } )
			end


			-- If we have a target, try to face it
			if( self._target ) then
				--ssk.actions.face( self, { target = common.currentPlayer, rate = 120 } )
				ssk.actions.face( self, { target = self._target,  rate = 120 } )

				if( common.debugEn or common.turretDebug ) then
					ssk.actions.target.drawDebugLine( self, { parent = self.parent } )
					ssk.actions.target.drawDebugAngleDistanceLabel( self, { parent = self.parent, yOffset = 30 } )
				end
			end

			-- Thrust forward and lay a particle trail
			ssk.actions.movep.forward( self, { rate = common.rocketSpeed } )
    		utils.rocketTrail( self, 6 )	
		end
		timer.performWithDelay( 350, function() Runtime:addEventListener( "enterFrame", rocket ) end )


		-- Add a basic collision listener and dispatch and event when it occurs, then remove this object from the world
		--
		rocket.ignorePlatforms = true -- Initially, ignore collisions with platforms
		rocket.collision = function( self, event )
			local other = event.other
			if( other.isPlayer ) then
				print("GOTCHA!")
				post( "onSFX", { sfx = "bad" } )
				-- Tip: We're only handling the first phase of the collision, so remove listener right away.
				self:removeEventListener( "collision" )
				timer.performWithDelay( 100, function()  Runtime:dispatchEvent( { name = "onReloadLevel" } )  end )
			
			elseif( other.isDecoy ) then
				common.decoys[other] = nil
				display.remove( other )
				display.remove( self )
			
			elseif( not self.ignorePlatforms ) then
				display.remove( self )
			
			end
			return true
		end
		rocket:addEventListener( "collision" )
		
		timer.performWithDelay( common.rocketLifetime, function() display.remove( rocket )  end )
		timer.performWithDelay( 500, function()   rocket.ignorePlatforms = false	end )
		timer.performWithDelay( common.rocketFireTime, self )
	end
	--turret:timer()  
	timer.performWithDelay( 500, turret )


	-- Return a reference to this object 
	--
	return aPiece
end

return builder