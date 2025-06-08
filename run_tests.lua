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
    -- fails --
    { src = "empty", input = "", output = "", code = 1, nocomp = true },
    { src = "fail_mod_name_1", input = "", output = "", code = 1, nocomp = true },
    { src = "fail_mod_name_2", input = "", output = "", code = 1, nocomp = true },
    { src = "fail_fun_name_1", input = "", output = "", code = 1, nocomp = true },
    { src = "fail_fun_name_2", input = "", output = "", code = 1, nocomp = true },
    { src = "fail_var_name_1", input = "", output = "", code = 1, nocomp = true },
    { src = "fail_var_name_2", input = "", output = "", code = 1, nocomp = true },
    { src = "self-import", input = "", output = "", code = 1, nocomp = true },
    { src = "prop_error", input = "", output = "", code = 1, nocomp = true },

    -- syntax and type checking --
    { src = "vars", input = "", output = "", code = 0, nocomp = false },
    { src = "globs", input = "", output = "", code = 0, nocomp = false },
    { src = "funcs", input = "", output = "", code = 0, nocomp = false },
    { src = "types", input = "", output = "", code = 0, nocomp = false },
    { src = "exp", input = "", output = "", code = 0, nocomp = false },
    { src = "strings", input = "", output = "ok\n", code = 0, nocomp = false },
    { src = "oper", input = "", output = "", code = 0, nocomp = false },
    { src = "bool", input = "", output = "", code = 0, nocomp = false },
    { src = "math", input = "", output = "test ok\n", code = 0, nocomp = false },
    { src = "floats", input = "", output = "test ok\n", code = 0, nocomp = false },
    { src = "arrays", input = "", output = "test ok!\n", code = 0, nocomp = false },

    -- io and effects --
    { src = "hello", input = "", output = "mornin' sailor!\n", code = 0, nocomp = false },
    { src = "mods", input = "", output = "mornin' sailor!\n", code = 0, nocomp = false },
    { src = "reply", input = "mika", output = "hi! what's your name?\n > hello, mika", code = 0, nocomp = false },
    { src = "files", input = "", output = "", code = 0, nocomp = false },

    -- branching and recursion --
    { src = "if-else", input = "", output = "test 0 ok\ntest 1 ok\ntest 2 ok\ntest 3 ok\n" ..
        "test 4 ok\ntest 5 ok\ntest 6 ok\n", code = 0, nocomp = false },
    { src = "recursive", input = "", output = "worked!\n", code = 0, nocomp = false },
    { src = "tailcall", input = "", output = "loop!\nloop!\nloop!\nloop!\n", code = 0, nocomp = false },
    { src = "map", input = "", output = "hello, mia!\nhello, maya!\nhello, mei!\n" ..
        "no one is on the left\nmia is at the middle\nand maya is at right of mia\n"..
        "mia is at left of maya\nmaya is at the middle\nand mei is at right of maya\n"..
        "maya is at left of mei\nmei is at the middle\nand no one is on the right\n", code = 0, nocomp = false },
    { src = "reduce", input = "", output = "test ok!\n", code = 0, nocomp = false },

    -- tagged unions and error types --
    { src = "error", input = "", output = "", code = 1, nocomp = false },
    { src = "fail_fs", input = "", output = "", code = 1, nocomp = false },
    { src = "fail_io", input = "", output = "", code = 1, nocomp = false },

    -- miscellany --
    { src = "test-block", input = "", output = "", code = 0, nocomp = false },
}

local failed = {}
for _, test in pairs(tests) do
    local cmd = "lcc " .. flags .. " tests/" .. test.src .. ".lic " .. tmp .. test.src
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
        if not ran and test.code == 0 then
            failed[#failed + 1] = "test \""  .. test.src .. "\" exit code: " .. (sig)
        elseif ran and test.code ~= 0 then
            failed[#failed + 1] = "test \""  .. test.src .. "\" had an exit code of 0 (should be " 
                .. (test.code) .. ")"
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
print((max - #failed) .. " of " .. (max) .. " tests succeeded in " .. (os.clock() - time) .. " seconds")

if #failed > 0 then
    for i, err in pairs(failed) do
        print("- fail " .. (i) .. ": " .. err)
    end
    os.exit(1)
else
    run("rm -r " .. tmp)
    run("rm -r tmp/")
end

