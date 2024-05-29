#! /usr/bin/lua
local init = os.execute("./build.sh")
if not init then os.exit(1) end

local tests = { "mile_1", "mile_2", "test_exp", "test_fun" }
local results = { "", "mornin' sailor!\n", "", "working!\n" }
local fails = 0
for i, t in pairs(tests) do
    local cmd = "./bin/mossy ex/" .. t .. ".ms bin/tmp/" .. t
    local ok = os.execute(cmd)
    if not ok then
        print(t .. " failed on compilation")
        fails = fails + 1 
    else
        ok = os.execute("./bin/tmp/" .. t .. " > " .. t .. ".log")
        if not ok then os.exit(1) end
    
        local log = io.open(t .. ".log") or os.exit(1)
        local res = log:read("a")
        log:close()
    
        if res ~= results[i] then
            print(t .. "'s ouput is incorrect: \"" .. res .. "\"")
            fails = fails + 1
        end
        os.remove(t .. ".log")
    end
    print("\n")
end

local max = #tests
print((max - fails) .. " of " .. (max) .. " tests succeeded")
