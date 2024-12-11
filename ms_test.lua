#! /usr/bin/lua
function exec(cmd, silent)
    if not silent then print("+ " .. cmd) end
    return os.execute(cmd)
end

local tmp = ".test/"
local flags = "-l lib/ -vb"

local init = exec("./build.sh")
if not init then os.exit(1) end

local tdir = exec("mkdir -p " .. tmp)
if not tdir then os.exit(1) end

local tests = { "vars", "files", "console", "branching", "math", "expressions" }
local results = {
    {},
    {},
    { "mikaela\n", "what's your name?\n> hello, mikaela!\n" },
    { "test 1 ok\ntest 2 ok\ntest 3 ok\ntest 4 ok\n" },
    { "test ok\n" },
    { "test 1 ok\ntest 2 ok\n" },
    {},
}
local fails = 0
local failed = {}
for i, t in pairs(tests) do
    local cmd = "./bin/mossy " .. flags .. " tests/" .. t .. ".ms " .. tmp .. t
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
            else
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
            end
        elseif #results[i] == 2 then
            local input = io.open(tmp .. t ..".input", "w") or os.exit(1)
            input:write(results[i][1])
            input:close()
            local ran, _, sig = exec("(" .. tmp .. t .. " < " .. tmp .. t .. ".input) > " .. tmp .. t .. ".log")
            if not ran then
                failed[#failed + 1] = t .. "'s exit code: " .. (sig)
                fails = fails + 1
            else
                local log = io.open(tmp .. t .. ".log") or os.exit(1)
                local res = log:read("a")
                if res ~= results[i][2] then
                    res = res:gsub("\n", "\\n")
                    local expct = results[i][2]:gsub("\n", "\\n")
                    failed[#failed + 1] = t .. "'s ouput is incorrect:\n\tgot: \"" .. res .. "\"\n\texpected: \"" .. expct .. "\""
                    fails = fails + 1
                end
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
            local ran, _, sig = exec("cat" .. argl .. " | " .. tmp .. t .. " > " .. tmp .. t .. ".log")
            if not ran then
                failed[#failed + 1] = "exit code: " .. (sig)
                fails = fails + 1
            else
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
    end
    io.write("\n")
end

local max = #tests
print((max - fails) .. " of " .. (max) .. " tests succeeded")

if fails > 0 then
    for i, err in pairs(failed) do
        print("- fail " .. (i) .. ": " .. err)
    end
    os.exit(1)
end

exec("rm -r " .. tmp, true)
exec("rm -r .tmp/", true)
