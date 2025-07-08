-- Unit tests for configuration manager
local ConfigManager = require('tsc.config')
local defaults = require('tsc.config.defaults')

describe('ConfigManager', function()
  local config
  
  before_each(function()
    config = ConfigManager.new()
  end)
  
  describe('new', function()
    it('should create with default configuration', function()
      assert.is_table(config)
      assert.is_function(config.get)
      assert.is_function(config.get_section)
      assert.is_function(config.update)
    end)
    
    it('should accept user configuration', function()
      local custom_config = ConfigManager.new({
        mode = 'monorepo',
        typescript = {
          flags = '--strict',
        },
      })
      
      assert.equal('monorepo', custom_config:get_mode())
      assert.equal('--strict', custom_config:get_tsc_flags())
    end)
    
    it('should validate configuration', function()
      -- This should not error
      local valid_config = ConfigManager.new({
        mode = 'project',
        output = {
          format = 'quickfix',
        },
      })
      assert.is_table(valid_config)
      
      -- Invalid mode should fall back to defaults
      local invalid_config = ConfigManager.new({
        mode = 'invalid_mode',
      })
      assert.equal('project', invalid_config:get_mode())
    end)
  end)
  
  describe('get', function()
    it('should return full configuration', function()
      local full_config = config:get()
      assert.is_table(full_config)
      assert.is_string(full_config.mode)
      assert.is_table(full_config.discovery)
      assert.is_table(full_config.typescript)
      assert.is_table(full_config.output)
      assert.is_table(full_config.plugins)
    end)
    
    it('should return a copy of configuration', function()
      local config1 = config:get()
      local config2 = config:get()
      assert.are_not.equal(config1, config2)
      assert.are.same(config1, config2)
    end)
  end)
  
  describe('get_section', function()
    it('should return specific configuration section', function()
      local discovery = config:get_section('discovery')
      assert.is_table(discovery)
      assert.is_table(discovery.root_markers)
      assert.is_string(discovery.tsconfig_name)
      assert.is_number(discovery.max_projects)
    end)
    
    it('should return nil for invalid section', function()
      local invalid = config:get_section('invalid_section')
      assert.is_nil(invalid)
    end)
  end)
  
  describe('update', function()
    it('should update configuration', function()
      local success = config:update({
        mode = 'monorepo',
        typescript = {
          timeout = 60000,
        },
      })
      
      assert.is_true(success)
      assert.equal('monorepo', config:get_mode())
      assert.equal(60000, config:get_timeout())
    end)
    
    it('should validate updates', function()
      local success = config:update({
        mode = 'invalid_mode',
      })
      
      assert.is_false(success)
      assert.equal('project', config:get_mode())
    end)
  end)
  
  describe('plugin configuration', function()
    it('should get plugin config', function()
      local quickfix_config = config:get_plugin_config('quickfix')
      assert.is_table(quickfix_config)
      assert.is_true(quickfix_config.enabled)
    end)
    
    it('should check if plugin is enabled', function()
      assert.is_true(config:is_plugin_enabled('quickfix'))
      assert.is_false(config:is_plugin_enabled('watch'))
    end)
    
    it('should handle non-existent plugins', function()
      local invalid = config:get_plugin_config('non_existent')
      assert.is_nil(invalid)
      assert.is_false(config:is_plugin_enabled('non_existent'))
    end)
  end)
  
  describe('TypeScript configuration', function()
    it('should get TypeScript binary', function()
      local bin = config:get_tsc_binary()
      assert.is_string(bin)
      -- Should be either 'tsc' or a path to node_modules/.bin/tsc
      assert.is_true(bin == 'tsc' or bin:match('tsc$'))
    end)
    
    it('should get TypeScript flags', function()
      local flags = config:get_tsc_flags()
      assert.is_string(flags)
      assert.equal('--noEmit', flags)
    end)
    
    it('should get timeout', function()
      local timeout = config:get_timeout()
      assert.is_number(timeout)
      assert.equal(30000, timeout)
    end)
  end)
  
  describe('get_summary', function()
    it('should return configuration summary', function()
      local summary = config:get_summary()
      assert.is_table(summary)
      assert.is_string(summary.mode)
      assert.is_string(summary.typescript_bin)
      assert.is_string(summary.typescript_flags)
      assert.is_number(summary.timeout)
      assert.is_string(summary.output_format)
      assert.is_table(summary.enabled_plugins)
    end)
  end)
  
  describe('2.x migration', function()
    it('should migrate 2.x configuration', function()
      local v2_config = ConfigManager.new({
        auto_open_qflist = true,
        auto_close_qflist = false,
        run_as_monorepo = true,
        use_diagnostics = true,
        flags = {
          noEmit = true,
          strict = true,
        },
      })
      
      assert.equal('monorepo', v2_config:get_mode())
      assert.is_true(v2_config:get_output_config().auto_open)
      assert.is_false(v2_config:get_output_config().auto_close)
      assert.is_true(v2_config:is_plugin_enabled('diagnostics'))
      assert.equal('--noEmit --strict', v2_config:get_tsc_flags())
    end)
  end)
end)