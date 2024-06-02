#! /usr/bin/lua
function exec(cmd)
    print("+ " .. cmd)
    return os.execute(cmd)
end

local tmp = ".test/"

local init = exec("./build.sh")
if not init then os.exit(1) end

local tdir = exec("mkdir -p " .. tmp)
if not tdir then os.exit(1) end

local tests = { "mile_1", "mile_2", "mile_3", "mile_3", "mile_3", "test_exp", "test_fun", "test_mem", "demo" }
local results = {
    {},                             -- mile_1
    { "mornin' sailor!\n" },        -- mile_2
    { "hi\n", "hiii!\n" },          -- mile_3
    { "bye\n", "bye bye!\n" },
    { "yo\n", "hop!\n" },
    {},                             -- test_exp
    { "working!\n" },               -- test_fun
    { "working!\n", "working!\n" }, -- test_mem
    { "mornin' sailor!\n" },        -- demo
}
local fails = 0
local failed = {}
for i, t in pairs(tests) do
    local cmd = "./bin/mossy ex/" .. t .. ".ms " .. tmp .. t
    local ok = exec(cmd)
    if not ok then
        failed[#failed + 1] = t .. " failed on compilation"
        fails = fails + 1 
    else
        if #results[i] <= 1 then
            ok = exec(tmp .. t .. " > " .. tmp .. t .. ".log")
            if not ok then os.exit(1) end
        
            local log = io.open(tmp .. t .. ".log") or os.exit(1)
            local res = log:read("a")
            log:close()
        
            if #results[i] == 0 and res ~= "" then
                res = res:gsub("\n", "\\n")
                failed[#failed + 1] = t .. "'s ouput is incorrect: \"" .. res .. "\""
                fails = fails + 1
            elseif #results[i] == 1 and res ~= results[i][1] then
                res = res:gsub("\n", "\\n")
                local expct = results[i][1]:gsub("\n", "\\n")
                failed[#failed + 1] = t .. "'s ouput is incorrect:\n\tgot: \"" .. res .. "\"\n\texpected: \"" .. expct .. "\""
                fails = fails + 1
            end
        else
            local input = io.open(tmp .. t ..".input", "w")
            input:write(results[i][1])
            input:close()
            ok = exec("(" .. tmp .. t .. " < " .. tmp .. t .. ".input) > " .. tmp .. t .. ".log")
            if not ok then os.exit(1) end

            local log = io.open(tmp .. t .. ".log") or os.exit(1)
            local res = log:read("a")
            if res ~= results[i][2] then
                res = res:gsub("\n", "\\n")
                local expct = results[i][2]:gsub("\n", "\\n")
                failed[#failed + 1] = t .. "'s ouput is incorrect:\n\tgot: \"" .. res .. "\"\n\texpected: \"" .. expct .. "\""
                fails = fails + 1
            end
        end
    end
    io.write("\n")
end

local max = #tests
print((max - fails) .. " of " .. (max) .. " tests succeeded")

if fails > 0 then
    for i, err in pairs(failed) do
        print("- fail " .. (i) .. ": " .. err)
    end
end
