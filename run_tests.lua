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
    { src = "fail_rec_1", code = 1, nocomp = true },
    { src = "fail_rec_2", code = 1, nocomp = true },
    { src = "fail_rec_3", code = 1, nocomp = true },
    { src = "fail_rec_4", code = 1, nocomp = true },
    { src = "fail_rec_5", code = 1, nocomp = true },
    { src = "fail_rec_6", code = 1, nocomp = true },
    { src = "fail_rec_7", code = 1, nocomp = true },
    { src = "fail_void_1", code = 1, nocomp = true },
    { src = "fail_void_2", code = 1, nocomp = true },
    { src = "fail_pub", code = 1, nocomp = true },
    { src = "fail_arena_1", code = 1, nocomp = true },
    { src = "fail_arena_2", code = 1, nocomp = true },
    { src = "fail_arena_3", code = 1, nocomp = true },
    { src = "fail_arena_4", code = 1, nocomp = true },
    { src = "fail_outlive_1", code = 1, nocomp = true },
    { src = "fail_outlive_2", code = 1, nocomp = true },
    { src = "fail_borrow", code = 1, nocomp = true },
    -- fail assertion --
    { src = "fail_io_bad_handle", code = 1, nocomp = false },
    { src = "fail_io_from_result", code = 1, nocomp = false },
    { src = "no_prop", code = 0 },
    { src = "assert", output = "test 1 ok\ntest 2 ok\ntest 3 ok\n", code = 0 },
    { src = "test", output = "test ok\n", code = 0 },
    { src = "fail_test", code = 1 },
    -- parser --
    { src = "vars", code = 0 },
    { src = "funcs", code = 0 },
    { src = "underscore", code = 0 },
    { src = "float", output = "test ok\n", code = 0 },
    { src = "mut", code = 0 },
    { src = "strings", output = "test ok\n", code = 0 },
    { src = "array_1", code = 0 },
    { src = "array_2", output = "test ok\n", code = 0 },
    { src = "array_3", output = "test 1 ok\ntest 2 ok\n", code = 0 },
    { src = "rec_1", output = "test ok\n", code = 0 },
    { src = "rec_2", output = "test ok\n", code = 0 },
    { src = "rec_3", output = "test ok\n", code = 0 },
    { src = "rec_4", output = "test 1 ok\ntest 2 ok\n", code = 0 },
    { src = "rec_5", output = "test ok\n", code = 0 },
    { src = "rec_6", output = "test ok\n", code = 0 },
    { src = "arr_rec", output = "test ok\n", code = 0 },
    { src = "str_fun", output = "test 1 ok\ntest 2 ok\ntest 3 ok\n", code = 0 },
    -- branching --
    { src = "if-else",
        output = "test 0 ok\ntest 1 ok\ntest 2 ok\ntest 3 ok\ntest 4 ok\ntest 5 ok\ntest 6 ok\n",
        code = 0 },
    -- type checking --
    { src = "types", code = 0 },
    { src = "exp", code = 0 },
    { src = "unit", code = 0 },
    { src = "void_1", code = 0 },
    { src = "void_2", code = 1 },
    { src = "error", output = "test ok\n", code = 0 },
    { src = "unwrap", code = 0 },
    { src = "rec_unwrap", output = "test 1 ok\ntest 2 ok\n", code = 0 },
    -- io --
    { src = "hello", output = "mornin' sailor!\n", code = 0 },
    -- mem --
    { src = "arena", code = 0 },
    { src = "arena_error_1", code = 1 },
    { src = "arena_error_2", output = "test ok\n", code = 0 },
    { src = "borrow", output = "test ok\n", code = 0 },
}

-- helpers --
local function exec(cmd, silent)
    if not silent then print("+ " .. cmd) end
    return os.execute(cmd)
end

local function run(cmd)
    if not exec(cmd, true) then os.exit(1) end
end

local function run_test(t, failed)
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
end

function filter(t, pre)
    local new = {}
    for i in ipairs(t) do
        if pre(t[i]) then
            table.insert(new, t[i])
        end
    end
    return new
end


-- setup --
run("./install.sh")
run("mkdir -p " .. tmp)

local failed = {}

-- run an specific set of tests
if arg[1] ~= nil then
    tests = filter(tests, function(t)
        for i = 1, #arg do
            if arg[i] == t.src then return true end
        end
        return false
    end)
end

-- run each test --
for _, t in ipairs(tests) do
    run_test(t, failed)
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
