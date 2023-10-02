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
      )
   ]])

   local id,_node,_metadata = query:iter_captures(root, bufnr, 0, -1)()
   return id ~= nil
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

         if not has_tests(source_buf) then
            return
         end
  
         local buf_lines = vim.api.nvim_buf_get_lines(source_buf, 0, -1, false)
         local fails = {}
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
                     end
                  else
                     tmp = "✅"
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
                     --vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, {tmp})
                  end
               end
               --vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, data)
            end,

            -- "cargo test" exited
            on_exit = function()
               vim.diagnostic.set(ns, source_buf, fails, {})
            end
         })
      end
   })
end

M.setup()

return M
