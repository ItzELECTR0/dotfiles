---[===Vertical=Stack===]---
-- Equal-height rows. Arriving windows (spawned or dropped) slot in at the cursor when it is over the
-- stack, like dwindle, otherwise above the bottom window so the third lands in the middle.
local orders = {}

local function key(target)
    return target.window and target.window.address or ("target:" .. target.index)
end

local function slot(area, count)
    local cursor = hl.get_cursor_pos()
    if cursor and count > 0
        and cursor.x >= area.x and cursor.x < area.x + area.w
        and cursor.y >= area.y and cursor.y < area.y + area.h then
        return math.floor((cursor.y - area.y) / area.h * count + 0.5) + 1
    end
    return count >= 2 and count or count + 1
end

hl.layout.register("vstack", {
    recalculate = function(ctx)
        local first = ctx.targets[1]
        local ws = first and first.window and first.window.workspace
        local id = ws and ws.id or "none"

        local by_key = {}
        for _, t in ipairs(ctx.targets) do by_key[key(t)] = t end

        local order = {}
        if orders[id] then
            local seen = {}
            for _, k in ipairs(orders[id]) do
                if by_key[k] then
                    table.insert(order, k)
                    seen[k] = true
                end
            end
            for _, t in ipairs(ctx.targets) do
                if not seen[key(t)] then table.insert(order, slot(ctx.area, #order), key(t)) end
            end
        else
            for _, t in ipairs(ctx.targets) do table.insert(order, key(t)) end
        end
        orders[id] = order

        local area, n = ctx.area, #order
        for i, k in ipairs(order) do
            by_key[k]:place({ x = area.x, y = area.y + area.h * (i - 1) / n, w = area.w, h = area.h / n })
        end
    end,
})
