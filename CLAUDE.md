# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Code Formatting
- **Format Lua code**: `stylua lua/` (follows configuration in `.stylua.toml`)
- **CI formatting check**: `stylua --color always --check lua` (used in GitHub Actions)

### Testing
- Tests are located in `lua/tsc/better-messages-test.lua` and `lua/tsc/utils-test.lua`
- Uses a simple test framework with `describe` and `it` blocks
- Tests focus on the better-messages translation functionality and core utils functions

## Recent Bug Fixes

### Error Detection Issues (Fixed)
The plugin previously failed to detect TypeScript errors that were visible when running `pnpm run typecheck` or `tsc` directly. Three root causes were identified and fixed:

1. **Auto-detection override**: The default config always called `find_nearest_tsconfig()` for the project flag, overriding user configuration. Now auto-detection only occurs when no explicit project is configured.

2. **ANSI color parsing**: TypeScript outputs colored text by default, but the regex parser expected plain text. Fixed by adding `--color false` flag to disable colored output.

3. **Working directory mismatch**: The plugin ran from the current buffer directory instead of project root. Fixed by setting `cwd` option in `jobstart()` to the project root directory.

### Enhanced Error Handling
- Added validation to ensure tsconfig.json exists and is readable
- Improved error messages when tsconfig is not found or invalid
- Better feedback for configuration issues

## Architecture Overview

This is a Neovim plugin that provides asynchronous TypeScript type-checking using `tsc`. The plugin consists of three main modules:

### Core Structure
- `lua/tsc/init.lua` - Main plugin entry point with setup and run functions
- `lua/tsc/utils.lua` - Utility functions for TSC binary discovery, output parsing, and quickfix list management
- `lua/tsc/better-messages.lua` - Enhanced error message translation system

### Key Components

#### Main Plugin (`init.lua`)
- Exposes `:TSC` command for manual type-checking
- Manages asynchronous job execution with progress notifications
- Handles configuration and watch mode functionality
- Integrates with nvim-notify for enhanced UI notifications

#### Utilities (`utils.lua`)
- `find_tsc_bin()` - Discovers local node_modules or global TSC binary
- `find_nearest_tsconfig()` - Locates nearest tsconfig.json file
- `parse_flags()` - Converts configuration flags to CLI arguments
- `parse_tsc_output()` - Parses TSC output into quickfix list format
- `set_qflist()` - Manages quickfix list display and behavior

#### Better Messages System (`better-messages.lua`)
- Translates cryptic TypeScript error codes (e.g., TS7006) into human-readable messages
- Uses markdown files in `better-messages/` directory (60+ error translations)
- Supports parameter substitution using `{0}`, `{1}` placeholders
- Strips markdown links and formatting for cleaner error display

### Configuration System
The plugin uses a flexible configuration system supporting:
- String-based flags (backward compatibility)
- Object-based flags with boolean, string, and function values
- Watch mode with auto-start capabilities
- Quickfix list behavior customization
- Progress notification preferences

### Watch Mode
When enabled, the plugin:
- Monitors TypeScript files for changes
- Automatically runs type-checking on save
- Parses incremental output differently than one-time runs
- Can auto-start when opening TypeScript files

## File Structure Notes
- Better message templates are stored as individual markdown files named by error code (e.g., `2604.md`)
- Each template has an "original" pattern and "better" replacement message
- The plugin searches upward from current directory for tsconfig.json (mimics TSC behavior)
- Binary discovery checks local node_modules first, then falls back to global TSC