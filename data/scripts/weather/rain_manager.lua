-- Rain manager script.
--[[
To add this script to your game, call from game_manager script:
    require("scripts/weather/rain_manager")

The functions here defined are:
    game:get_rain_type(world)
    game:set_rain_type(world, rain_type)

Rain types: nil (no rain), "rain", "storm".
--]]

-- This script requires the multi_event script:
require("scripts/multi_events")
local rain_manager = {}

local game_meta = sol.main.get_metatable("game")
local map_meta = sol.main.get_metatable("map")

-- Assets: sounds and sprites.
local drop_sprite = sol.sprite.create("weather/rain")
local thunder_sounds = {"thunder1", "thunder2", "thunder3", "thunder_far", "thunder_double"}

-- Default settings. Change these for testing.
local rain_enabled = true -- Do not change this property, unless you are testing.
-- local lightning_enabled = true
local rain_speed = 140
local storm_speed = 220
local current_drop_speed
local drop_min_distance = 40 -- Min possible distance for drop movements.
local drop_max_distance = 300 -- Max possible distance for drop movements.
local rain_drop_delay = 10 -- Delay between drops for rain, in milliseconds.
local storm_drop_delay = 2 -- Delay between drops for storms, in milliseconds.
local current_drop_delay
local min_lightning_delay = 2000
local max_lightning_delay = 10000
local rain_surface, flash_surface -- Surfaces to draw rain and lightning flash.
local draw_flash_surface = false -- Used by the lightning menu.
local current_drop_index = 0 -- Current index for the next drop to be created.
local max_drop_number_rain = 200
local max_drop_number_storm = 500
local max_drop_number -- Max number of drops per map.
local drop_list = {} -- List of properties for each drop.
local splash_list = {} -- List of properties for each splash effect.
local timers = {}
local num_drops, num_splashes = 0, 0
local current_map

-- Get the rain manager.
function game_meta:get_rain_manager() return rain_manager end

-- Initialize rain on maps when necessary.
game_meta:register_event("on_map_changed", function(game)
  local map = game:get_map()
  current_map = map
  rain_manager:on_map_changed()
end)

-- Create rain if necessary when entering a new map.
function rain_manager:on_map_changed()
  -- Clear variables.
  rain_surface = nil
  drop_list, splash_list, timers = {}, {}, {}
  num_drops, num_splashes = 0, 0
  -- Get rain state in this world.
  local map = current_map
  local world = map:get_world()
  local rain_type = map:get_game():get_rain_type(world)
  -- Start rain if necessary.
  self:start_rain_mode(rain_type)
  -- Draw rain: start menu.
  sol.menu.start(map, rain_manager)
end

-- Get/set the raining state for a given world.
function game_meta:get_rain_type(world)
  local rain_type = nil 
  if world then
    rain_type = self:get_value("rain_state_" .. world)
  end
  return rain_enabled and rain_type
end
-- Set the raining state for a given world.
function game_meta:set_rain_type(world, rain_type)
  -- Update savegame variable.
  self:set_value("rain_state_" .. world, rain_type)
  -- Check if rain is necessary: if we are in that world and rain is needed.  
  local current_world = self:get_map():get_world()
  local rain_needed = (current_world == world) and rain_enabled and rain_type
end

-- Define on_draw event for the rain_manager menu (if it is initialized).
function rain_manager:on_draw(dst_surface)
  if rain_surface then
    rain_surface:clear()
    local camera = current_map:get_camera()
    local cx, cy, cw, ch = camera:get_bounding_box()
    -- Draw drops on surface.
    drop_sprite:set_animation("drop")
    for _, drop in pairs(drop_list) do
      drop_sprite:set_frame(drop.frame)
      local x = (drop.init_x + drop.x - cx) % cw
      local y = (drop.init_y + drop.y - cy) % ch
      drop_sprite:draw(rain_surface, x, y)
    end
    -- Draw splashes on surface.
    drop_sprite:set_animation("drop_splash")
    for _, splash in pairs(splash_list) do
      drop_sprite:set_frame(splash.frame)
      local x = (splash.x - cx) % cw
      local y = (splash.y - cy) % ch
      drop_sprite:draw(rain_surface, x, y)
    end
    -- Draw the surface.
    rain_surface:draw(dst_surface) -- Draw rain.
  end
  if draw_flash_surface then
    flash_surface:draw(dst_surface) -- Draw lightning if necessary.
  end
end

-- Create properties list for water drop at random position.
function rain_manager:create_drop(deviation)
  local r = deviation or 0
  local map = current_map
  local camera = map:get_camera()
  local cx, cy, cw, ch = camera:get_bounding_box()
  -- Initialize properties for new drop.
  local drop = {} -- Drop properties.
  drop.init_x = cx + cw * math.random()
  drop.init_y = cy + ch * math.random()
  drop.x, drop.y, drop.frame = 0, 0, 0
  drop.index = current_drop_index
  current_drop_index = (current_drop_index + 1) % max_drop_number
  drop_list[drop.index] = drop
  num_drops = num_drops + 1
  -- Initialize drop movement.
  local m = sol.movement.create("straight")
  m:set_angle(7 * math.pi / 5 + r)
  m:set_speed(current_drop_speed)
  local random_distance = math.random(drop_min_distance, drop_max_distance)
  m:set_max_distance(random_distance)
  -- Callback: create splash effect.
  m:start(drop, function()
    local index = drop.index
    local splash = {x = drop.init_x + drop.x, y = drop.init_y + drop.y}
    drop_list[index] = nil
    num_drops = num_drops - 1
    if num_drops == 0 then timers["drop_frame_timer"]:stop() end
    splash.index = index
    splash.frame = 0
    splash_list[index] = splash
    num_splashes = num_splashes + 1
  end)
  return drop
end

-- Stop rain effects for the current map.
function rain_manager:stop()
  -- Stop drop rain timers if already started.
  local t = timers["drop_timer"]
  if t then t:stop() end
  timers["drop_timer"] = nil
  return true
end

-- Start rain in the current map.
function rain_manager:start_rain_mode(rain_type)
  -- Reset drop timer.
  self:stop()
  if rain_type == nil then return end
  -- Reset other timers.
  for _, t in pairs(timers) do t:stop() end
  -- Initialize parameters.
  local drop_deviation = 0
  if rain_type == "rain" then
    current_drop_speed = rain_speed
    current_drop_delay = rain_drop_delay
    max_drop_number = max_drop_number_rain
  elseif rain_type == "storm" then
    current_drop_speed = storm_speed
    current_drop_delay = storm_drop_delay
    max_drop_number = max_drop_number_storm
  else
    error("Invalid rain mode.")
  end
  -- Create rain surface.
  local map = current_map
  local camera = map:get_camera()
  local cx, cy, cw, ch = camera:get_bounding_box()
  rain_surface = sol.surface.create(cw, ch)
  -- Initialize drop timer.
  timers["drop_timer"] = sol.timer.start(map, current_drop_delay, function()
    -- Check if there is space for a new drop (there is a max number of drops).
    if drop_list[current_drop_index] == nil then
      -- Random angle deviation in case of storm.
      if rain_type == "storm" then
        drop_deviation = math.random(-1, 1) * math.random() * math.pi / 8
      end
      -- Create drops at random positions.
      rain_manager:create_drop(drop_deviation)
    end
    return true -- Repeat loop.
  end)
  -- Update rain frames for all drops at once.
  timers["drop_frame_timer"] = sol.timer.start(map, 75, function()
    for _, drop in pairs(drop_list) do
      drop.frame = (drop.frame + 1) % 3
    end
    return true
  end)
  -- Update splash frames for all splashes at once.
  timers["splash_frame_timer"] = sol.timer.start(map, 100, function()
    for index, splash in pairs(splash_list) do
      splash.frame = splash.frame + 1
      if splash.frame >= 4 then
        -- Destroy splash after last frame.
        splash_list[index] = nil
        num_splashes = num_splashes - 1
        if num_splashes == 0 then return false end
      end
    end
    return true
  end)
end

--[[
-- Start lighnings in the current map.
local function create_lightnings(map)
  -- Play thunder sound after a random delay.
  local lightning_delay = math.random(min_lightning_delay, max_lightning_delay)
  timers["lightning_timer"] = sol.timer.start(map, lightning_delay, function()
    -- Create lightning flash.
    draw_flash_surface = true
    sol.timer.start(map, 150, function()
      draw_flash_surface = false -- Stop drawing lightning flash.
    end)
    -- Play random thunder sound after a delay.
    local thunder_delay = math.random(200, 1500)
    sol.timer.start(map, thunder_delay, function()
      local random_index = math.random(1, #thunder_sounds)
      local sound_id = thunder_sounds[random_index]
      sol.audio.play_sound(sound_id)
    end)
    -- Prepare next lightning.
    create_lightnings(map)
  end)
end

-- Start storm in the current map.
function rain_manager:start_storm(map)
  -- Initialize drop speed.
  current_drop_speed = storm_speed
  -- Stop rain timers if already started.
  self:stop()
  -- Create lightning surface.
  local camera = map:get_camera()
  local cx, cy, cw, ch = camera:get_bounding_box()
  flash_surface = sol.surface.create(cw, ch)
  flash_surface:fill_color({255, 255, 100})
  flash_surface:set_opacity(170)
  -- Initialize menu to draw lightning surface.
  sol.menu.start(map, rain_manager)

  -- Start timer to draw rain drops.
  timers["drop_timer"] = sol.timer.start(map, storm_drop_delay, function()
    -- Create drops on random positions.
    create_drop(map)
    -- Repeat loop.
    return true
  end)
  -- Start lightning effects.
  create_lightnings(map)
end
--]]

-- Return rain manager.
return rain_manager