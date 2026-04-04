-- tests/foundations.lua
-- Integration tests for auto-foundation-undergrounds.
-- These run inside a real Factorio instance via FactorioTest, so all surface/
-- entity/tile APIs are the real thing — no mocking needed.
local function get_surface()
    -- The headless benchmark save only has Nauvis; create Vulcanus if needed.
    local s = game.get_surface("vulcanus")
    if not s then
        s = game.create_surface("vulcanus")
        -- Newly created surfaces have no generated chunks; generate a region around
        -- the origin so that set_tiles and create_entity work without silently failing.
        s.request_to_generate_chunks({
            x = 0,
            y = 0
        }, 5)
        s.force_generate_chunk_requests()
    end
    return s
end

local function get_force()
    return game.forces["player"]
end

-- Place an underground belt pair and return {input, output}.
-- direction is the direction of belt travel (e.g. defines.direction.east).
-- The input is placed at pos; the output at pos + (distance + 1) tiles forward.
-- raise_built = true fires script_raised_built synchronously during create_entity,
-- so ghosts are placed before this function returns.
local function place_belt_pair(surface, pos, direction, distance)
    distance = distance or 3
    local offsets = {
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
    local off = offsets[direction]
    local exit_pos = {
        x = pos.x + off.x * (distance + 1),
        y = pos.y + off.y * (distance + 1)
    }

    local input = surface.create_entity {
        name = "underground-belt",
        position = pos,
        direction = direction,
        type = "input",
        force = get_force(),
        raise_built = true
    }
    assert(input and input.valid, "Failed to place belt input at " .. serpent.line(pos))
    local output = surface.create_entity {
        name = "underground-belt",
        position = exit_pos,
        direction = direction,
        type = "output",
        force = get_force(),
        raise_built = true
    }
    assert(output and output.valid, "Failed to place belt output at " .. serpent.line(exit_pos))
    return input, output
end

-- Place a pipe-to-ground pair and return {entry, partner}.
-- direction is the above-ground opening direction of entry.
-- The partner is placed (distance + 1) tiles in the opposite direction, facing back.
-- raise_built = true fires script_raised_built synchronously during create_entity.
local function place_pipe_pair(surface, pos, direction, distance)
    distance = distance or 3
    local offsets = {
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
    local off = offsets[direction]
    local partner_pos = {
        x = pos.x - off.x * (distance + 1),
        y = pos.y - off.y * (distance + 1)
    }

    local entry = surface.create_entity {
        name = "pipe-to-ground",
        position = pos,
        direction = direction,
        force = get_force(),
        raise_built = true
    }
    assert(entry and entry.valid, "Failed to place pipe at " .. serpent.line(pos))
    local partner = surface.create_entity {
        name = "pipe-to-ground",
        position = partner_pos,
        -- Factorio 2.0 uses 16-direction values; cardinal opposites are +8 mod 16.
        direction = (direction + 8) % 16,
        force = get_force(),
        raise_built = true
    }
    assert(partner and partner.valid, "Failed to place pipe partner at " .. serpent.line(partner_pos))
    return entry, partner
end

-- Flood a rectangle of tiles with lava.
local function set_lava(surface, x1, y1, x2, y2)
    local tiles = {}
    for x = x1, x2 do
        for y = y1, y2 do
            tiles[#tiles + 1] = {
                name = "lava",
                position = {x, y}
            }
        end
    end
    surface.set_tiles(tiles)
end

-- Count foundation tile-ghosts in the tile rectangle [x1,x2] × [y1,y2].
local function count_foundation_ghosts(surface, x1, y1, x2, y2)
    local count = 0
    for _, ghost in pairs(surface.find_entities_filtered {
        name = "tile-ghost",
        area = {{x1, y1}, {x2 + 1, y2 + 1}}
    }) do
        if ghost.ghost_name == "foundation" then
            count = count + 1
        end
    end
    return count
end

-- Destroy all entities and reset all tiles to stone-path in the given tile rectangle.
local function clear_area(surface, x1, y1, x2, y2)
    -- +1 on the far edges because find_entities_filtered uses exclusive upper bounds.
    for _, e in pairs(surface.find_entities_filtered {
        area = {{x1, y1}, {x2 + 1, y2 + 1}}
    }) do
        if e.valid then
            e.destroy()
        end
    end
    local tiles = {}
    for x = x1, x2 do
        for y = y1, y2 do
            tiles[#tiles + 1] = {
                name = "stone-path",
                position = {x, y}
            }
        end
    end
    surface.set_tiles(tiles)
end

-- ────────────────────────────────────────────────────────────────────────────

describe("underground belt over lava", function()
    local surface
    before_each(function()
        surface = get_surface()
        set_lava(surface, 1, 0, 5, 0)
    end)
    after_each(function()
        clear_area(surface, 0, 0, 6, 0)
    end)

    it("places foundation ghosts on each lava tile in the gap (east)", function()
        -- Input at tile 0, output at tile 6, gap is tiles 1–5 (all lava → 5 ghosts).
        async()
        place_belt_pair(surface, {
            x = 0.5,
            y = 0.5
        }, defines.direction.east, 5)
        after_ticks(1, function()
            local n = count_foundation_ghosts(surface, 1, 0, 5, 0)
            assert(n == 5, "Expected 5 ghosts, got " .. n)
            done()
        end)
    end)

    it("does not place ghosts on non-lava tiles", function()
        -- Tiles 2 and 4 are stone; only 1, 3, 5 are lava → 3 ghosts.
        surface.set_tiles {{
            name = "stone-path",
            position = {2, 0}
        }, {
            name = "stone-path",
            position = {4, 0}
        }}
        async()
        place_belt_pair(surface, {
            x = 0.5,
            y = 0.5
        }, defines.direction.east, 5)
        after_ticks(1, function()
            local n = count_foundation_ghosts(surface, 1, 0, 5, 0)
            assert(n == 3, "Expected 3 ghosts, got " .. n)
            done()
        end)
    end)

    it("places ghosts for north-south belt pair", function()
        set_lava(surface, 0, 1, 0, 5)
        async()
        place_belt_pair(surface, {
            x = 0.5,
            y = 0.5
        }, defines.direction.south, 5)
        after_ticks(1, function()
            local n = count_foundation_ghosts(surface, 0, 1, 0, 5)
            assert(n == 5, "Expected 5 ghosts, got " .. n)
            done()
        end)
    end)

    it("removes ghosts when input belt is mined", function()
        async()
        local input = place_belt_pair(surface, {
            x = 0.5,
            y = 0.5
        }, defines.direction.east, 5)
        after_ticks(1, function()
            input.destroy {
                raise_destroy = true
            }
            assert(count_foundation_ghosts(surface, 1, 0, 5, 0) == 0)
            done()
        end)
    end)

    it("removes ghosts when output belt is mined", function()
        async()
        local _, output = place_belt_pair(surface, {
            x = 0.5,
            y = 0.5
        }, defines.direction.east, 5)
        after_ticks(1, function()
            output.destroy {
                raise_destroy = true
            }
            assert(count_foundation_ghosts(surface, 1, 0, 5, 0) == 0)
            done()
        end)
    end)

    it("does not place ghosts on non-Vulcanus surfaces", function()
        local nauvis = game.get_surface("nauvis")
        set_lava(nauvis, 1, 0, 5, 0) -- tiles won't be real lava, but exercises the surface guard
        async()
        place_belt_pair(nauvis, {
            x = 0.5,
            y = 0.5
        }, defines.direction.east, 5)
        after_ticks(1, function()
            assert(count_foundation_ghosts(nauvis, 1, 0, 5, 0) == 0)
            clear_area(nauvis, 0, 0, 6, 0)
            done()
        end)
    end)
end)

-- ────────────────────────────────────────────────────────────────────────────

describe("pipe-to-ground over lava", function()
    local surface
    before_each(function()
        surface = get_surface()
        set_lava(surface, 1, 0, 5, 0)
    end)
    after_each(function()
        clear_area(surface, -1, 0, 7, 0)
    end)

    it("places foundation ghosts on lava tiles in the gap (east)", function()
        -- Entry at x=5.5 (east), partner at x=-0.5 (west); gap tiles 0–4.
        -- Lava is set at tiles 1–5, so ghosts land at tiles 1, 2, 3, 4 (4 total).
        async()
        place_pipe_pair(surface, {
            x = 5.5,
            y = 0.5
        }, defines.direction.east, 5)
        after_ticks(1, function()
            assert(count_foundation_ghosts(surface, 1, 0, 4, 0) == 4)
            done()
        end)
    end)

    it("removes ghosts when a pipe is mined", function()
        async()
        local entry = place_pipe_pair(surface, {
            x = 5.5,
            y = 0.5
        }, defines.direction.east, 5)
        after_ticks(1, function()
            entry.destroy {
                raise_destroy = true
            }
            assert(count_foundation_ghosts(surface, 1, 0, 4, 0) == 0)
            done()
        end)
    end)
end)

-- ────────────────────────────────────────────────────────────────────────────

describe("revert built foundations on mine", function()
    local surface
    before_each(function()
        surface = get_surface()
        set_lava(surface, 1, 0, 3, 0)
    end)
    after_each(function()
        clear_area(surface, 0, 0, 4, 0)
    end)

    -- Simulate construction robots building the foundation ghosts.
    local function build_ghosts(s, x1, y1, x2, y2)
        for _, ghost in pairs(s.find_entities_filtered {
            name = "tile-ghost",
            area = {{x1, y1}, {x2 + 1, y2 + 1}}
        }) do
            if ghost.valid and ghost.ghost_name == "foundation" then
                local pos = ghost.position
                ghost.destroy()
                s.set_tiles {{
                    name = "foundation",
                    position = pos
                }}
            end
        end
    end

    it("orders deconstruction of built foundation tiles when underground is mined", function()
        async()
        local input = place_belt_pair(surface, {
            x = 0.5,
            y = 0.5
        }, defines.direction.east, 3)
        after_ticks(1, function()
            -- Ghosts are placed; simulate robots building them into real tiles.
            build_ghosts(surface, 1, 0, 3, 0)

            for x = 1, 3 do
                assert(surface.get_tile(x, 0).name == "foundation", "Expected foundation at " .. x .. ",0")
            end

            input.destroy {
                raise_destroy = true
            }

            -- Each deconstructed tile gets a deconstructible-tile-proxy entity.
            local proxies = surface.find_entities_filtered {
                name = "deconstructible-tile-proxy",
                area = {{0, -1}, {6, 2}}
            }
            assert(#proxies == 3, "Expected 3 tiles marked for deconstruction, got " .. #proxies)
            done()
        end)
    end)
end)
