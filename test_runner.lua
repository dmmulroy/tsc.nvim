#!/usr/bin/env luajit

-- Simple test runner for tsc.nvim 3.0
-- This is a basic test runner until we set up proper testing infrastructure

local function run_tests()
  print("tsc.nvim 3.0 - Basic Smoke Tests")
  print("==================================")

  -- Test 1: Event system can be loaded
  print("\n1. Testing event system loading...")
  local success, Events = pcall(require, "tsc.core.events")
  if success then
    print("   ✓ Event system loaded successfully")

    -- Test event creation
    local events = Events.new()
    if events then
      print("   ✓ Event system instance created")
    else
      print("   ✗ Failed to create event system instance")
    end
  else
    print("   ✗ Failed to load event system:", Events)
  end

  -- Test 2: Configuration system can be loaded
  print("\n2. Testing configuration system loading...")
  local success, Config = pcall(require, "tsc.config")
  if success then
    print("   ✓ Configuration system loaded successfully")

    -- Test config creation
    local config = Config.new()
    if config then
      print("   ✓ Configuration instance created")
      local summary = config:get_summary()
      if summary then
        print("   ✓ Configuration summary retrieved")
      else
        print("   ✗ Failed to get configuration summary")
      end
    else
      print("   ✗ Failed to create configuration instance")
    end
  else
    print("   ✗ Failed to load configuration system:", Config)
  end

  -- Test 3: Plugin system can be loaded
  print("\n3. Testing plugin system loading...")
  success, Plugins = pcall(require, "tsc.plugins")
  if success then
    print("   ✓ Plugin system loaded successfully")
  else
    print("   ✗ Failed to load plugin system:", Plugins)
  end

  -- Test 4: Core discovery system can be loaded
  print("\n4. Testing discovery system loading...")
  local success, Discovery = pcall(require, "tsc.core.discovery")
  if success then
    print("   ✓ Discovery system loaded successfully")
  else
    print("   ✗ Failed to load discovery system:", Discovery)
  end

  -- Test 5: Runner system can be loaded
  print("\n5. Testing runner system loading...")
  local success, Runner = pcall(require, "tsc.core.runner")
  if success then
    print("   ✓ Runner system loaded successfully")
  else
    print("   ✗ Failed to load runner system:", Runner)
  end

  -- Test 6: Main module can be loaded
  print("\n6. Testing main module loading...")
  local success, TSC = pcall(require, "tsc")
  if success then
    print("   ✓ Main module loaded successfully")
  else
    print("   ✗ Failed to load main module:", TSC)
  end

  print("\n==================================")
  print("Basic smoke tests completed!")
end

-- Run the tests
run_tests()

