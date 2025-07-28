#!/usr/bin/env lua
local tmp   = ".test/"
local flags = "-std lib/ -verbose -t"
local time  = os.clock()

-- test list --
local tests = {
    -- compilation error --
    { src = "fail_empty", code = 1, nocomp = true },
    { src = "fail_mod_name_1", code = 1, nocomp = true },
    { src = "fail_mod_name_2", code = 1, nocomp = true },
    { src = "fail_fun_name_1", code = 1, nocomp = true },
    { src = "fail_fun_name_2", code = 1, nocomp = true },
    { src = "fail_var_name_1", code = 1, nocomp = true },
    { src = "fail_var_name_2", code = 1, nocomp = true },
    { src = "fail_self-import", code = 1, nocomp = true },
    { src = "fail_efx_1", code = 1, nocomp = true },
    { src = "fail_efx_2", code = 1, nocomp = true },
    { src = "fail_efx_3", code = 1, nocomp = true },
    { src = "fail_prop_1", code = 1, nocomp = true },
    { src = "fail_prop_2", code = 1, nocomp = true },
    { src = "fail_prop_3", code = 1, nocomp = true },
    { src = "fail_unused", code = 1, nocomp = true },
    { src = "fail_mut_1", code = 1, nocomp = true },
    { src = "fail_mut_2", code = 1, nocomp = true },
    { src = "fail_mut_3", code = 1, nocomp = true },
    { src = "fail_mut_4", code = 1, nocomp = true },
    { src = "fail_array_1", code = 1, nocomp = true },
    { src = "fail_array_2", code = 1, nocomp = true },
    { src = "fail_array_3", code = 1, nocomp = true },
    { src = "fail_array_4", code = 1, nocomp = true },
    { src = "fail_array_5", code = 1, nocomp = true },
    { src = "fail_void_1", code = 1, nocomp = true },
    { src = "fail_void_2", code = 1, nocomp = true },
    -- fail assertion --
    { src = "fail_io_bad_handle", code = 1, nocomp = false },
    { src = "fail_io_from_result", code = 1, nocomp = false },
    { src = "no_prop", code = 0 },
    { src = "assert", output = "test 1 ok\ntest 2 ok\ntest 3 ok\n", code = 0 },
    -- parser --
    { src = "vars", code = 0 },
    { src = "funcs", code = 0 },
    { src = "underscore", code = 0 },
    { src = "float", output = "test ok\n", code = 0 },
    { src = "mut", code = 0 },
    { src = "strings", output = "test ok\n", code = 0 },
    { src = "array", code = 0 },
    { src = "rec_1", output = "test ok\n", code = 0 },
    { src = "rec_2", output = "test ok\n", code = 0 },
    { src = "rec_3", output = "test ok\n", code = 0 },
    { src = "rec_4", output = "test 1 ok\ntest 2 ok\n", code = 0 },
    -- branching --
    { src = "if-else",
        output = "test 0 ok\ntest 1 ok\ntest 2 ok\ntest 3 ok\ntest 4 ok\ntest 5 ok\ntest 6 ok\n",
        code = 0 },
    -- type checking --
    { src = "unit", code = 0 },
    { src = "void", code = 0 },
    { src = "types", code = 0 },
    { src = "exp", code = 0 },
    { src = "unwrap", code = 0 },
    { src = "rec_unwrap", output = "test ok\n", code = 0 },
    -- io --
    { src = "hello", output = "mornin' sailor!\n", code = 0 },
    -- others --
    { src = "stress",
        output = "branch 1 ok\ny is even\ncomputing factorial...\nfactorial(5) ok\nresult is:\nz computed ok\n", 
        code = 0 },
}

-- helpers --
local function exec(cmd, silent)
    if not silent then print("+ " .. cmd) end
    return os.execute(cmd)
end

local function run(cmd)
    if not exec(cmd, true) then os.exit(1) end
end

-- setup --
run("./install.sh")
run("mkdir -p " .. tmp)

local failed = {}

-- run each test --
for _, t in ipairs(tests) do
    local bin = tmp .. t.src
    local ok  = exec("lcc " .. flags .. " tests/" .. t.src .. ".lic " .. bin)

    if not ok and not t.nocomp then
        table.insert(failed, t.src .. " failed at compilation")
    elseif ok and t.nocomp then
        table.insert(failed, t.src .. " (a fail test) compiled")
    elseif ok then
        local log = tmp .. t.src .. ".log"

        if t.input and t.input ~= "" then
            local f = assert(io.open(tmp .. t.src .. ".input", "w"))
            f:write(t.input)
            f:close()
            ok = exec("cat " .. tmp .. t.src .. ".input | " .. bin .. " > " .. log)
        else
            ok = exec(bin .. " > " .. log)
        end

        local result   = io.open(log):read("a"):gsub("\n", "\\n")
        local expected = (t.output or ""):gsub("\n", "\\n")

        if (t.code == 0 and not ok) or (t.code ~= 0 and ok) then
            table.insert(failed, string.format('test "%s" wrong exit code', t.src))
        elseif expected ~= result then
            table.insert(failed, string.format(
                "%s's output is incorrect:\nexpected:\t\"%s\" (len:%d)\ngot:\t\t\"%s\" (len:%d)",
                t.src, expected, #expected, result, #result ))
        end
    end

    io.write("\n")
end

-- summary --
local passed = #tests - #failed
local total  = #tests
print(string.format("%d of %d tests succeeded in %.2f seconds", passed, total, os.clock() - time))

if #failed > 0 then
    for i, e in ipairs(failed) do
        print("- fail " .. i .. ": " .. e)
    end
    os.exit(1)
else
    run("rm -r " .. tmp)
    run("rm -r lcc_temp/")
end