local M = {}

local function has_tests(bufnr)
   local lang_tree = vim.treesitter.get_parser(bufnr, "rust")
   local syntax_tree = lang_tree:parse()
   local root = syntax_tree[1]:root()

   local query = vim.treesitter.query.parse("rust", [[
      (attribute_item
         (attribute
            (identifier) @attribute_name (#eq? @attribute_name "cfg")
            (token_tree
               (identifier) @attribute_argument (#eq? @attribute_argument "test")
            )
         )
      ) @attribute
   ]])

   local id,node,_metadata = query:iter_captures(root, bufnr, 0, -1)()
   if node == nil then
      return false, nil
   end
   local test_mod = node:next_sibling()
   if test_mod == nil then
      return false, nil
   end
   return true,test_mod:start()
end

local function show_diagnostic(source_buf, ns, line_test_mod, msg, severity)
   local diag = { {
         bufnr = source_buf,
         lnum = line_test_mod,
         col = -1,
         severity = severity,
         message = msg,
         code = "Hint",
      } }
      vim.diagnostic.set(ns, source_buf, diag, {})
end

local function cur_dir_is_in_project_folder(file_path)
   local cur_dir = vim.loop.cwd() .. "/"
   local dir, file = file_path:match('(.*/)(.*)')
   if dir:find(cur_dir) ~= nil then
      
      if vim.loop.fs_stat(cur_dir .. "Cargo.toml") or string.find(file, "src") ~= nil then
         return true
      end
   end

   return false
end

function M.setup()
   vim.api.nvim_create_autocmd("BufWritePost", {
      group = vim.api.nvim_create_augroup("ic0r", { clear = true }),
      pattern = "*.rs",
      callback = function()
         local ns = vim.api.nvim_create_namespace("ic0r")
         local source_buf = vim.api.nvim_get_current_buf()
         vim.api.nvim_buf_clear_namespace(source_buf, ns, 0, -1)
         vim.api.nvim_buf_clear_namespace(source_buf, ns, 0, -1)
         vim.diagnostic.reset(ns, source_buf)

         local has_t, line_test_mod = has_tests(source_buf)
         if not has_t then
            return
         end
         
         local fullpath = vim.api.nvim_buf_get_name(source_buf)
         if not cur_dir_is_in_project_folder(fullpath) then
            show_diagnostic(source_buf, ns, line_test_mod, "Change into project directory to get instant test feedback", vim.diagnostic.severity.HINT)
            return
         end
         
         local buf_lines = vim.api.nvim_buf_get_lines(source_buf, 0, -1, false)
         local fails = {}
         local fail_count = 0
         local succ_count = 0
         vim.fn.jobstart({ "cargo", "test" }, {
            stdout_buffered = true,
            on_stdout = function(_, data)
               for _,line in ipairs(data) do
                  local _, _, test_name = string.find(line, "test %a+::(.*) ... ok")
                  local tmp = nil
                  local success = false
                  if test_name == nil then
                     _, _, test_name = string.find(line, "test %a+::(.*) ... FAILED")
                     if test_name ~= nil then
                        tmp = "❌"
                        fail_count = fail_count + 1
                     end
                  else
                     tmp = "✅"
                     succ_count = succ_count + 1
                     success = true
                  end
                  if tmp then
                     for idx,buf_line in ipairs(buf_lines) do
                        local startidx,_ = string.find(buf_line, "fn " .. test_name)
                        if startidx then
                           --vim.api.nvim_buf_set_lines(source_buf, idx-1, idx, false, {buf_line .. " " .. tmp})
                              vim.api.nvim_buf_set_extmark(source_buf, ns, idx-1, 0, {
                                 virt_text = { { tmp, "Test" } },
                              })
                              if not success then
                                 table.insert(fails, {
                                    bufnr = source_buf,
                                    lnum = idx-1,
                                    col = -1,
                                    severity = vim.diagnostic.severity.ERROR,
                                    message = "Test failed",
                                    source = "cargo test",
                                    code = test_name,
                                    user_data = { test_name = test_name }
                                 })
                              end
                        end
         --[[
    bufnr: Buffer number
    lnum(+): The starting line of the diagnostic
    end_lnum: The final line of the diagnostic
    col(+): The starting column of the diagnostic
    end_col: The final column of the diagnostic
    severity: The severity of the diagnostic |vim.diagnostic.severity|
    message(+): The diagnostic text
    source: The source of the diagnostic
    code: The diagnostic code
    user_data: Arbitrary data plugins or users can add
   --]]
                     end
                  end
               end
            end,

            -- "cargo test" exited
            on_exit = function()
               if #fails > 0 then
                  local info_string = "["
                  for i,fail in ipairs(fails) do
                     info_string = info_string .. fail.user_data.test_name
                     if i ~= #fails then
                        info_string = info_string .. ", "
                     end
                  end
                  info_string = info_string .. "]"
                  table.insert(fails, {
                     bufnr = source_buf,
                     lnum = line_test_mod,
                     col = -1,
                     severity = vim.diagnostic.severity.ERROR,
                     message = info_string,
                     source = "cargo test",
                     code = "Failed tests",
                  })
                  --]]
                  -- Diagnostics next to failed tests
                  vim.diagnostic.set(ns, source_buf, fails, {})
               end
               -- Success/Fail ratio text next to beginning of test module
               vim.api.nvim_buf_set_extmark(source_buf, ns, line_test_mod, 0, {
                  virt_text = { { succ_count .. "/" .. (succ_count+fail_count) .. " tests passed", "Test" } },
               })
            end
         })
      end
   })
end

M.setup()

return M
