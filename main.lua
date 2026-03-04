-- run.lua - Love2D 0.10.2 game with proper animations
-- Fixed: enemy walk animation, vesper attacks, arrow projectiles, mouse interaction

WINDOW_WIDTH = 1280
WINDOW_HEIGHT = 720
DEBUG_PANEL_WIDTH = 420
FULL_WIDTH = WINDOW_WIDTH + DEBUG_PANEL_WIDTH
DEBUG_PANEL_X = WINDOW_WIDTH  -- Panel starts at right edge
VESPER_SCALE = 1.05
ENEMY_SCALE = 1.0
ENEMY_SPAWN_INTERVAL = 2.0
VESPER_ATTACK_RANGE = 300

-- Debug panel slider values (multipliers)
DEBUG = {
    -- Multipliers (1.0 = default)
    vesperAttackPower = 1.0,
    vesperAttackRange = 1.0,
    vesperAttackSpeed = 1.0,
    vesperSkill1Damage = 1.0,
    vesperSkill2Damage = 1.0,
    vesperMoveSpeed = 1.0,
    enemyArmor = 1.0,
    enemySpeed = 1.0,
    enemySpawnSpeed = 1.0,
    -- UI state
    activeSlider = nil,
    draggingSlider = nil
}

-- Animations
ANIMATIONS = {
    idle = {from = 1, to = 18, fps = 10},
    walk = {from = 19, to = 36, fps = 15},
    ranged_attack = {from = 91, to = 110, fps = 15},
    ricochet = {from = 141, to = 169, fps = 15},
    arrow_storm = {from = 91, to = 110, fps = 15}
}

-- Enemy skeleton animation system
-- Abomination uses skeleton-based animation with multiple body parts
ENEMY_SKELETON = {
    fps = 30,
    loaded = false,
    parts = {},  -- {name = {quad, w, h, image}}
    animations = {
        idle = {frameStart = 1, frameCount = 1},
        walk = {frameStart = 40, frameCount = 32}  -- 32 frames walk cycle
    }
}

VESPER = {
    x = WINDOW_WIDTH / 2,
    y = WINDOW_HEIGHT / 2,
    hp = 160, maxHp = 160,
    attackMin = 240, attackMax = 360,
    attackCooldown = 1.0,
    state = "idle",
    animFrame = 1, animTimer = 0,
    facing = 1,
    skills = {
        [1] = {name = "Ricochet", cooldown = 20, cooldownTimer = 0, ready = true, anim = "ranged_attack", damage = 150},
        [2] = {name = "Arrow Storm", cooldown = 60, cooldownTimer = 0, ready = true, anim = "arrow_storm", damage = 200}
    }
}

ENEMY_TEMPLATE = {hp = 900, armor = 0.5, speed = 20}

-- Enemy animations
ENEMY_ANIM = {
    idle = {from = 1, to = 1, fps = 2},
    walk = {from = 2, to = 33, fps = 10}
}

bgImage, heroImage, enemyImage = nil, nil, nil
heroFrames = {}
enemyFrames = {}
arrowFrames = {}
hitFxFrames = {}
ricochetFxFrames = {}

enemies = {}
projectiles = {}
attackEffects = {}
arrowStormParticles = {}
enemySpawnTimer = 0

mouseOnHero = false
mouseDown = false
gamePaused = false

-- Keyboard state for WASD movement
keysDown = {w = false, a = false, s = false, d = false}

function log(msg)
    print(os.date("%H:%M:%S") .. " " .. msg)
end

-- Load hero frames
function loadHeroFrames()
    local frames = {}
    local chunk = loadfile("assets/images/go_hero_vesper.lua")
    if not chunk then return frames end
    
    local data = chunk()
    local validFrames = {idle = {}, walk = {}, ranged_attack = {}, ricochet = {}, arrow_storm = {}}
    
    for k, v in pairs(data) do
        if type(k) == "string" and string.match(k, "^hero_vesper_vesper_%d%d%d%d$") then
            local n = tonumber(string.match(k, "%d%d%d%d$"))
            if n and v and v.f_quad then
                local qx, qy, qw, qh = unpack(v.f_quad)
                local aw, ah = unpack(v.a_size)
                local quad = love.graphics.newQuad(qx, qy, qw, qh, aw, ah)
                frames[n] = {quad = quad, w = qw, h = qh}
                
                -- Track which animation this frame belongs to
                for animName, anim in pairs(ANIMATIONS) do
                    if n >= anim.from and n <= anim.to then
                        table.insert(validFrames[animName], n)
                    end
                end
            end
        end
    end
    
    frames.validFrames = validFrames
    log("Hero frames: " .. #frames)
    return frames
end

-- Get Vesper animation frame safely
function getVesperFrame()
    local anim = ANIMATIONS[VESPER.state] or ANIMATIONS.idle
    local validList = heroFrames.validFrames[VESPER.state]
    
    if not validList or #validList == 0 then
        -- Fallback: try any frame in range
        validList = {}
        for i = anim.from, anim.to do
            table.insert(validList, i)
        end
    end
    
    if #validList == 0 then return heroFrames[1] end
    
    local frameIndex = ((VESPER.animFrame - 1) % #validList) + 1
    local frameNum = validList[frameIndex]
    
    return heroFrames[frameNum]
end

-- Load enemy frames
function loadEnemyFrames()
    local frames = {}
    local chunk = loadfile("assets/images/go_enemies_terrain_2.lua")
    if not chunk then return frames end
    
    local data = chunk()
    -- Load up to 210 frames for unblinded_abomination
    for i = 1, 210 do
        local name = string.format("unblinded_abomination_unblinded_abomination_%04d", i)
        local v = data[name]
        if not v then break end
        
        local qx, qy, qw, qh = unpack(v.f_quad)
        local aw, ah = unpack(v.a_size)
        local quad = love.graphics.newQuad(qx, qy, qw, qh, aw, ah)
        frames[i] = {quad = quad, w = qw, h = qh, qx = qx, qy = qy}
    end
    log("Enemy frames: " .. #frames)
    return frames
end

-- Load enemy sprite frames (for sprite sheet animation)
function loadEnemySpriteFrames()
    local frames = {}
    local chunk = loadfile("assets/images/go_enemies_terrain_2.lua")
    if not chunk then 
        log("No sprite data")
        return frames 
    end
    local data = chunk()
    
    -- Load frames for unblinded_abomination (idle=1, walk=2-33)
    -- Pre-compute valid frame indices for each animation state
    local validFrames = {idle = {}, walk = {}}
    local loaded = 0
    
    for i = 1, 33 do
        local name = string.format("unblinded_abomination_unblinded_abomination_%04d", i)
        local v = data[name]
        if v then
            local qx, qy, qw, qh = unpack(v.f_quad)
            local aw, ah = unpack(v.a_size)
            local quad = love.graphics.newQuad(qx, qy, qw, qh, aw, ah)
            frames[i] = {quad = quad, w = qw, h = qh}
            loaded = loaded + 1
            
            -- Track valid frames for each animation
            if i == 1 then
                table.insert(validFrames.idle, i)
            else
                table.insert(validFrames.walk, i)
            end
        end
    end
    
    -- Store valid frame list for animation
    frames.validFrames = validFrames
    log("Loaded " .. loaded .. " enemy frames, idle:" .. #validFrames.idle .. " walk:" .. #validFrames.walk)
    return frames
end

-- Get the correct frame for enemy animation
function getEnemyAnimationFrame(e)
    local validList = enemyFrames.validFrames[e.state]
    if not validList or #validList == 0 then
        -- Fallback
        validList = enemyFrames.validFrames.idle
    end
    
    -- Calculate frame index within valid frames
    local frameIndex = ((e.frame - 1) % #validList) + 1
    local frameNum = validList[frameIndex]
    
    return enemyFrames[frameNum]
end

-- Create simplified exo data for testing
function createSimplifiedExo()
    local exo = {fps = 30, animations = {}}
    
    -- Create idle animation (1 frame with all parts)
    local idleAnim = {name = "idle", frames = {}}
    idleAnim.frames[1] = {
        parts = {
            {name = "Abomination2_asst_abomination2_shadow", xform = {sx = 1, sy = 1, r = 0, x = -15, y = -5}},
            {name = "Abomination2_asst_abomination2_torso", xform = {sx = 0.85, sy = 0.85, r = 0, x = 1, y = -24}},
            {name = "Abomination2_asst_abomination2_legs", xform = {sx = 0.9, sy = 0.94, r = 0, x = 0, y = -5}},
            {name = "Abomination2_asst_abomination2_arm", xform = {sx = 0.85, sy = 0.85, r = 0.1, x = -15, y = -21}},
            {name = "Abomination2_asst_abomination2_arm2", xform = {sx = 1, sy = 1, r = 0, x = 24, y = -23}},
            {name = "Abomination2_asst_abomination2_head", xform = {sx = 0.9, sy = 0.9, r = 0, x = 9, y = -26}}
        }
    }
    exo.animations[#exo.animations + 1] = idleAnim
    
    -- Create walk animation (8 simplified frames)
    local walkAnim = {name = "walk", frames = {}}
    for f = 1, 8 do
        local frame = {parts = {}}
        -- Animate legs
        local legOffset = math.sin((f - 1) * math.pi / 4) * 5
        local armOffset = math.cos((f - 1) * math.pi / 4) * 8
        
        frame.parts[#frame.parts + 1] = {name = "Abomination2_asst_abomination2_shadow", xform = {sx = 1.1, sy = 0.97, r = 0, x = -15, y = -5}}
        frame.parts[#frame.parts + 1] = {name = "Abomination2_asst_abomination2_torso", xform = {sx = 0.85, sy = 0.85, r = 0, x = 1 + legOffset*0.2, y = -24}}
        frame.parts[#frame.parts + 1] = {name = "Abomination2_asst_abomination2_legs", xform = {sx = 0.9, sy = 0.94, r = 0, x = legOffset, y = -5}}
        frame.parts[#frame.parts + 1] = {name = "Abomination2_asst_abomination2_arm", xform = {sx = 0.85, sy = 0.85, r = armOffset * 0.05, x = -15 + armOffset, y = -21}}
        frame.parts[#frame.parts + 1] = {name = "Abomination2_asst_abomination2_arm2", xform = {sx = 1, sy = 1, r = 0, x = 24 - armOffset, y = -23}}
        frame.parts[#frame.parts + 1] = {name = "Abomination2_asst_abomination2_head", xform = {sx = 0.9, sy = 0.9, r = 0, x = 9 + legOffset*0.1, y = -26}}
        
        walkAnim.frames[#walkAnim.frames + 1] = frame
    end
    exo.animations[#exo.animations + 1] = walkAnim
    
    return exo
end

-- Get skeleton animation frame
function getSkeletonFrame(skeleton, animName, frameNum)
    if not skeleton or not skeleton.exo then return nil end
    
    for _, anim in ipairs(skeleton.exo.animations) do
        if anim.name == animName then
            local idx = ((frameNum - 1) % #anim.frames) + 1
            return anim.frames[idx]
        end
    end
    return nil
end

-- Draw skeleton at position
function drawSkeleton(skeleton, animName, frameNum, x, y, facing, scale)
    scale = scale or ENEMY_SCALE
    facing = facing or 1
    
    local frame = getSkeletonFrame(skeleton, animName, frameNum)
    if not frame then 
        -- Debug: draw placeholder if no frame
        love.graphics.setColor(255, 100, 100, 200)
        love.graphics.rectangle("fill", x - 30 * scale, y - 60 * scale, 60 * scale, 80 * scale)
        love.graphics.setColor(255, 255, 255)
        return 
    end
    
    local drawn = false
    for _, part in ipairs(frame.parts) do
        local partData = skeleton.parts[part.name]
        if partData and partData.quad then
            local tf = part.xform
            local sx = (tf.sx or 1) * scale * facing
            local sy = (tf.sy or 1) * scale
            local rot = tf.r or 0
            local px = x + (tf.x or 0) * scale
            local py = y + (tf.y or 0) * scale
            
            love.graphics.draw(partData.image, partData.quad, px, py, rot, sx, sy)
            drawn = true
        end
    end
    
    -- Debug: if no parts found, draw placeholder
    if not drawn then
        love.graphics.setColor(255, 100, 100, 200)
        love.graphics.rectangle("fill", x - 30 * scale, y - 60 * scale, 60 * scale, 80 * scale)
        love.graphics.setColor(255, 255, 255)
    end
end

-- Load arrow frame
function loadArrowFrames()
    local frames = {}
    local chunk = loadfile("assets/images/go_hero_vesper.lua")
    if not chunk then return frames end
    
    local data = chunk()
    local v = data.hero_vesper_arrow
    if v then
        local qx, qy, qw, qh = unpack(v.f_quad)
        local aw, ah = unpack(v.a_size)
        local quad = love.graphics.newQuad(qx, qy, qw, qh, aw, ah)
        frames[1] = {quad = quad, w = qw, h = qh}
    end
    log("Arrow frames: " .. #frames)
    return frames
end

-- Load hit FX
function loadHitFx()
    local frames = {}
    local chunk = loadfile("assets/images/go_hero_vesper.lua")
    if not chunk then return frames end
    
    local data = chunk()
    for i = 1, 10 do
        local name = string.format("hero_vesper_attack_hit_%04d", i * 2 - 1)
        local v = data[name]
        if not v then break end
        local qx, qy, qw, qh = unpack(v.f_quad)
        local aw, ah = unpack(v.a_size)
        local quad = love.graphics.newQuad(qx, qy, qw, qh, aw, ah)
        frames[#frames + 1] = {quad = quad, w = qw, h = qh}
    end
    log("Hit FX: " .. #frames)
    return frames
end

function spawnEnemy()
    local side = math.random(1, 4)
    local x, y
    if side == 1 then x = math.random(100, WINDOW_WIDTH-100); y = -50
    elseif side == 2 then x = WINDOW_WIDTH+50; y = math.random(100, WINDOW_HEIGHT-100)
    elseif side == 3 then x = math.random(100, WINDOW_WIDTH-100); y = WINDOW_HEIGHT+50
    else x = -50; y = math.random(100, WINDOW_HEIGHT-100) end
    
    enemies[#enemies + 1] = {
        x = x, y = y,
        state = "idle",
        frame = 1, frameTimer = 0,
        alive = true,
        hp = ENEMY_TEMPLATE.hp, maxHp = ENEMY_TEMPLATE.hp,
        armor = (DEFAULT_VALUES.enemyArmor or 0.5) * DEBUG.enemyArmor,
        speed = (DEFAULT_VALUES.enemySpeed or 20) * DEBUG.enemySpeed,
        facing = x < WINDOW_WIDTH/2 and 1 or -1
    }
end

function spawnArrow(target, isSkill1, isSkill2)
    if #arrowFrames == 0 then return end
    local startX = VESPER.x
    local startY = VESPER.y
    local targetX = target.x
    local targetY = target.y
    
    -- Calculate flight distance and time
    local dist = math.sqrt((targetX - startX)^2 + (targetY - startY)^2)
    local speed = 500
    local totalTime = dist / speed  -- Time to reach target
    
    -- Calculate damage based on type
    local baseDamage = (VESPER.attackMin + VESPER.attackMax) / 2
    if isSkill1 then
        baseDamage = VESPER.skills[1].damage
    elseif isSkill2 then
        baseDamage = VESPER.skills[2].damage
    end
    
    projectiles[#projectiles + 1] = {
        x = startX, y = startY,
        startX = startX, startY = startY,
        targetX = targetX, targetY = targetY,
        speed = speed,
        flightTime = 0,
        totalTime = totalTime,
        rotation = 0,
        alive = true,
        damage = baseDamage,
        isSkill1 = isSkill1,
        isSkill2 = isSkill2,
        target = target
    }
end

function setVesperState(newState)
    if VESPER.state ~= newState then
        VESPER.state = newState
        VESPER.animFrame = 1
        VESPER.animTimer = 0
    end
end

function activateSkill(idx)
    local skill = VESPER.skills[idx]
    if not skill or not skill.ready then return end
    
    log("Skill: " .. skill.name)
    skill.ready = false
    skill.cooldownTimer = skill.cooldown
    setVesperState(skill.anim)
    
    if idx == 1 then
        -- Arrow Storm: 81 arrows (9x9 grid), vertical downward, AOE in attack range
        local attackRange = (DEFAULT_VALUES.vesperAttackRange or 300) * DEBUG.vesperAttackRange
        local gridSize = 9
        local spacing = attackRange * 2 / gridSize
        
        for i = 1, 81 do
            -- Calculate grid position (9x9)
            local row = math.floor((i-1) / gridSize)
            local col = (i-1) % gridSize
            
            -- Random offset within cell
            local offsetX = math.random() * spacing * 0.6 - spacing * 0.3
            local offsetY = math.random() * spacing * 0.6 - spacing * 0.3
            
            -- Target position within attack range circle
            local angle = math.random() * math.pi * 2
            local radius = math.sqrt(math.random()) * attackRange
            local targetX = VESPER.x + math.cos(angle) * radius
            local targetY = VESPER.y + math.sin(angle) * radius
            
            -- Spawn arrow falling from above
            local startX = targetX
            local startY = VESPER.y - 500 - math.random(200, 400)
            
            local dist = math.sqrt((targetX - startX)^2 + (targetY - startY)^2)
            local speed = 600
            local totalTime = dist / speed
            
            projectiles[#projectiles + 1] = {
                x = startX, y = startY,
                startX = startX, startY = startY,
                targetX = targetX, targetY = targetY,
                speed = speed,
                flightTime = 0,
                totalTime = totalTime,
                rotation = math.pi/2,  -- Point vertically downward
                alive = true,
                damage = VESPER.skills[1].damage,
                isSkill1 = true,
                isSkill2 = false,
                isAOE = true,  -- AOE damage flag
                aoeRadius = 80  -- AOE radius
            }
        end
    elseif idx == 2 then
        for _, e in ipairs(enemies) do
            if e and e.alive then spawnArrow(e, false, true) end  -- isSkill2 = true
        end
    end
end

function love.load()
    log("=== Loading ===")
    
    -- Load default values from default.json
    DEFAULT_VALUES = {}
    local success, result = pcall(function()
        local file = love.filesystem.newFile("default.json")
        if file:open("r") then
            local content = file:read()
            file:close()
            if content then
                -- Parse JSON manually (simple key-value pairs)
                for k, v in string.gmatch(content, '"(%w+)":%s*([%d.]+)') do
                    DEFAULT_VALUES[k] = tonumber(v)
                end
            end
        end
    end)
    
    -- Apply loaded defaults (set multipliers to 1.0, store defaults for calculations)
    -- DEBUG stores multipliers, DEFAULT_VALUES stores base values
    DEBUG.vesperAttackPower = 1.0
    DEBUG.vesperAttackRange = 1.0
    DEBUG.vesperAttackSpeed = 1.0
    DEBUG.vesperSkill1Damage = 1.0
    DEBUG.vesperSkill2Damage = 1.0
    DEBUG.vesperMoveSpeed = 1.0
    DEBUG.enemyArmor = 1.0
    DEBUG.enemySpeed = 1.0
    DEBUG.enemySpawnSpeed = 1.0
    
    if DEFAULT_VALUES.skill1Cooldown then VESPER.skills[1].cooldown = DEFAULT_VALUES.skill1Cooldown end
    if DEFAULT_VALUES.skill2Cooldown then VESPER.skills[2].cooldown = DEFAULT_VALUES.skill2Cooldown end
    
    love.window.setMode(FULL_WIDTH, WINDOW_HEIGHT, {centered = true, resizable = false})
    love.window.setTitle("Vesper vs Enemies")
    
    bgImage = love.graphics.newImage("assets/images/go_stage09_bg-1.png")
    bgImage:setFilter("linear", "linear")
    
    heroImage = love.graphics.newImage("assets/images/go_hero_vesper-1.png")
    heroImage:setFilter("linear", "linear")
    
    enemyImage = love.graphics.newImage("assets/images/go_enemies_terrain_2-1.png")
    enemyImage:setFilter("linear", "linear")
    
    heroFrames = loadHeroFrames()
    enemyFrames = loadEnemySpriteFrames()  -- Use sprite sheet frames
    arrowFrames = loadArrowFrames()
    hitFxFrames = loadHitFx()
    
    log("=== Ready ===")
end

function love.update(dt)
    if gamePaused then return end
    
    -- Skill cooldowns
    for i = 1, 2 do
        local s = VESPER.skills[i]
        if not s.ready then
            s.cooldownTimer = s.cooldownTimer - dt
            if s.cooldownTimer <= 0 then
                s.ready = true
                s.cooldownTimer = 0
                log(s.name .. " ready")
            end
        end
    end
    
    -- WASD movement
    local moveSpeed = (DEFAULT_VALUES.vesperMoveSpeed or 200) * DEBUG.vesperMoveSpeed
    local isMoving = false
    local moveX, moveY = 0, 0
    
    if keysDown.w then moveY = moveY - 1 end
    if keysDown.s then moveY = moveY + 1 end
    if keysDown.a then moveX = moveX - 1 end
    if keysDown.d then moveX = moveX + 1 end
    
    if moveX ~= 0 or moveY ~= 0 then
        isMoving = true
        -- Normalize diagonal movement
        local len = math.sqrt(moveX*moveX + moveY*moveY)
        moveX = moveX / len
        moveY = moveY / len
        
        VESPER.x = VESPER.x + moveX * moveSpeed * dt
        VESPER.y = VESPER.y + moveY * moveSpeed * dt
        
        -- Clamp to game area
        VESPER.x = math.max(50, math.min(WINDOW_WIDTH - 50, VESPER.x))
        VESPER.y = math.max(50, math.min(WINDOW_HEIGHT - 50, VESPER.y))
        
        -- Update facing direction based on movement keys
        -- Press A → facing=-1, Press D → facing=1
        if moveX > 0.1 then VESPER.facing = 1
        elseif moveX < -0.1 then VESPER.facing = -1
        end
    end
    
    -- Update Vesper state based on movement
    if isMoving and VESPER.state == "idle" then
        setVesperState("walk")
    elseif not isMoving and VESPER.state == "walk" then
        setVesperState("idle")
    end
    
    -- Vesper animation - use valid frame count
    local validList = heroFrames.validFrames[VESPER.state]
    if not validList then
        validList = heroFrames.validFrames.idle
    end
    
    local anim = ANIMATIONS[VESPER.state] or ANIMATIONS.idle
    -- Apply attack speed multiplier for attack animations
    local speedMult = 1.0
    if VESPER.state == "ranged_attack" or VESPER.state == "idle" then
        speedMult = DEBUG.vesperAttackSpeed
    end
    local effectiveFps = anim.fps * speedMult
    
    VESPER.animTimer = VESPER.animTimer + dt
    if VESPER.animTimer >= 1/effectiveFps then
        VESPER.animTimer = VESPER.animTimer - 1/effectiveFps
        VESPER.animFrame = VESPER.animFrame + 1
        -- Loop through valid frames
        if VESPER.animFrame > #validList then
            if VESPER.state == "ranged_attack" or VESPER.state == "ricochet" or VESPER.state == "arrow_storm" then
                setVesperState("idle")
                VESPER.animFrame = 1
            else
                VESPER.animFrame = 1
            end
        end
    end
    
    -- Ensure animFrame is always valid
    if VESPER.animFrame < 1 then VESPER.animFrame = 1 end
    
    -- Spawn arrow at attack frame 3
    if VESPER.state == "ranged_attack" and VESPER.animFrame == 3 then
        -- Find nearest enemy for arrow (within range)
        local attackRange = (DEFAULT_VALUES.vesperAttackRange or 300) * DEBUG.vesperAttackRange
        local nearestDist = attackRange + 1
        local nearestEnemy = nil
        for _, e in ipairs(enemies) do
            if e and e.alive then
                local dist = math.sqrt((e.x-VESPER.x)^2 + (e.y-VESPER.y)^2)
                if dist <= attackRange and dist < nearestDist then
                    nearestDist = dist
                    nearestEnemy = e
                end
            end
        end
        if nearestEnemy then
            spawnArrow(nearestEnemy)
            -- Attack facing: enemy.x < vesper.x → facing=-1
            VESPER.facing = nearestEnemy.x < VESPER.x and -1 or 1
        end
    end
    
    -- Auto attack - target nearest enemy within range
    if VESPER.state == "idle" then
        local attackRange = (DEFAULT_VALUES.vesperAttackRange or 300) * DEBUG.vesperAttackRange
        local nearestDist = attackRange + 1
        local nearestEnemy = nil
        for _, e in ipairs(enemies) do
            if e and e.alive then
                local dist = math.sqrt((e.x-VESPER.x)^2 + (e.y-VESPER.y)^2)
                if dist <= attackRange and dist < nearestDist then
                    nearestDist = dist
                    nearestEnemy = e
                end
            end
        end
        if nearestEnemy then
            setVesperState("ranged_attack")
        end
    end
    
    -- Spawn enemies
    enemySpawnTimer = enemySpawnTimer + dt
    if enemySpawnTimer >= (DEFAULT_VALUES.enemySpawnSpeed or 2.0) / DEBUG.enemySpawnSpeed then
        enemySpawnTimer = 0
        spawnEnemy()
    end
    
    -- Update enemies
    for i = #enemies, 1, -1 do
        local e = enemies[i]
        if not e or not e.alive then
            table.remove(enemies, i)
        else
            local dx = VESPER.x - e.x
            local dy = VESPER.y - e.y
            local dist = math.sqrt(dx*dx + dy*dy)
            
            e.facing = e.x < VESPER.x and 1 or -1
            
            local oldState = e.state
            if dist > 50 then
                e.state = "walk"
                e.x = e.x + (dx/dist) * e.speed * dt
                e.y = e.y + (dy/dist) * e.speed * dt
            else
                e.state = "idle"
            end
            
            -- Reset frame when state changes
            if e.state ~= oldState then
                e.frame = 1
                e.frameTimer = 0
            end
            
            -- Enemy animation - use valid frame count
            local validList = enemyFrames.validFrames[e.state]
            if not validList then validList = enemyFrames.validFrames.idle end
            
            e.frameTimer = e.frameTimer + dt
            local eanim = ENEMY_ANIM[e.state] or ENEMY_ANIM.idle
            if e.frameTimer >= 1/eanim.fps then
                e.frameTimer = e.frameTimer - 1/eanim.fps
                e.frame = e.frame + 1
                -- Loop through valid frames only
                if e.frame > #validList then e.frame = 1 end
            end
        end
    end
    
    -- Update projectiles (with parabolic trajectory and trail)
    for i = #projectiles, 1, -1 do
        local p = projectiles[i]
        if not p then
            table.remove(projectiles, i)
        else
            -- Update flight time
            p.flightTime = (p.flightTime or 0) + dt
            
            -- Parabolic trajectory parameters
            local gravity = 500  -- Gravity strength
            local totalTime = p.totalTime or 1.0  -- Total flight duration
            
            -- Calculate current position on parabola
            local t = p.flightTime / totalTime
            if t > 1 then t = 1 end
            
            local startX, startY = p.startX, p.startY
            local targetX, targetY = p.targetX, p.targetY
            
            -- Linear interpolation for X
            local x = startX + (targetX - startX) * t
            -- Parabolic interpolation for Y (with arc)
            local baseY = startY + (targetY - startY) * t
            local arcHeight = 150  -- Arrow arc height
            local arc = arcHeight * 4 * t * (1 - t)  -- Parabolic arc
            local y = baseY - arc
            
            p.x = x
            p.y = y
            
            -- Calculate rotation - arrow always tangent to parabola
            -- Derivative of parabola: dy/dt = (targetY - startY) - 4*arcHeight + 8*arcHeight*t
            local dx = targetX - startX
            local dy_dt = (targetY - startY) - 4 * arcHeight + 8 * arcHeight * t
            p.rotation = math.atan2(dy_dt, dx)
            
            -- Spawn trail particle
            if math.random() < 0.7 then  -- 70% chance per frame
                table.insert(arrowStormParticles, {
                    x = x + math.random(-5, 5),
                    y = y + math.random(-5, 5),
                    angle = p.rotation,
                    life = 0.3,
                    maxLife = 0.3,
                    alpha = 150
                })
            end
            
            -- Check if hit target
            local distToTarget = math.sqrt((p.x - p.targetX)^2 + (p.y - p.targetY)^2)
            if distToTarget < 20 or t >= 1 then
                -- Hit
                local baseDmg = (DEFAULT_VALUES.vesperAttackPower or 300) * DEBUG.vesperAttackPower
                if p.isSkill1 then baseDmg = (DEFAULT_VALUES.vesperSkill1Damage or 150) * DEBUG.vesperSkill1Damage end
                if p.isSkill2 then baseDmg = (DEFAULT_VALUES.vesperSkill2Damage or 200) * DEBUG.vesperSkill2Damage end
                
                -- AOE damage for skill 1
                if p.isAOE then
                    local aoeRadius = p.aoeRadius or 80
                    for _, e in ipairs(enemies) do
                        if e and e.alive then
                            local distToArrow = math.sqrt((e.x - p.x)^2 + (e.y - p.y)^2)
                            if distToArrow <= aoeRadius then
                                local enemyArmor = math.min(1, e.armor or 0.5)
                                local dmg = math.floor(baseDmg * (1 - enemyArmor))
                                e.hp = e.hp - dmg
                                attackEffects[#attackEffects + 1] = {
                                    x = e.x, y = e.y,
                                    timer = 0.3, frame = 1, fxType = "hit"
                                }
                                if e.hp <= 0 then e.alive = false end
                            end
                        end
                    end
                else
                    -- Single target damage
                    if p.target and p.target.alive then
                        local enemyArmor = math.min(1, p.target.armor or 0.5)
                        local dmg = math.floor(baseDmg * (1 - enemyArmor))
                        p.target.hp = p.target.hp - dmg
                        attackEffects[#attackEffects + 1] = {
                            x = p.target.x, y = p.target.y,
                            timer = 0.3, frame = 1, fxType = "hit"
                        }
                        if p.target.hp <= 0 then p.target.alive = false end
                    end
                end
                p.alive = false
            end
            
            if not p.alive then table.remove(projectiles, i) end
        end
    end
    
    -- Update trail particles
    for i = #arrowStormParticles, 1, -1 do
        local p = arrowStormParticles[i]
        if not p.maxLife then p.maxLife = p.life end
        p.life = p.life - dt
        p.alpha = math.floor(255 * (p.life / p.maxLife))
        if p.life <= 0 then
            table.remove(arrowStormParticles, i)
        end
    end
    
    -- Update effects
    for i = #attackEffects, 1, -1
    do
        local fx = attackEffects[i]
        fx.timer = fx.timer - dt
        fx.frame = fx.frame + 1
        if fx.timer <= 0 then table.remove(attackEffects, i) end
    end
    
    -- Update arrow storm particles
    for i = #arrowStormParticles, 1, -1
    do
        local p = arrowStormParticles[i]
        if p.speedY then
            p.y = p.y + p.speedY * dt
        end
        p.life = p.life - dt
        if p.life <= 0 or (p.speedY and p.y > WINDOW_HEIGHT + 50) then
            table.remove(arrowStormParticles, i)
        end
    end
end

function love.draw()
    -- Draw "PAUSED" text if game is paused
    if gamePaused then
        love.graphics.setColor(0, 0, 0, 150)
        love.graphics.rectangle("fill", 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT)
        love.graphics.setColor(255, 255, 255)
        love.graphics.print("PAUSED", WINDOW_WIDTH/2 - 30, WINDOW_HEIGHT/2)
    end
    
    -- Background
    if bgImage then
        love.graphics.draw(bgImage, 0, 0, 0, WINDOW_WIDTH/bgImage:getWidth(), WINDOW_HEIGHT/bgImage:getHeight())
    else
        love.graphics.setColor(20, 20, 40)
        love.graphics.rectangle("fill", 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT)
    end
    love.graphics.setColor(255, 255, 255)
    
    -- Enemies
    for _, e in ipairs(enemies) do
        if e and e.alive then
            local eanim = ENEMY_ANIM[e.state] or ENEMY_ANIM.idle
            -- Use safe animation frame lookup
            local f = getEnemyAnimationFrame(e)
            
            if f and f.quad then
                love.graphics.setColor(255, 255, 255)
                -- Draw at center with center-based flip
                love.graphics.draw(enemyImage, f.quad, e.x, e.y, 0, ENEMY_SCALE*e.facing, ENEMY_SCALE, f.w/2, f.h/2)
                
                local barW, barH = 50, 8
                local barY = e.y - f.h * ENEMY_SCALE - 10
                local barX = e.x - barW/2
                local hpRatio = e.hp / e.maxHp
                love.graphics.setColor(30, 30, 30)
                love.graphics.rectangle("fill", barX, barY, barW, barH)
                love.graphics.setColor(200, 50, 50)
                love.graphics.rectangle("fill", barX, barY, barW * hpRatio, barH)
                love.graphics.setColor(255, 255, 255)
            end
        end
    end
    
    -- Projectiles (arrows) with rotation
    for _, p in ipairs(projectiles) do
        if p and #arrowFrames > 0 then
            local f = arrowFrames[1]
            love.graphics.draw(heroImage, f.quad, p.x, p.y, p.rotation or 0, 1, 1, f.w/2, f.h/2)
        end
    end
    
    -- Arrow storm particles (trail effect)
    for _, p in ipairs(arrowStormParticles) do
        if #arrowFrames > 0 and p.alpha > 0 then
            local f = arrowFrames[1]
            love.graphics.setColor(255, 255, 255, p.alpha)
            love.graphics.draw(heroImage, f.quad, p.x, p.y, p.angle, 0.5, 0.5, f.w/2, f.h/2)
            love.graphics.setColor(255, 255, 255)
        end
    end
    
    -- Hit effects
    for _, fx in ipairs(attackEffects) do
        if fx and #hitFxFrames > 0 then
            local fi = math.min(fx.frame, #hitFxFrames)
            local f = hitFxFrames[fi]
            if f then
                love.graphics.setColor(255, 255, 255, 200)
                love.graphics.draw(heroImage, f.quad, fx.x - f.w, fx.y - f.h, 0, 1.5, 1.5)
                love.graphics.setColor(255, 255, 255)
            end
        end
    end
    
    -- Vesper - use safe frame lookup
    local f = getVesperFrame()
    
    if f and heroImage then
        love.graphics.setColor(255, 255, 255)
        -- Draw at center with center-based flip
        love.graphics.draw(heroImage, f.quad, VESPER.x, VESPER.y, 0, VESPER_SCALE*VESPER.facing, VESPER_SCALE, f.w/2, f.h/2)
    end
    love.graphics.setColor(255, 255, 255)
    
    -- Attack range circle when mouse on hero
    if mouseOnHero and mouseDown then
        local attackRange = (DEFAULT_VALUES.vesperAttackRange or 300) * DEBUG.vesperAttackRange
        love.graphics.setColor(255, 255, 255, 80)
        love.graphics.circle("fill", VESPER.x, VESPER.y, attackRange)
        love.graphics.setColor(255, 255, 255, 180)
        love.graphics.circle("line", VESPER.x, VESPER.y, attackRange)
        love.graphics.setColor(255, 255, 255)
    end
    
    -- Hero HP
    love.graphics.setColor(30, 30, 30)
    love.graphics.rectangle("fill", 10, WINDOW_HEIGHT-30, 200, 20)
    love.graphics.setColor(50, 200, 50)
    love.graphics.rectangle("fill", 10, WINDOW_HEIGHT-30, 200 * (VESPER.hp/VESPER.maxHp), 20)
    love.graphics.setColor(255, 255, 255)
    love.graphics.print(string.format("HP: %d/%d", VESPER.hp, VESPER.maxHp), 15, WINDOW_HEIGHT-28)
    
    -- Skill buttons
    local btnY = WINDOW_HEIGHT - 100
    for i = 1, 2 do
        local s = VESPER.skills[i]
        local bx = 10 + (i-1)*60
        
        love.graphics.setColor(s.ready and {50,150,50} or {100,100,100})
        love.graphics.rectangle("fill", bx, btnY, 50, 50)
        
        if not s.ready then
            love.graphics.setColor(0, 0, 0, 150)
            love.graphics.rectangle("fill", bx, btnY + 50*(1-s.cooldownTimer/s.cooldown), 50, 50*s.cooldownTimer/s.cooldown)
        end
        
        love.graphics.setColor(200, 200, 200)
        love.graphics.rectangle("line", bx, btnY, 50, 50)
        love.graphics.setColor(255, 255, 255)
        love.graphics.print(tostring(i), bx+5, btnY+5)
        love.graphics.print(s.name, bx, btnY+55)
        
        -- Show cooldown timer if not ready (accurate to 0.1s)
        if not s.ready then
            love.graphics.setColor(255, 50, 50)
            love.graphics.print(string.format("%.1f", s.cooldownTimer), bx+15, btnY+25)
        end
    end
    
    -- Debug panel
    drawDebugPanel()
    
    -- Debug info
    love.graphics.setColor(255, 255, 255)
    love.graphics.print(string.format("Enemies: %d", #enemies), 10, 10)
    love.graphics.print(string.format("E Frames: %d", #enemyFrames), 10, 30)
    love.graphics.print(string.format("H Frames: %d", #heroFrames), 10, 50)
    love.graphics.print("State: " .. VESPER.state, 10, 70)
    love.graphics.print("Proj: " .. #projectiles, 10, 90)
end

-- Draw debug panel
function drawDebugPanel()
    local panelX = WINDOW_WIDTH
    local panelW = DEBUG_PANEL_WIDTH
    local panelH = WINDOW_HEIGHT
    
    -- Panel background
    love.graphics.setColor(20, 20, 30, 230)
    love.graphics.rectangle("fill", panelX, 0, panelW, panelH)
    love.graphics.setColor(100, 100, 120)
    love.graphics.rectangle("line", panelX, 0, panelW, panelH)
    
    local sliderX = panelX + 30
    local sliderW = panelW - 60
    local sliderY = 80  -- Increased by 50px from 30
    local sliderSpacing = 55
    
    love.graphics.setColor(200, 200, 200)
    love.graphics.print("=== DEBUG PANEL ===", sliderX, 30)
    
    -- Define sliders (show multiplier values)
    local sliders = {
        {name = "Vesper Attack", key = "vesperAttackPower", value = DEBUG.vesperAttackPower},
        {name = "Vesper Range", key = "vesperAttackRange", value = DEBUG.vesperAttackRange},
        {name = "Vesper AtkSpd", key = "vesperAttackSpeed", value = DEBUG.vesperAttackSpeed},
        {name = "Skill1 Dmg", key = "vesperSkill1Damage", value = DEBUG.vesperSkill1Damage},
        {name = "Skill2 Dmg", key = "vesperSkill2Damage", value = DEBUG.vesperSkill2Damage},
        {name = "Vesper MoveSpd", key = "vesperMoveSpeed", value = DEBUG.vesperMoveSpeed},
        {name = "Enemy Armor", key = "enemyArmor", value = DEBUG.enemyArmor},
        {name = "Enemy Speed", key = "enemySpeed", value = DEBUG.enemySpeed},
        {name = "Spawn Speed", key = "enemySpawnSpeed", value = DEBUG.enemySpawnSpeed}
    }
    
    -- Draw sliders
    for i, slider in ipairs(sliders) do
        local y = sliderY + (i-1) * sliderSpacing
        
        -- Label
        love.graphics.setColor(180, 180, 180)
        love.graphics.print(slider.name, sliderX, y)
        
        -- Value display - 20px from right edge of panel
        love.graphics.setColor(255, 255, 255)
        local displayVal = string.format("%.2fx", DEBUG[slider.key])
        love.graphics.print(displayVal, panelX + panelW - 50, y)
        
        -- Slider track
        love.graphics.setColor(60, 60, 80)
        love.graphics.rectangle("fill", sliderX, y + 20, sliderW, 8)
        
        -- Calculate knob position: center = 1.0, left = 1/32, right = 32
        -- log2(32) = 5, so range is -5 to +5
        local logValue = math.log(DEBUG[slider.key]) / math.log(2)
        local knobX = sliderX + sliderW/2 + (logValue / 5) * (sliderW/2)
        knobX = math.max(sliderX, math.min(sliderX + sliderW, knobX))
        
        -- Store knob position for click detection
        slider.knobX = knobX
        slider.y = y
        
        -- Slider knob
        love.graphics.setColor(100, 150, 200)
        love.graphics.circle("fill", knobX, y + 24, 10)
        
        -- Center line (1x)
        love.graphics.setColor(100, 100, 100)
        love.graphics.rectangle("fill", sliderX + sliderW/2 - 1, y + 15, 2, 16)
    end
    
    DEBUG.sliders = sliders
    
    -- Buttons for resetting cooldowns
    local btnY = sliderY + #sliders * sliderSpacing + 20
    local btnW = sliderW / 2 - 5
    local btnH = 35
    
    -- Skill 1 CD reset button
    love.graphics.setColor(80, 120, 80)
    love.graphics.rectangle("fill", sliderX, btnY, btnW, btnH)
    love.graphics.setColor(150, 200, 150)
    love.graphics.print("Reset S1 CD", sliderX + 10, btnY + 10)
    
    -- Skill 2 CD reset button
    love.graphics.setColor(80, 120, 80)
    love.graphics.rectangle("fill", sliderX + btnW + 10, btnY, btnW, btnH)
    love.graphics.setColor(150, 200, 150)
    love.graphics.print("Reset S2 CD", sliderX + btnW + 20, btnY + 10)
    
    DEBUG.skillBtnY = btnY
    DEBUG.skillBtnH = btnH
    DEBUG.skillBtnW = btnW
    DEBUG.sliderX = sliderX
    DEBUG.sliderW = sliderW
    
    -- Reset button at bottom
    local resetBtnY = btnY + btnH + 30
    local resetBtnW = sliderW
    local resetBtnH = 40
    
    love.graphics.setColor(100, 100, 100)
    love.graphics.rectangle("fill", sliderX, resetBtnY, resetBtnW, resetBtnH)
    love.graphics.setColor(200, 200, 200)
    love.graphics.print("RESET ALL", sliderX + resetBtnW/2 - 40, resetBtnY + 12)
    
    DEBUG.resetBtnY = resetBtnY
    DEBUG.resetBtnW = resetBtnW
    DEBUG.resetBtnH = resetBtnH
end

-- Handle slider interaction
function handleDebugPanelClick(x, y)
    local panelX = WINDOW_WIDTH
    if x < panelX then return end
    
    local sliders = DEBUG.sliders or {}
    local sliderX = DEBUG.sliderX or (panelX + 30)
    local sliderW = DEBUG.sliderW or 300
    
    -- Check sliders
    for i, slider in ipairs(sliders) do
        local sliderY = 80 + (i-1) * 55 + 20  -- Adjusted by 50px
        if y >= sliderY - 10 and y <= sliderY + 30 then
            if x >= sliderX and x <= sliderX + sliderW then
                -- Calculate multiplier from position
                local ratio = (x - sliderX) / sliderW
                -- ratio 0 = 1/32, 0.5 = 1, 1 = 32
                local logValue = (ratio - 0.5) * 10  -- -5 to +5
                DEBUG[slider.key] = math.pow(2, logValue)
                return true
            end
        end
    end
    
    -- Check buttons (adjusted by 50px)
    local btnY = DEBUG.skillBtnY or 550
    local btnW = DEBUG.skillBtnW or 145
    local btnH = DEBUG.skillBtnH or 35
    
    -- Skill 1 button
    if y >= btnY and y <= btnY + btnH then
        if x >= sliderX and x <= sliderX + btnW then
            VESPER.skills[1].ready = true
            VESPER.skills[1].cooldownTimer = 0
            return true
        end
        -- Skill 2 button
        if x >= sliderX + btnW + 10 and x <= sliderX + btnW * 2 + 10 then
            VESPER.skills[2].ready = true
            VESPER.skills[2].cooldownTimer = 0
            return true
        end
    end
    
    -- Reset button
    local resetBtnY = DEBUG.resetBtnY or 620
    local resetBtnW = DEBUG.resetBtnW or 300
    local resetBtnH = DEBUG.resetBtnH or 40
    if y >= resetBtnY and y <= resetBtnY + resetBtnH then
        if x >= sliderX and x <= sliderX + resetBtnW then
            -- Reset all sliders to 1.0x
            DEBUG.vesperAttackPower = 1.0
            DEBUG.vesperAttackRange = 1.0
            DEBUG.vesperAttackSpeed = 1.0
            DEBUG.vesperSkill1Damage = 1.0
            DEBUG.vesperSkill2Damage = 1.0
            DEBUG.vesperMoveSpeed = 1.0
            DEBUG.enemyArmor = 1.0
            DEBUG.enemySpeed = 1.0
            DEBUG.enemySpawnSpeed = 1.0
            return true
        end
    end
    
    return false
end

function love.mousepressed(x, y, btn)
    mouseDown = true
    local dist = math.sqrt((x-VESPER.x)^2 + (y-VESPER.y)^2)
    mouseOnHero = (dist < 60)
    
    -- Handle debug panel
    handleDebugPanelClick(x, y)
end

function love.mousereleased(x, y, btn)
    mouseDown = false
    mouseOnHero = false
end

function love.keypressed(key)
    if key == "escape" then love.event.quit()
    elseif key == "space" then
        gamePaused = not gamePaused
    elseif key == "1" then activateSkill(1)
    elseif key == "2" then activateSkill(2)
    elseif key == "w" or key == "W" then keysDown.w = true
    elseif key == "a" or key == "A" then keysDown.a = true
    elseif key == "s" or key == "S" then keysDown.s = true
    elseif key == "d" or key == "D" then keysDown.d = true
    end
end

function love.keyreleased(key)
    if key == "w" or key == "W" then keysDown.w = false
    elseif key == "a" or key == "A" then keysDown.a = false
    elseif key == "s" or key == "S" then keysDown.s = false
    elseif key == "d" or key == "D" then keysDown.d = false
    end
end
