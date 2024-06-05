#! /usr/bin/lua
function exec(cmd)
    print("+ " .. cmd)
    return os.execute(cmd)
end

local tmp = ".test/"
local flags = "-l lib/ -v"

local init = exec("./build.sh")
if not init then os.exit(1) end

local tdir = exec("mkdir -p " .. tmp)
if not tdir then os.exit(1) end

local tests = { "test_exp", "test_fun", "test_mem", "test_glob", "demo", "test_loop", "test_fmt", "test_if" }
local results = {
    {},                                                     -- test_exp
    { "working!\n" },                                       -- test_fun
    { "working!\n", "working!\n" },                         -- test_mem
    {},                                                     -- test_glob
    { "mornin' sailor!\n" },                                -- demo
    { "hi!\nhoy!\nhi!\nhoy!\nhi!\nyay!\nyay!\nyay!\n" },    -- loop
    { "128\n", "128\n128 + 2 = 130\n" },                    -- test_fmt
    { "5\n", "3\n", "if!\n" },                              -- test_if
    { "3\n", "4\n", "else if!\n" },
    { "1\n", "0\n", "else!\n" },
}
local fails = 0
local failed = {}
for i, t in pairs(tests) do
    local cmd = "./bin/mossy " .. flags .. " ex/" .. t .. ".ms " .. tmp .. t
    local ok = exec(cmd)
    if not ok then
        failed[#failed + 1] = t .. " failed on compilation"
        fails = fails + 1 
    else
        if #results[i] <= 1 then
            local ran, _, sig = exec(tmp .. t .. " > " .. tmp .. t .. ".log")
            if not ran then
                failed[#failed + 1] = "exit code: " .. (sig)
                fails = fails + 1
            end

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
        elseif #results[i] == 2 then
            local input = io.open(tmp .. t ..".input", "w") or os.exit(1)
            input:write(results[i][1])
            input:close()
            local ran, _, sig = exec("(" .. tmp .. t .. " < " .. tmp .. t .. ".input) > " .. tmp .. t .. ".log")
            if not ran then
                failed[#failed + 1] = t .. "'s exit code: " .. (sig)
                fails = fails + 1
            end

            local log = io.open(tmp .. t .. ".log") or os.exit(1)
            local res = log:read("a")
            if res ~= results[i][2] then
                res = res:gsub("\n", "\\n")
                local expct = results[i][2]:gsub("\n", "\\n")
                failed[#failed + 1] = t .. "'s ouput is incorrect:\n\tgot: \"" .. res .. "\"\n\texpected: \"" .. expct .. "\""
                fails = fails + 1
            end
        else
            local argl = ""
            for c = 1, (#results[i] - 1) do
                local fname = tmp .. t ..".input." .. (c)
                argl = argl .. " " .. fname
                local input = io.open(fname, "w") or os.exit(1)
                input:write(results[i][c])
                input:close()
            end
            local ran, _, sig = exec("(cat" .. argl .. " | " .. tmp .. t .. ") > " .. tmp .. t .. ".log")
            if not ran then
                failed[#failed + 1] = "exit code: " .. (sig)
                fails = fails + 1
            end

            local log = io.open(tmp .. t .. ".log") or os.exit(1)
            local res = log:read("a")
            if res ~= results[i][#results[i]] then
                res = res:gsub("\n", "\\n")
                local expct = results[i][#results[i]]:gsub("\n", "\\n")
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

os.remove(".test/")
