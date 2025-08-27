#!/usr/bin/env lua
local tmp   = ".test/"
local time  = os.time()

-- test list --
local tests = {
    -- shadowing error --
    { src = "fail_mod_name_1", code = 1, nocomp = true },
    { src = "fail_mod_name_2", code = 1, nocomp = true },
    { src = "fail_fun_name_1", code = 1, nocomp = true },
    { src = "fail_fun_name_2", code = 1, nocomp = true },
    { src = "fail_var_name_1", code = 1, nocomp = true },
    { src = "fail_var_name_2", code = 1, nocomp = true },
    -- module error --
    { src = "fail_self-import", code = 1, nocomp = true },
    { src = "fail_recursive", code = 1, nocomp = true },
    { src = "fail_pub", code = 1, nocomp = true },
    -- effect system error --
    { src = "fail_efx_1", code = 1, nocomp = true },
    { src = "fail_efx_2", code = 1, nocomp = true },
    { src = "fail_efx_3", code = 1, nocomp = true },
    { src = "fail_map", code = 1, nocomp = true },
    { src = "fail_while", code = 1, nocomp = true },
    { src = "fail_tailcall_1", code = 1, nocomp = true },
    { src = "fail_tailcall_2", code = 1, nocomp = true },
    -- propagation error --
    { src = "fail_prop_1", code = 1, nocomp = true },
    { src = "fail_prop_2", code = 1, nocomp = true },
    { src = "fail_prop_3", code = 1, nocomp = true },
    -- type system error --
    { src = "fail_unused", code = 1, nocomp = true },
    { src = "fail_mut_1", code = 1, nocomp = true },
    { src = "fail_mut_2", code = 1, nocomp = true },
    { src = "fail_mut_3", code = 1, nocomp = true },
    { src = "fail_mut_4", code = 1, nocomp = true },
    { src = "fail_mut_5", code = 1, nocomp = true },
    { src = "fail_mut_6", code = 1, nocomp = true },
    { src = "fail_mut_7", code = 1, nocomp = true },
    { src = "fail_mut_8", code = 1, nocomp = true },
    { src = "fail_mut_9", code = 1, nocomp = true },
    { src = "fail_mut_10", code = 1, nocomp = true },
    { src = "fail_mut_11", code = 1, nocomp = true },
    { src = "fail_mut_12", code = 1, nocomp = true },
    { src = "fail_mut_13", code = 1, nocomp = true },
    { src = "fail_array_1", code = 1, nocomp = true },
    { src = "fail_array_2", code = 1, nocomp = true },
    { src = "fail_array_3", code = 1, nocomp = true },
    { src = "fail_array_4", code = 1, nocomp = true },
    { src = "fail_array_5", code = 1, nocomp = true },
    { src = "fail_array_6", code = 1, nocomp = true },
    { src = "fail_slice_1", code = 1, nocomp = true },
    { src = "fail_for_slice", code = 1, nocomp = true },
    { src = "fail_rec_1", code = 1, nocomp = true },
    { src = "fail_rec_2", code = 1, nocomp = true },
    { src = "fail_rec_3", code = 1, nocomp = true },
    { src = "fail_rec_4", code = 1, nocomp = true },
    { src = "fail_rec_5", code = 1, nocomp = true },
    { src = "fail_rec_6", code = 1, nocomp = true },
    { src = "fail_rec_7", code = 1, nocomp = true },
    { src = "fail_void_1", code = 1, nocomp = true },
    { src = "fail_void_2", code = 1, nocomp = true },
    -- memory error --
    { src = "fail_arena_1", code = 1, nocomp = true },
    { src = "fail_arena_2", code = 1, nocomp = true },
    { src = "fail_arena_3", code = 1, nocomp = true },
    { src = "fail_arena_4", code = 1, nocomp = true },
    { src = "fail_arena_5", code = 1, nocomp = true },
    { src = "fail_alloc", code = 1, nocomp = true },
    -- borrowing error --
    { src = "fail_borrow_1", code = 1, nocomp = true },
    { src = "fail_borrow_2", code = 1, nocomp = true },
    { src = "fail_borrow_3", code = 1, nocomp = true },
    { src = "fail_lifetime", code = 1, nocomp = true },
    { src = "fail_no_lifetime_1", code = 1, nocomp = true },
    { src = "fail_no_lifetime_2", code = 1, nocomp = true },
    { src = "fail_iterator_1", code = 1, nocomp = true },
    { src = "fail_iterator_2", code = 1, nocomp = true },
    -- statement behavior --
    { src = "fail_switch_1", code = 1, nocomp = true },
    { src = "fail_switch_2", code = 1, nocomp = true },
    { src = "fail_switch_3", code = 1, nocomp = true },
    { src = "fail_switch_4", code = 1, nocomp = true },
    { src = "fail_switch_5", code = 1, nocomp = true },
    { src = "fail_switch_6", code = 1, nocomp = true },
    { src = "fail_loop_op", code = 1, nocomp = true },
    { src = "fail_defer_1", code = 1, nocomp = true },
    { src = "fail_defer_2", code = 1, nocomp = true },
    { src = "fail_defer_3", code = 1, nocomp = true },
    -- issue fixing --
    { src = "fail_outlive_1", code = 1, nocomp = true },
    { src = "fail_outlive_2", code = 1, nocomp = true },
    { src = "fail_synax_1", code = 1, nocomp = true },
    { src = "issue_mut_loop", code = 0 },
    { src = "issue_for_slice", code = 0 },
    { src = "issue_lit_arr", code = 0 },
    -- fail assertion --
    { src = "fail_io_bad_handle",
        output = "../tests/fail_io_bad_handle.lic:7:33: assertion failed\n",
        code = 1 },
    { src = "fail_io_from_result",
        output = "../tests/fail_io_from_result.lic:14:19: assertion failed\n",
        code = 1 },
    { src = "no_prop", code = 0 },
    { src = "assert", output = "test 1 ok\ntest 2 ok\ntest 3 ok\n", code = 0 },
    { src = "test", output = "test ok\n", code = 0 },
    { src = "fail_test", output = "../tests/fail_test.lic:5:10: test ok\n", code = 1 },
    { src = "ret", code = 0 },
    -- others --
    { src = "fail_empty", code = 1, nocomp = true },
    { src = "fail_empty_assign", code = 1, nocomp = true },

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
    { src = "array_4", output = "test ok\n", code = 0 },
    { src = "rec_1", output = "test ok\n", code = 0 },
    { src = "rec_2", output = "test ok\n", code = 0 },
    { src = "rec_3", output = "test ok\n", code = 0 },
    { src = "rec_4", output = "test 1 ok\ntest 2 ok\n", code = 0 },
    { src = "rec_5", output = "test ok\n", code = 0 },
    { src = "rec_6", output = "test ok\n", code = 0 },
    { src = "rec_7", code = 0 },
    { src = "arr_rec", output = "test ok\n", code = 0 },
    { src = "str_fun", output = "test 1 ok\ntest 2 ok\ntest 3 ok\n", code = 0 },
    { src = "empty_assign", code = 0 },
    -- branching --
    { src = "if-else",
        output = "test 0 ok\ntest 1 ok\ntest 2 ok\ntest 3 ok\ntest 4 ok\ntest 5 ok\ntest 6 ok\n",
        code = 0 },
    { src = "switch",
        output = "test 1 ok\ntest 2 ok\ntest 3 ok\ntest 4 ok\n",
        code = 0 },
    { src = "for_loop", output = "mia\nleo\nlue\n", code = 0 },
    { src = "for_ops", code = 0 },
    { src = "for_str", code = 0 },
    { src = "str_array", code = 0 },
    { src = "defer_1", output = "second\nfirst\n", code = 0 },
    { src = "defer_2",
        output = "on call\non scope\nat scope exit\nat exit\n", code = 0 },
    { src = "defer_3",
        output = "on call\non scope\nat return\nat exit\n", code = 0 },
    { src = "defer_4",
        output = "at defer\n", code = 0 },
    { src = "defer_5",
        output = "printing names at exit\nmia\nleo\nlue\n", code = 0},
    { src = "while", code = 0 },
    { src = "cond_tailcall", code = 0 },
    -- type checking --
    { src = "types", code = 0 },
    { src = "exp", code = 0 },
    { src = "unit_1", code = 0 },
    { src = "unit_2", code = 0 },
    { src = "void_1", code = 0 },
    { src = "void_2", code = 1 },
    { src = "error", output = "test ok\n", code = 0 },
    { src = "unwrap", code = 0 },
    { src = "rec_unwrap_1", output = "test 1 ok\ntest 2 ok\n", code = 0 },
    { src = "rec_unwrap_2", output = "test 1 ok\ntest 2 ok\ntest 3 ok\n", code = 0 },
    { src = "fail_slice_2",
        output = "../tests/fail_slice_2.lic:7:30: assertion failed\n", code = 1 },
    { src = "map", output = "mia\nleo\nlue\n", code = 0 },
    { src = "safe_rec_mut", code = 0 },
    -- io --
    { src = "hello", output = "mornin' sailor!\n", code = 0 },
    -- mem --
    { src = "arena", code = 0 },
    { src = "arena_error_1",
        output = "../tests/arena_error_1.lic:10:6: assertion failed\n",
        code = 1 },
    { src = "arena_error_2", output = "test ok\n", code = 0 },
    { src = "borrow", output = "test ok\n", code = 0 },
    { src = "dynamic_array", code = 0 },
    { src = "dyarr_rec_1", code = 0 },
    { src = "dyarr_rec_2", code = 0 },
    { src = "dyarr_rec_3", code = 0 },
    { src = "alloc_rec", code = 0 },
    { src = "for_alloc", code = 0 },
    { src = "cat_1", code = 0 },
    { src = "cat_2", code = 0 },
    { src = "cat_3", code = 0 },
    { src = "cat_4", code = 0 },
    { src = "cat_5", output = "mia\nleo\nlue\nkim\n", code = 0 },
    { src = "cat_6", output = "a\nb\nc\n", code = 0 },
    -- complex structuring --
    { src = "stream", output = "mornin' sailor!\n", code = 0 },
}

local examples = {
    { src = "110",
    output = ". . . . . . . . . . . . . . # # \n" ..
        ". . . . . . . . . . . . . # # # \n" ..
        ". . . . . . . . . . . . # # . # \n" ..
        ". . . . . . . . . . . # # # # # \n" ..
        ". . . . . . . . . . # # . . . # \n" ..
        ". . . . . . . . . # # # . . # # \n" ..
        ". . . . . . . . # # . # . # # # \n" ..
        ". . . . . . . # # # # # # # . # \n" ..
        ". . . . . . # # . . . . . # # # \n" ..
        ". . . . . # # # . . . . # # . # \n" ..
        ". . . . # # . # . . . # # # # # \n" ..
        ". . . # # # # # . . # # . . . # \n" ..
        ". . # # . . . # . # # # . . # # \n" ..
        ". # # # . . # # # # . # . # # # \n" ..
        "# # . # . # # . . # # # # # . # \n" ..
        "# # # # # # # . # # . . . # # # \n", code = 0 },
    { src = "args", add_args = "-lc", argv = "hello!", output = "hello!\n", code = 0 },
    { src = "conv", input = "3\n7\n", output = "x = y = x + y = 10", code = 0 },
    { src = "ffi", add_args = "-lc", output = "mornin' sailor!\n", code = 0 },
    { src = "file", output = "test ok\n", code = 0 },
    { src = "hello", output = "mornin' sailor!\n", code = 0 },
    { src = "input", input = "mikaela", output = "type your name > hello, mikaela!\n", code = 0 },
    { src = "maker", output = "mornin' sailor!\n", code = 0 },
}

-- helpers --
local function exec(cmd)
    return os.execute(cmd)
end

local function run(cmd)
    local ok = os.execute(cmd)
    if not ok then os.exit(1) end
end

local function run_test(t, failed, ex)
    local bin = tmp .. t.src
    local args = "-t " .. (t.add_args or "")
    local ok = nil
    if ex then
        ok = exec("lcc ".. args .. " ../ex/" .. t.src .. ".lic " .. bin .. " > " .. tmp .. "compiler.log 2>&1")
    else
        ok = exec("lcc ".. args .. " ../tests/" .. t.src .. ".lic " .. bin .. " > " .. tmp .. "compiler.log 2>&1")
    end

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
            ok = exec("cat " .. tmp .. t.src .. ".input | " .. bin .. (t.argv or "") .. " > " .. log .. " 2>&1")
        else
            ok = exec(bin .. (t.argv or "") .. " > " .. log .. " 2>&1")
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

local function filter(t, pre)
    local new = {}
    for i in ipairs(t) do
        if pre(t[i]) then
            table.insert(new, t[i])
        end
    end
    return new
end

local function isin(t, val)
    for _, i in ipairs(t) do
        if i.src == val then return true end
    end
    return false
end

-- setup --
run("mkdir -p " .. tmp)

local failed = {}
local running_ex = false

-- run an specific set of tests
if arg[1] ~= nil then
    if arg[1] == "examples" then
        running_ex = true
        for i, t in ipairs(examples) do
            io.write(string.format("\rrunning tests (%d/%d)", i, #examples))
            io.flush()
            run_test(t, failed, true)
        end
    else
        for i = 1, #arg do
            if not isin(tests, arg[i]) then
                print("test \"" .. arg[i] .. "\" not found")
                os.exit(1)
            end
        end
        tests = filter(tests, function(t)
            for i = 1, #arg do
                if arg[i] == t.src then return true end
            end
            return false
        end)
    end
end

if not running_ex then
    -- run each test --
    for i, t in ipairs(tests) do
        io.write(string.format("\rrunning tests (%d/%d)", i, #tests))
        io.flush()
        run_test(t, failed)
    end
end

-- summary --
local passed = 0
local total  = 0
if not running_ex then
    passed = #tests - #failed
    total = #tests
else
    passed = #examples - #failed
    total = #examples
end
print(string.format("\r%d of %d tests succeeded in %.2f seconds", passed, total, os.time() - time))

if #failed > 0 then
    for i, e in ipairs(failed) do
        print("- fail " .. i .. ": " .. e)
    end
    os.exit(4)
else
    run("rm -r " .. tmp)
    run("rm -r lcc_temp/")
end
