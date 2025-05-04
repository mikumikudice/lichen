#! /usr/bin/lua
function exe_cmd(cmd, silent)
    if not silent then print("+ " .. cmd) end
    return os.execute(cmd)
end

function run(cmd)
    if not exe_cmd(cmd, true) then os.exit(1) end
end

local tmp = ".test/"
local flags = "-std lib/ -vb -t"

local time = os.clock()
run("./install.sh")
--run("./hare_test.sh")
run("mkdir -p " .. tmp)

local tests = {
    { src = "empty", input = "", output = "", code = 1, nocomp = true },
    { src = "vars", input = "", output = "", code = 0, nocomp = false },
    { src = "funcs", input = "", output = "", code = 0, nocomp = false },
    { src = "hello", input = "", output = "mornin' sailor!\n", code = 0, nocomp = false },
    { src = "mods", input = "", output = "mornin' sailor!\n", code = 0, nocomp = false },
    { src = "types", input = "", output = "", code = 0, nocomp = false },
    { src = "exp", input = "", output = "", code = 0, nocomp = false },
    { src = "reply", input = "mika", output = "hi! what's your name?\n > hello, mika", code = 0, nocomp = false },
}

local failed = {}
for _, test in pairs(tests) do
    local cmd = "mmc " .. flags .. " tests/" .. test.src .. ".ms " .. tmp .. test.src
    local ok = exe_cmd(cmd)
    if not ok and not test.nocomp then
        failed[#failed + 1] = test.src .. " failed at compilation"
    elseif ok and test.nocomp then
        failed[#failed + 1] = test.src .. " (a fail test) compiled"
    elseif ok then
        if test.input == "" then
            cmd = tmp .. test.src .. " > " .. tmp .. test.src .. ".log"
        else
            local input = io.open(tmp .. test.src ..".input", "w") or os.exit(1)
            input:write(test.input)
            input:close()
            cmd = "cat " .. tmp .. test.src .. ".input | " .. tmp .. test.src ..
                " > " .. tmp .. test.src .. ".log"
        end
        local ran, _, sig = exe_cmd(cmd)
        if not ran then
            failed[#failed + 1] = "test \""  .. test.src .. "\" exit code: " .. (sig)
        else
            local log = io.open(tmp .. test.src .. ".log") or os.exit(1)
            local res = log:read("a")
            log:close()

            if test.output ~= res then
                res = res:gsub("\n", "\\n")
                local expected = test.output:gsub("\n", "\\n")
                failed[#failed + 1] = test.src .. "'s ouput is incorrect:\nexpected:\t\"" ..
                    expected .. "\" (len: " .. (#expected) .. ")\n" .. "got:\t\t\"" .. res ..
                    "\" (len: " .. (#res) .. ")"
            end
        end
    end
    io.write("\n")
end

local max = #tests
time = os.clock() - time
print((max - #failed) .. " of " .. (max) .. " tests succeeded in " .. (time) .. " seconds")

if #failed > 0 then
    for i, err in pairs(failed) do
        print("- fail " .. (i) .. ": " .. err)
    end
    os.exit(1)
else
    --run("rm -r " .. tmp)
    --run("rm -r .tmp/")
end

