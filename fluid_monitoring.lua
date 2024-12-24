component = require("component")
gpu = component.gpu


function update_deque(deque, value)
    --[[Update the deque with the value up to the maximum deque size.
    Examples:
        DEQUE_MAX_SIZE = 3
        update_deque({1, 2}   , 5) -> {1, 2, 5}
        update_deque({1, 2, 3}, 5) -> {2, 3, 5}
    --]]
    if #deque == DEQUE_MAX_SIZE then
        table.remove(deque, 1)
    end
    table.insert(deque, value)
    return deque
end


function get_average(list)
    local sum = 0
    for i = 1, #list do
        sum = sum + list[i]
    end
    local average = sum / #list
    return average
end


function round(number, ndigits)
    --[[Rounds down a number to a specified number of decimal places,
    adding trailing zeros if necessary.
    --]]
    number = tostring(number)
    local whole_number_part = string.match(number, "(.*)%.") or number
    local decimal_part = string.match(number, "%.(.*)")

    -- No decimal part, add trailing zeros
    if not decimal_part then
        decimal_part = string.rep("0", ndigits)
    -- Long decimal part, shortening
    elseif #decimal_part > ndigits then
        decimal_part = string.sub(decimal_part, 1, ndigits)
    -- Short decimal part, add trailing zeros
    elseif #decimal_part < ndigits then
        decimal_part = decimal_part .. string.rep("0", ndigits - #decimal_part)
    end

    return whole_number_part .. "." .. decimal_part
end


function add_commas_to_number(number)
    --[[Add commas to a number as thousands separators. Supports int, 
    float, str. Example: "+1234.0000" -> "+1,234.0000".
    --]]
    number = tostring(number)
    local has_plus_sign = string.sub(number, 1, 1) == "+"
    local has_minus_sign = string.sub(number, 1, 1) == "-"
    local decimal_part = string.match(number, "%.(.*)")
    number = math.abs(number)    -- get rid of the sign
    number = math.floor(number)  -- get rid of the decimal part

    -- Add commas as thousands separators
    number = string.reverse(number)
    local number_with_commas = string.gsub(number, "(%d%d%d)", "%1,")
    number_with_commas = string.reverse(number_with_commas)

    -- Remove the comma from ",123,456"
    if string.sub(number_with_commas, 1, 1) == "," then
        number_with_commas = string.sub(number_with_commas, 2)
    end

    -- Adding back signs
    if has_minus_sign then
        number_with_commas = "-" .. number_with_commas
    elseif has_plus_sign then
        number_with_commas = "+" .. number_with_commas
    end

    -- Adding back decimal part
    if decimal_part then
        number_with_commas = number_with_commas .. "." .. decimal_part
    end

    return number_with_commas
end


function set_explicit_sign(number)
    --[[Return a string representation of a number greater that zero
    with an explicit "+" sign.
    --]]
    number = tostring(number)
    if tonumber(number) > 0 then
        return "+" .. number
    end
    return number
end


function set_foreground_by_sign(number)
    --[[Sets a foreground color based on a given number: "green" for
    positive numbers, "red" for negative numbers, and "gray" for zero.
    --]]
    if number > 0 then
        gpu.setForeground(0x00FF00)
    elseif number < 0 then
        gpu.setForeground(0xFF0000)
    else
        gpu.setForeground(0x777777)
    end
end


function get_tank_addresses()
    local tank_addresses = {}
    for tank_address, _ in component.list("gt_machine") do
        table.insert(tank_addresses, tank_address)
    end
    return tank_addresses
end


function get_fluid_values(tank_address)
    --[[Get the Super/Quantum Tank fluid values.--]]


    local function get_tank_scanner_data(tank_address)
        --[[Get the Super/Quantum Tank scanner data as a table. Example:
            {"§9Super Tank§r",
             "Stored Fluid:",
             "§6Water§r",
             "§a9,720 L§r §e4,000,000 L§r"}
        --]]
        
        -- Error catch while ME system with OC P2P is booting
        local is_no_error, tank_scanner_data = pcall(component.invoke, tank_address, "getSensorInformation")
        while not is_no_error do
            local a, b = gpu.getResolution()
            gpu.fill(1, 1, a, b, " ")
            gpu.set(1, 1, "Waiting for your ME system to boot...")
            gpu.set(1, 2, "Or did you dismantle the tank? Then reboot the program")
            gpu.bitblt(0, _, _, _, _, 1)
            os.sleep(1)
            is_no_error, tank_scanner_data = pcall(component.invoke, tank_address, "getSensorInformation")
        end

        local ticks_stamp = os.time()*(1000/60/60)

        return tank_scanner_data, ticks_stamp
    end


    local function parse_fluid_name(raw_fluid_name)
        --[[Parse the fluid name. Example: "§6Water§r" -> "Water".--]]
        return string.gsub(raw_fluid_name, "§.", "")
    end


    local function parse_fluid_amount(raw_fluid_amount)
        --[[Parse the fluid amount. Example:
        "§a9,720 L§r §e4,000,000 L§r" -> 9720.
        --]]
        local fluid_amount = string.match(raw_fluid_amount, "a([%d,]*)")
        fluid_amount = string.gsub(fluid_amount, ",", "")
        fluid_amount = tonumber(fluid_amount)
        return fluid_amount
    end


    local function parse_fluid_capacity(raw_fluid_capacity)
        --[[Parse the fluid capacity. Example:
        "§a9,720 L§r §e4,000,000 L§r" -> 4000000.

        Note: when the tank Overflow Voiding Mode is enabled, the fluid
        capacity is shown as 2,147,483,648. The possible solution
        is an Overflow Valve cover with the overflow point slightly
        below the tank capacity.
        --]]
        local fluid_capacity = string.match(raw_fluid_capacity, "e([%d,]*)")
        fluid_capacity = string.gsub(fluid_capacity, ",", "")
        fluid_capacity = tonumber(fluid_capacity)
        return fluid_capacity
    end


    local function get_fluid_fill_percentage(fluid_amount, fluid_capacity)
        --[[Get the fluid fill percentage. Example: 9.302275.--]]
        local fluid_fill_percentage = fluid_amount/fluid_capacity*100
        return fluid_fill_percentage
    end


    local function get_fluid_rate_avg_per_tick(fluid_amount_current, tick_stamp_current, x)
        --[[Table structure:
        {[tank_address] = {fluid_amount_previous, tick_stamp_previous, fluid_rate_per_tick_deque},
        [tank_address] = {fluid_amount_previous, tick_stamp_previous, fluid_rate_per_tick_deque},
        ...}
        
        x is {fluid_amount_previous, tick_stamp_previous, fluid_rate_per_tick_deque}
        --]]

        -- Initialization
        if not x then
            x = {}
            local fluid_amount_previous = fluid_amount_current
            local tick_stamp_previous = tick_stamp_current
            local fluid_rate_per_tick_deque = {}

            x[1] = fluid_amount_previous
            x[2] = tick_stamp_previous
            x[3] = fluid_rate_per_tick_deque

            return 0, x
        end

        -- Processing
        local fluid_amount_previous = x[1]
        local tick_stamp_previous = x[2]
        local fluid_rate_per_tick_deque = x[3]

        local tick_interval = tick_stamp_current - tick_stamp_previous
        local fluid_rate_per_tick = (fluid_amount_current - fluid_amount_previous)/tick_interval

        fluid_rate_per_tick_deque = update_deque(fluid_rate_per_tick_deque, fluid_rate_per_tick)
        local fluid_rate_avg_per_tick = get_average(fluid_rate_per_tick_deque)

        fluid_amount_previous = fluid_amount_current
        tick_stamp_previous = tick_stamp_current

        x[1] = fluid_amount_previous
        x[2] = tick_stamp_previous
        x[3] = fluid_rate_per_tick_deque

        return fluid_rate_avg_per_tick, x
    end


    local function get_time_forecast(fluid_flow, fluid_amount, fluid_capacity)
        --[[Get the time forecast in ticks. Example: 39203.29.--]]
        if fluid_flow > 0 then
            time_forecast = (fluid_capacity - fluid_amount)/fluid_flow
        elseif fluid_flow < 0 then
            time_forecast = fluid_amount/fluid_flow
        else
            time_forecast = 0
        end
        return time_forecast
    end


    local function get_fluid_percentage_flow(fluid_flow, fluid_capacity)
        --[[Get the fluid percentage flow per tick. Example: 0.04.--]]
        local fluid_percentage_flow = fluid_flow/fluid_capacity*100
        return fluid_percentage_flow
    end


    local tank_scanner_data, ticks_stamp = get_tank_scanner_data(tank_address)

    local raw = {}
    raw.fluid_name     = parse_fluid_name(tank_scanner_data[3])
    raw.fluid_amount   = parse_fluid_amount(tank_scanner_data[4])
    raw.fluid_capacity = parse_fluid_capacity(tank_scanner_data[4])

    raw.fluid_fill_percentage = get_fluid_fill_percentage(raw.fluid_amount, raw.fluid_capacity)
    raw.fluid_flow, deques_buffer[tank_address] = get_fluid_rate_avg_per_tick(raw.fluid_amount, ticks_stamp, deques_buffer[tank_address])
    raw.fluid_percentage_flow = get_fluid_percentage_flow(raw.fluid_flow, raw.fluid_capacity)
    raw.time_forecast = get_time_forecast(raw.fluid_flow, raw.fluid_amount, raw.fluid_capacity)

    return raw
end


function format_values(raw)
    --[[Format raw values for display on the screen.--]]


    local function format_fluid_name(fluid_name)
        return fluid_name
    end


    local function format_time_forecast(time_forecast)
        --[[Examples: "Full in 19.3 h", "Empty in 0.3 h".--]]
        if time_forecast > 0 then
            prefix = "Full in "
        elseif time_forecast < 0 then
            prefix = "Empty in "
            time_forecast = -time_forecast
        else
            return "Still"
        end
        time_forecast = time_forecast/20/60/60
        time_forecast = round(time_forecast, 2)
        time_forecast = add_commas_to_number(time_forecast)
        time_forecast = prefix .. time_forecast .. " h"
        return time_forecast
    end


    local function format_fluid_amount(fluid_amount)
        --[[Examples: "1,137,853".--]]
        fluid_amount = add_commas_to_number(fluid_amount)
        return fluid_amount
    end


    local function format_fluid_capacity(fluid_capacity)
        --[[Examples: "16,000,000".--]]
        fluid_capacity = add_commas_to_number(fluid_capacity)
        return fluid_capacity
    end


    local function format_fluid_flow(fluid_flow)
        --[[Examples: "+12,392 L/h", "-12,392 L/h".--]]
        fluid_flow = fluid_flow*20*60*60
        fluid_flow = math.floor(fluid_flow)
        fluid_flow = set_explicit_sign(fluid_flow)
        fluid_flow = add_commas_to_number(fluid_flow)
        fluid_flow = fluid_flow .. " L/h"
        return fluid_flow
    end


    local function format_fluid_fill_percentage(fluid_fill_percentage)
        --[[Examples: "74.12%", "100.00%".--]]
        fluid_fill_percentage = round(fluid_fill_percentage, 2)
        fluid_fill_percentage = add_commas_to_number(fluid_fill_percentage)
        fluid_fill_percentage = fluid_fill_percentage .. " %"
        return fluid_fill_percentage
    end


    local function format_fluid_percentage_flow(fluid_percentage_flow)
        --[[Examples: "+12.39 %/h", "-12.00 %/h".--]]
        fluid_percentage_flow = fluid_percentage_flow*20*60*60
        fluid_percentage_flow = round(fluid_percentage_flow, 2)
        fluid_percentage_flow = set_explicit_sign(fluid_percentage_flow)
        fluid_percentage_flow = add_commas_to_number(fluid_percentage_flow)
        fluid_percentage_flow = fluid_percentage_flow .. " %/h"
        return fluid_percentage_flow
    end


    local formatted = {}
    formatted.fluid_name            = format_fluid_name(raw.fluid_name)
    formatted.time_forecast         = format_time_forecast(raw.time_forecast)
    formatted.fluid_amount          = format_fluid_amount(raw.fluid_amount)
    formatted.fluid_capacity        = format_fluid_capacity(raw.fluid_capacity)
    formatted.fluid_flow            = format_fluid_flow(raw.fluid_flow)
    formatted.fluid_fill_percentage = format_fluid_fill_percentage(raw.fluid_fill_percentage)
    formatted.fluid_percentage_flow = format_fluid_percentage_flow(raw.fluid_percentage_flow)

    return formatted
end


function draw_fluid_status_window(tank_address, x, y, width, height, forced_fluid_name)
    --[[Draw the fluid status window. Example:
        ┌ Water ─────────────────────────────────────────────── Full in 19.3 h ┐
        │ ██████████████████████████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
        └ 97,391,600 / 128,000,000 L (+132,300 L/h) ─────── 74.12% (+0.01 %/h) ┘
    --]]
    gpu.fill(x, y, x + width, y + width, " ")

    local raw = get_fluid_values(tank_address)
    raw.fluid_name = forced_fluid_name or raw.fluid_name

    local formatted = format_values(raw)

    -- Upper part
    dy = y

        -- Upper left
        dx_L = x

        gpu.setForeground(DEFAULT_COLOR)    
        gpu.set(dx_L, dy, DRAW_FRAME and "┌" or " ")
        dx_L = dx_L + 2

        gpu.setForeground(FLUID_COLORS[raw.fluid_name] or DEFAULT_COLOR)
        gpu.set(dx_L, dy, formatted.fluid_name)
        dx_L = dx_L + #formatted.fluid_name + 1
        gpu.setForeground(DEFAULT_COLOR)    

        -- Upper right
        dx_R = x + width - 1

        gpu.set(dx_R, y, DRAW_FRAME and "┐" or " ")
        dx_R = dx_R - #formatted.time_forecast - 1

        set_foreground_by_sign(raw.time_forecast)
        gpu.set(dx_R, dy, formatted.time_forecast)
        dx_R = dx_R - 1
        gpu.setForeground(DEFAULT_COLOR)

        -- Upper frame
        gpu.set(dx_L, dy, string.rep(DRAW_FRAME and "─" or " ", dx_R - dx_L))

    -- Middle part
    dy = dy + 1

    dx = x

    gpu.set(dx, dy, DRAW_FRAME and "│" or " ")
    dx = dx + 2

    filled_bar_width = math.floor((width - 4)*(raw.fluid_fill_percentage/100))

    gpu.setForeground(FLUID_COLORS[raw.fluid_name] or DEFAULT_COLOR)
    gpu.set(dx, dy, string.rep("█", filled_bar_width))
    dx = dx + filled_bar_width
    gpu.setForeground(DEFAULT_COLOR)

    gpu.setForeground(0x333333)
    empty_bar_width = width - 4 - filled_bar_width
    gpu.set(dx, dy, string.rep("░", empty_bar_width))
    dx = dx + empty_bar_width + 1
    gpu.setForeground(DEFAULT_COLOR)

    gpu.set(dx, dy, DRAW_FRAME and "│" or " ")

    for i = 1, height - 3 do
        gpu.copy(x, y + 1, width, 1, 0, i)
        dy = dy + 1
    end

    -- Lower part
    dy = dy + 1

        -- Lower left
        dx_L = x

        gpu.set(dx_L, dy, DRAW_FRAME and "└" or " ")
        dx_L = dx_L + 2

        gpu.set(dx_L, dy, formatted.fluid_amount)
        dx_L = dx_L + #formatted.fluid_amount + 1

        gpu.set(dx_L, dy, "/")
        dx_L = dx_L + 2

        gpu.set(dx_L, dy, formatted.fluid_capacity)
        dx_L = dx_L + #formatted.fluid_capacity + 1

        gpu.set(dx_L, dy, "L (")
        dx_L = dx_L + 3

        set_foreground_by_sign(raw.fluid_flow)
        gpu.set(dx_L, dy, formatted.fluid_flow)
        dx_L = dx_L + #formatted.fluid_flow
        gpu.setForeground(DEFAULT_COLOR)

        gpu.set(dx_L, dy, ")")
        dx_L = dx_L + 2

        -- Lower right
        dx_R = x + width - 1

        gpu.set(dx_R, dy, DRAW_FRAME and "┘" or " ")
        dx_R = dx_R - 2

        gpu.set(dx_R, dy, ")")
        dx_R = dx_R - #formatted.fluid_percentage_flow

        set_foreground_by_sign(raw.fluid_flow)
        gpu.set(dx_R, dy, formatted.fluid_percentage_flow)
        dx_R = dx_R - 1
        gpu.setForeground(DEFAULT_COLOR)

        gpu.set(dx_R, dy, "(")
        dx_R = dx_R - 1 - #formatted.fluid_fill_percentage

        gpu.set(dx_R, dy, formatted.fluid_fill_percentage)
        dx_R = dx_R - 1

        -- Lower frame
        gpu.set(dx_L, dy, string.rep(DRAW_FRAME and "─" or " ", dx_R - dx_L))

    -- Experimental EU/t calculation. It's displayed on the left side of
    -- the progress bar and is aware of the background. Benzene only.
    -- May not display correctly with shaders as it uses the background color.
    if formatted.fluid_name == "Benzene" and SHOW_BENZENE_EU_T then
        local eu_t = raw.fluid_flow*360
        eu_t = math.floor(eu_t)
        eu_t = set_explicit_sign(eu_t)
        eu_t = add_commas_to_number(eu_t)
        eu_t = tostring(eu_t) .. " EU/t"
        
        -- Character iteration
        for i = 1, #eu_t do
            local char = string.sub(eu_t, i, i)
            if gpu.get(x + 1 + i, y + 1) == "█" then
                gpu.setForeground(0x101010)
                gpu.setBackground(FLUID_COLORS[formatted.fluid_name])
                gpu.set(x + 1 + i, y + 1, char)
            else
                gpu.setForeground(FLUID_COLORS[formatted.fluid_name])
                gpu.setBackground(0x101010)
                gpu.set(x + 1 + i, y + 1, char)
            end
        end
        gpu.setForeground(DEFAULT_COLOR)
        gpu.setBackground(0x000000)
    end
end


DEQUE_MAX_SIZE = 10
UPDATE_DELAY_IN_SEC = 6

DRAW_FRAME = true
SHOW_BENZENE_EU_T = false
DEFAULT_COLOR = 0x777777
FLUID_COLORS = {
    ["Hydrogen Gas"] = 0xbd4b4b,
    ["Helium Gas"] = 0x751b00,
    ["Nitrogen Gas"] = 0x8b0000,
    ["Oxygen Gas"] = 0x005a75,
    ["Fluorine"] = 0x40729d,
    ["Chlorine"] = 0x194c4c,
    ["Argon Gas"] = 0x6d0084,
    ["Mercury"] = 0x8c8c8c,
    ["Radon"] = 0xbc3dbc,

    ["Water"] = 0x212fb4,
    ["Benzene"] = 0x4f4f4f,  -- default: 0x0f0f0f, too dark
    ["Nitrobenzene"] = 0x634d43  -- default: 0x2a1e18, too dark
    }

local tank_addresses = get_tank_addresses()
gpu.setResolution(80, 4*(#tank_addresses) - 1)
gpu.allocateBuffer()
gpu.setActiveBuffer(1)

deques_buffer = {}

while true do
    for i = 1, #tank_addresses do
        draw_fluid_status_window(tank_addresses[i], 1, 1 + 4*(i - 1), 80, 3)
    end
    gpu.bitblt(0, _, _, _, _, 1)
    os.sleep(UPDATE_DELAY_IN_SEC)
end
