-- Unit tests for output parser
local parser = require('tsc.core.parser')

describe('OutputParser', function()
  describe('parse_error_line', function()
    it('should parse standard TypeScript error', function()
      local line = 'src/index.ts(10,5): error TS2322: Type "string" is not assignable to type "number".'
      local error = parser.parse_error_line(line)
      
      assert.is_table(error)
      assert.equal('src/index.ts', error.filename)
      assert.equal(10, error.lnum)
      assert.equal(5, error.col)
      assert.equal('error TS2322: Type "string" is not assignable to type "number".', error.text)
      assert.equal('E', error.type)
      assert.equal(1, error.valid)
    end)
    
    it('should parse error with Windows path', function()
      local line = 'C:\\project\\src\\index.ts(25,10): error TS2339: Property "foo" does not exist on type "Bar".'
      local error = parser.parse_error_line(line)
      
      assert.is_table(error)
      assert.equal('C:\\project\\src\\index.ts', error.filename)
      assert.equal(25, error.lnum)
      assert.equal(10, error.col)
    end)
    
    it('should return nil for non-error lines', function()
      local lines = {
        'Found 5 errors in 2 files.',
        'Watching for file changes.',
        '',
        'TypeScript compilation complete',
      }
      
      for _, line in ipairs(lines) do
        assert.is_nil(parser.parse_error_line(line))
      end
    end)
  end)
  
  describe('parse_output', function()
    it('should parse multiple errors', function()
      local output = {
        'src/index.ts(10,5): error TS2322: Type "string" is not assignable to type "number".',
        'src/utils.ts(20,10): error TS2339: Property "foo" does not exist on type "Bar".',
        'src/types.ts(5,1): error TS2304: Cannot find name "UnknownType".',
        '',
        'Found 3 errors in 3 files.',
      }
      
      local result = parser.parse_output(output)
      
      assert.equal(3, result.total_errors)
      assert.equal(3, result.total_files)
      assert.equal(3, #result.errors)
      assert.equal(3, #result.files)
      
      -- Check first error
      assert.equal('src/index.ts', result.errors[1].filename)
      assert.equal(10, result.errors[1].lnum)
      
      -- Check files list
      assert.is_true(vim.tbl_contains(result.files, 'src/index.ts'))
      assert.is_true(vim.tbl_contains(result.files, 'src/utils.ts'))
      assert.is_true(vim.tbl_contains(result.files, 'src/types.ts'))
    end)
    
    it('should handle empty output', function()
      local result = parser.parse_output({})
      
      assert.equal(0, result.total_errors)
      assert.equal(0, result.total_files)
      assert.equal(0, #result.errors)
      assert.equal(0, #result.files)
    end)
    
    it('should handle nil output', function()
      local result = parser.parse_output(nil)
      
      assert.equal(0, result.total_errors)
      assert.equal(0, #result.errors)
    end)
  end)
  
  describe('parse_error_code', function()
    it('should extract TypeScript error code', function()
      local message = 'error TS2322: Type "string" is not assignable to type "number".'
      local info = parser.parse_error_code(message)
      
      assert.equal('TS2322', info.code)
      assert.equal(2322, info.numeric_code)
      assert.equal('type_assignment', info.category)
    end)
    
    it('should categorize common errors', function()
      local test_cases = {
        { code = 2339, category = 'property_missing' },
        { code = 2304, category = 'name_not_found' },
        { code = 2307, category = 'module_resolution' },
        { code = 1005, category = 'syntax' },
        { code = 5023, category = 'config' },
      }
      
      for _, test in ipairs(test_cases) do
        local message = string.format('error TS%d: Some error message', test.code)
        local info = parser.parse_error_code(message)
        assert.equal(test.category, info.category)
      end
    end)
  end)
  
  describe('parse_watch_output', function()
    it('should detect watch mode indicators', function()
      local output = {
        'Starting compilation in watch mode...',
        '',
        'src/index.ts(10,5): error TS2322: Type "string" is not assignable to type "number".',
        '',
        'Watching for file changes.',
      }
      
      local result = parser.parse_watch_output(output)
      
      assert.is_true(result.watch_info.is_watch)
      assert.is_true(result.watch_info.is_initial)
      assert.is_false(result.watch_info.is_incremental)
    end)
    
    it('should detect incremental compilation', function()
      local output = {
        'File change detected. Starting incremental compilation...',
        '',
        'src/index.ts(10,5): error TS2322: Type "string" is not assignable to type "number".',
        '',
        'Watching for file changes.',
      }
      
      local result = parser.parse_watch_output(output)
      
      assert.is_true(result.watch_info.is_incremental)
    end)
  end)
  
  
  describe('group_errors_by_file', function()
    it('should group errors by filename', function()
      local errors = {
        { filename = 'src/index.ts', lnum = 10, text = 'Error 1' },
        { filename = 'src/utils.ts', lnum = 20, text = 'Error 2' },
        { filename = 'src/index.ts', lnum = 15, text = 'Error 3' },
      }
      
      local grouped = parser.group_errors_by_file(errors)
      
      assert.equal(2, vim.tbl_count(grouped))
      assert.equal(2, #grouped['src/index.ts'])
      assert.equal(1, #grouped['src/utils.ts'])
    end)
  end)
  
  describe('filter_errors', function()
    it('should filter by filename pattern', function()
      local errors = {
        { filename = 'src/index.ts', text = 'Error 1' },
        { filename = 'src/utils.ts', text = 'Error 2' },
        { filename = 'test/index.test.ts', text = 'Error 3' },
      }
      
      local filtered = parser.filter_errors(errors, {
        filename_pattern = '^src/',
      })
      
      assert.equal(2, #filtered)
    end)
    
    it('should filter by error code', function()
      local errors = {
        { text = 'error TS2322: Type error' },
        { text = 'error TS2339: Property error' },
        { text = 'error TS2322: Another type error' },
      }
      
      local filtered = parser.filter_errors(errors, {
        error_code = 'TS2322',
      })
      
      assert.equal(2, #filtered)
    end)
  end)
  
  describe('get_error_stats', function()
    it('should calculate error statistics', function()
      local errors = {
        { filename = 'src/index.ts', type = 'E', text = 'error TS2322: Type error' },
        { filename = 'src/utils.ts', type = 'E', text = 'error TS2339: Property error' },
        { filename = 'src/index.ts', type = 'W', text = 'warning TS6133: Unused variable' },
      }
      
      local stats = parser.get_error_stats(errors)
      
      assert.equal(3, stats.total_errors)
      assert.equal(2, stats.files_with_errors)
      assert.equal(2, stats.severity_counts.error)
      assert.equal(1, stats.severity_counts.warning)
      assert.equal(2, stats.error_categories.property_missing)
      assert.equal(1, stats.error_categories.type_assignment)
    end)
  end)
end)