-- Unit tests for project discovery
local ProjectDiscovery = require('tsc.core.discovery')
local fs = require('tsc.utils.fs')

describe('ProjectDiscovery', function()
  local discovery
  local test_config
  
  before_each(function()
    test_config = {
      root_markers = { 'package.json', 'tsconfig.json' },
      tsconfig_name = 'tsconfig.json',
      max_projects = 20,
      exclude_patterns = { 'node_modules', '.git' },
    }
    discovery = ProjectDiscovery.new(test_config)
  end)
  
  describe('new', function()
    it('should create new discovery instance', function()
      assert.is_table(discovery)
      assert.is_function(discovery.find_projects)
      assert.is_function(discovery.get_project_root)
      assert.is_function(discovery.clear_cache)
    end)
  end)
  
  describe('find_projects', function()
    it('should find single project', function()
      -- Mock fs.find_file_upward
      local original_find = fs.find_file_upward
      fs.find_file_upward = function(filename)
        if filename == 'tsconfig.json' then
          return '/test/project/tsconfig.json'
        end
        return nil
      end
      
      -- Mock fs.file_exists and fs.dir_exists
      local original_file_exists = fs.file_exists
      local original_dir_exists = fs.dir_exists
      fs.file_exists = function(path)
        return path == '/test/project/tsconfig.json'
      end
      fs.dir_exists = function(path)
        return path == '/test/project'
      end
      
      -- Mock fs.read_file
      local original_read = fs.read_file
      fs.read_file = function(path)
        if path == '/test/project/tsconfig.json' then
          return '{"compilerOptions": {}}'
        end
        return nil
      end
      
      local projects = discovery:find_projects('project')
      
      assert.equal(1, #projects)
      assert.equal('/test/project/tsconfig.json', projects[1].path)
      assert.equal('/test/project', projects[1].root)
      assert.equal('project', projects[1].type)
      
      -- Restore mocks
      fs.find_file_upward = original_find
      fs.file_exists = original_file_exists
      fs.dir_exists = original_dir_exists
      fs.read_file = original_read
    end)
    
    it('should return empty array when no project found', function()
      -- Mock fs.find_file_upward to return nil
      local original_find = fs.find_file_upward
      fs.find_file_upward = function()
        return nil
      end
      
      local projects = discovery:find_projects('project')
      
      assert.equal(0, #projects)
      
      -- Restore mock
      fs.find_file_upward = original_find
    end)
    
    it('should respect max_projects limit', function()
      -- Mock fs.find_files_recursive to return many projects
      local original_find_recursive = fs.find_files_recursive
      fs.find_files_recursive = function()
        local results = {}
        for i = 1, 30 do
          table.insert(results, string.format('./project%d/tsconfig.json', i))
        end
        return results
      end
      
      -- Mock validation functions
      local original_file_exists = fs.file_exists
      local original_dir_exists = fs.dir_exists
      local original_read = fs.read_file
      local original_absolute = fs.absolute_path
      
      fs.file_exists = function() return true end
      fs.dir_exists = function() return true end
      fs.read_file = function() return '{"compilerOptions": {}}' end
      fs.absolute_path = function(path) return '/test' .. path:sub(2) end
      
      local projects = discovery:find_projects('monorepo')
      
      assert.equal(test_config.max_projects, #projects)
      
      -- Restore mocks
      fs.find_files_recursive = original_find_recursive
      fs.file_exists = original_file_exists
      fs.dir_exists = original_dir_exists
      fs.read_file = original_read
      fs.absolute_path = original_absolute
    end)
  end)
  
  describe('caching', function()
    it('should cache discovery results', function()
      local call_count = 0
      
      -- Mock fs.find_file_upward to count calls
      local original_find = fs.find_file_upward
      fs.find_file_upward = function(filename)
        call_count = call_count + 1
        if filename == 'tsconfig.json' then
          return '/test/project/tsconfig.json'
        end
        return nil
      end
      
      -- Mock other required functions
      local original_file_exists = fs.file_exists
      local original_dir_exists = fs.dir_exists
      local original_read = fs.read_file
      
      fs.file_exists = function() return true end
      fs.dir_exists = function() return true end
      fs.read_file = function() return '{"compilerOptions": {}}' end
      
      -- First call
      local projects1 = discovery:find_projects('project')
      assert.equal(1, call_count)
      
      -- Second call should use cache
      local projects2 = discovery:find_projects('project')
      assert.equal(1, call_count)
      
      assert.are.same(projects1, projects2)
      
      -- Restore mocks
      fs.find_file_upward = original_find
      fs.file_exists = original_file_exists
      fs.dir_exists = original_dir_exists
      fs.read_file = original_read
    end)
    
    it('should clear cache', function()
      -- Set up some cached data
      discovery._cache['test:key'] = { { path = '/test/tsconfig.json' } }
      
      local cache = discovery:get_cache()
      assert.equal(1, vim.tbl_count(cache))
      
      discovery:clear_cache()
      
      cache = discovery:get_cache()
      assert.equal(0, vim.tbl_count(cache))
    end)
  end)
  
  describe('project validation', function()
    it('should validate project files exist', function()
      -- Mock file system functions
      local original_file_exists = fs.file_exists
      local original_dir_exists = fs.dir_exists
      local original_read = fs.read_file
      
      local file_exists_map = {
        ['/valid/tsconfig.json'] = true,
        ['/invalid/tsconfig.json'] = false,
      }
      
      fs.file_exists = function(path)
        return file_exists_map[path] or false
      end
      
      fs.dir_exists = function(path)
        return path == '/valid' or path == '/invalid'
      end
      
      fs.read_file = function(path)
        if path == '/valid/tsconfig.json' then
          return '{"compilerOptions": {}}'
        end
        return nil
      end
      
      local projects = {
        { path = '/valid/tsconfig.json', root = '/valid', type = 'project' },
        { path = '/invalid/tsconfig.json', root = '/invalid', type = 'project' },
      }
      
      local validated = discovery:_validate_projects(projects)
      
      assert.equal(1, #validated)
      assert.equal('/valid/tsconfig.json', validated[1].path)
      
      -- Restore mocks
      fs.file_exists = original_file_exists
      fs.dir_exists = original_dir_exists
      fs.read_file = original_read
    end)
  end)
  
  describe('find_root_by_markers', function()
    it('should find root by markers', function()
      -- Mock fs.find_file_upward
      local original_find = fs.find_file_upward
      fs.find_file_upward = function(marker)
        if marker == 'package.json' then
          return '/test/project/package.json'
        end
        return nil
      end
      
      -- Mock fs.dirname
      local original_dirname = fs.dirname
      fs.dirname = function(path)
        return '/test/project'
      end
      
      local root = discovery:find_root_by_markers({'package.json', 'tsconfig.json'})
      
      assert.equal('/test/project', root)
      
      -- Restore mocks
      fs.find_file_upward = original_find
      fs.dirname = original_dirname
    end)
  end)
  
  describe('get_stats', function()
    it('should return discovery statistics', function()
      -- Add some cached data
      discovery._cache['project:/test1'] = { { path = '/test1/tsconfig.json' } }
      discovery._cache['monorepo:/test2'] = { 
        { path = '/test2/pkg1/tsconfig.json' },
        { path = '/test2/pkg2/tsconfig.json' },
      }
      
      local stats = discovery:get_stats()
      
      assert.equal(3, stats.total_cached_projects)
      assert.equal(2, stats.cache_entries)
      assert.equal(2, #stats.cache_keys)
    end)
  end)
end)