-- control.lua
local opposite_direction = {
    [defines.direction.north] = defines.direction.south,
    [defines.direction.east] = defines.direction.west,
    [defines.direction.south] = defines.direction.north,
    [defines.direction.west] = defines.direction.east
}

local direction_offset = {
    [defines.direction.north] = {
        x = 0,
        y = -1
    },
    [defines.direction.east] = {
        x = 1,
        y = 0
    },
    [defines.direction.south] = {
        x = 0,
        y = 1
    },
    [defines.direction.west] = {
        x = -1,
        y = 0
    }
}

local function is_lava_tile(tile)
    return tile.name:find("lava") ~= nil
end

--- Returns true if the mod should act on this surface.
--- Centralised here so adding support for modded lava planets is a one-line change.
local function is_supported_surface(surface)
    return surface.name == "vulcanus"
end

--- Find the paired underground partner of entity, if present. Returns nil if not found.
local function find_underground_partner(entity)
    local pos = entity.position
    local direction = entity.direction
    local is_belt = entity.type == "underground-belt"

    -- Underground belts: both halves face the direction of travel.
    --   input  → search forward (in the direction of travel)
    --   output → search backward to find its input
    --
    -- Pipe-to-ground: `direction` is the above-ground opening direction.
    --   The underground runs the OPPOSITE way, so the partner is in that direction.
    local search_dir
    if is_belt then
        search_dir = entity.belt_to_ground_type == "output" and opposite_direction[direction] or direction
    else
        search_dir = opposite_direction[direction]
    end

    local offset = direction_offset[search_dir]
    if not offset then
        return nil
    end

    local proto = prototypes.entity[entity.name]
    local max_reach = proto and proto.max_underground_distance or 10

    -- max_underground_distance is the maximum number of tiles in the gap.
    -- The partner entity itself therefore sits up to max_reach + 1 steps away.
    for i = 1, max_reach + 1 do
        local cp = {
            x = pos.x + offset.x * i,
            y = pos.y + offset.y * i
        }
        for _, candidate in pairs(entity.surface.find_entities_filtered {
            position = cp,
            name = entity.name
        }) do
            local is_partner
            if is_belt then
                local want_type = entity.belt_to_ground_type == "input" and "output" or "input"
                is_partner = candidate.belt_to_ground_type == want_type and candidate.direction == direction
            else
                -- The pipe partner faces back toward the gap, i.e. opposite to this entity.
                is_partner = candidate.direction == opposite_direction[direction]
            end
            if is_partner then
                return candidate
            end
        end
    end
    return nil
end

--- Returns a list of {x, y} tile coordinates strictly between pos1 and pos2
--- along a single cardinal axis (the only valid case for underground connections).
local function get_gap_positions(pos1, pos2)
    -- Entity positions in Factorio are at tile centers (e.g. tile (3,5) has its
    -- center at {x=3.5, y=5.5}). math.floor converts to the tile coordinate.
    local x1 = math.floor(pos1.x)
    local y1 = math.floor(pos1.y)
    local x2 = math.floor(pos2.x)
    local y2 = math.floor(pos2.y)

    local positions = {}
    local dx = x2 - x1
    local dy = y2 - y1
    if math.abs(dx) + math.abs(dy) <= 1 then
        return positions
    end

    if dx ~= 0 then
        local step = dx > 0 and 1 or -1
        for x = x1 + step, x2 - step, step do
            positions[#positions + 1] = {
                x = x,
                y = y1
            }
        end
    else
        local step = dy > 0 and 1 or -1
        for y = y1 + step, y2 - step, step do
            positions[#positions + 1] = {
                x = x1,
                y = y
            }
        end
    end
    return positions
end

--- Place foundation tile ghosts on every lava tile in the given gap positions.
--- Returns only the positions where a ghost was actually placed (for undo tagging).
local function fill_lava_at(surface, positions, force)
    local placed = {}
    for _, pos in pairs(positions) do
        if is_lava_tile(surface.get_tile(pos.x, pos.y)) then
            surface.create_entity {
                name = "tile-ghost",
                position = {pos.x, pos.y},
                force = force,
                inner_name = "foundation"
            }
            placed[#placed + 1] = pos
        end
    end
    return placed
end

--- Revert foundation ghosts and built foundation tiles at the given positions.
--- Ghosts are destroyed immediately; built foundations are ordered for deconstruction
--- so that robots can collect the item and the hidden lava tile is restored.
local function revert_foundations_at(surface, positions)
    for _, pos in pairs(positions) do
        -- Destroy the ghost if robots haven't built it yet.
        for _, ghost in pairs(surface.find_entities_filtered {
            name = "tile-ghost",
            position = {pos.x + 0.5, pos.y + 0.5}
        }) do
            if ghost.ghost_name == "foundation" then
                ghost.destroy()
            end
        end

        -- If robots already built the foundation, order it deconstructed.
        -- LuaTile.order_deconstruction is used rather than surface.deconstruct_area
        -- to avoid interference from entities whose bounding boxes touch the tile edge.
        local tile = surface.get_tile(pos.x, pos.y)
        if tile.name == "foundation" then
            tile.order_deconstruction(game.forces["player"])
        end
    end
end

local TAG_POSITIONS = "auto_foundation_positions"
local TAG_SURFACE = "auto_foundation_surface"

--- Tag the undo action for entity with the positions of foundation ghosts we placed.
--- We scan all actions in undo item 1 to find the one matching entity (by name and
--- position), then attach the gap positions and surface index as tags. Tags are
--- automatically discarded when the undo stack flushes — no persistent storage needed.
local function tag_undo_action(player, entity, placed_positions)
    if not player then
        return
    end
    local stack = player.undo_redo_stack
    if stack.get_undo_item_count() == 0 then
        return
    end

    local item = stack.get_undo_item(1)
    for action_index = 1, #item do
        local action = item[action_index]
        if action.type == "built-entity" and action.target then
            local t = action.target
            if t.name == entity.name and t.position and math.floor(t.position.x) == math.floor(entity.position.x) and
                math.floor(t.position.y) == math.floor(entity.position.y) then
                stack.set_undo_tag(1, action_index, TAG_POSITIONS, placed_positions)
                stack.set_undo_tag(1, action_index, TAG_SURFACE, entity.surface.index)
                return
            end
        end
    end
end

local function on_entity_built(event)
    local entity = event.entity
    if not (entity and entity.valid) then
        return
    end
    if not is_supported_surface(entity.surface) then
        return
    end

    local partner = find_underground_partner(entity)
    if not partner then
        return
    end

    local gap = get_gap_positions(entity.position, partner.position)
    local placed = fill_lava_at(entity.surface, gap, entity.force)
    if #placed == 0 then
        return
    end

    if event.player_index then
        tag_undo_action(game.get_player(event.player_index), entity, placed)
    end
end

local function on_entity_removed(event)
    local entity = event.entity
    if not (entity and entity.valid) then
        return
    end
    if not is_supported_surface(entity.surface) then
        return
    end

    local partner = find_underground_partner(entity)
    if not partner then
        return
    end

    local gap = get_gap_positions(entity.position, partner.position)
    revert_foundations_at(entity.surface, gap)
end

--- Scan all connected players' redo stacks (item 1 = just-undone action) for our tag.
--- on_undo_applied provides only tick (no player_index), so we check all connected players.
local function on_undo_applied()
    for _, player in pairs(game.connected_players) do
        local stack = player.undo_redo_stack
        if stack.get_redo_item_count() == 0 then
            goto continue
        end

        local actions = stack.get_redo_item(1)
        for action_index = 1, #actions do
            local positions = stack.get_redo_tag(1, action_index, TAG_POSITIONS)
            local surface_index = stack.get_redo_tag(1, action_index, TAG_SURFACE)
            if positions and surface_index then
                local surface = game.get_surface(surface_index)
                if surface then
                    revert_foundations_at(surface, positions)
                end
            end
        end

        ::continue::
    end
end

--- Scan all connected players' undo stacks (item 1 = just-redone action) for our tag.
--- on_redo_applied provides only tick (no player_index), so we check all connected players.
local function on_redo_applied()
    for _, player in pairs(game.connected_players) do
        local stack = player.undo_redo_stack
        if stack.get_undo_item_count() == 0 then
            goto continue
        end

        local actions = stack.get_undo_item(1)
        for action_index = 1, #actions do
            local positions = stack.get_undo_tag(1, action_index, TAG_POSITIONS)
            local surface_index = stack.get_undo_tag(1, action_index, TAG_SURFACE)
            if positions and surface_index then
                local surface = game.get_surface(surface_index)
                if surface then
                    -- Use the redoing player's force (matches the original build force).
                    fill_lava_at(surface, positions, player.force)
                end
            end
        end

        ::continue::
    end
end

local entity_filters = {{
    filter = "type",
    type = "underground-belt"
}, {
    filter = "type",
    type = "pipe-to-ground"
}}

script.on_event(defines.events.on_built_entity, on_entity_built, entity_filters)
script.on_event(defines.events.on_robot_built_entity, on_entity_built, entity_filters)
script.on_event(defines.events.script_raised_built, on_entity_built, entity_filters)
script.on_event(defines.events.on_player_mined_entity, on_entity_removed, entity_filters)
script.on_event(defines.events.on_robot_pre_mined, on_entity_removed, entity_filters)
script.on_event(defines.events.script_raised_destroy, on_entity_removed, entity_filters)
script.on_event(defines.events.on_undo_applied, on_undo_applied)
script.on_event(defines.events.on_redo_applied, on_redo_applied)

if script.active_mods["factorio-test"] then
    require("__factorio-test__/init")({"tests/foundations"}, {
        load_luassert = false, -- we use plain assert() throughout
        game_speed = 1000
    })
end
