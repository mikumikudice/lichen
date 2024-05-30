#! /usr/bin/lua
local init = os.execute("./build.sh")
if not init then os.exit(1) end

local tests = { "mile_1", "mile_2", "test_exp", "test_fun", "test_mem" }
local results = {
    -- output / input --
    {}, { "mornin' sailor!\n" },
    {}, { "working!\n" },
    { "working!\n", "working!\n" }
}
local fails = 0
for i, t in pairs(tests) do
    local cmd = "./bin/mossy ex/" .. t .. ".ms bin/tmp/" .. t
    local ok = os.execute(cmd)
    if not ok then
        print(t .. " failed on compilation")
        fails = fails + 1 
    else
        if #results[i] < 2 then
            ok = os.execute("./bin/tmp/" .. t .. " > " .. t .. ".log")
            if not ok then os.exit(1) end
        
            local log = io.open(t .. ".log") or os.exit(1)
            local res = log:read("a")
            log:close()
        
            if #results[i] == 0 and res ~= "" then
                res = res:gsub("\n", "\\n")
                print(t .. "'s ouput is incorrect: \"" .. res .. "\"")
                fails = fails + 1
            elseif #results[i] == 1 and res ~= results[i][1] then
                res = res:gsub("\n", "\\n")
                local expct = results[i][1]:gsub("\n", "\\n")
                print(t .. "'s ouput is incorrect:\n\tgot: \"" .. res .. "\"\n\texpected: \"" .. expct .. "\"")
                fails = fails + 1
            end
        else
            local input = io.open(t ..".input", "w")
            input:write(results[i][2])
            input:close()
            ok = os.execute("(./bin/tmp/" .. t .. " < " .. t .. ".input) > " .. t .. ".log")
            if not ok then os.exit(1) end

            local log = io.open(t .. ".log") or os.exit(1)
            local res = log:read("a")
            if res ~= results[i][2] then
                res = res:gsub("\n", "\\n")
                local expct = results[i][2]:gsub("\n", "\\n")
                print(t .. "'s ouput is incorrect:\n\tgot: \"" .. res .. "\"\n\texpected: \"" .. expct .. "\"")
                fails = fails + 1
            end
            os.remove(t .. ".input")
        end
        os.remove(t .. ".log")
    end
    io.write("\n")
end

local max = #tests
print((max - fails) .. " of " .. (max) .. " tests succeeded")
