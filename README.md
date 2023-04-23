# tsc.nvim

![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/ellisonleao/nvim-plugin-template/default.yml?branch=main&style=for-the-badge)
![Lua](https://img.shields.io/badge/Made%20with%20Lua-blueviolet.svg?style=for-the-badge&logo=lua)

This Neovim plugin provides an asynchronous interface to run TypeScript type-checking using the TypeScript compiler (`tsc`). It displays the type-checking results in a quickfix list and provides visual notifications about the progress and completion of type-checking.

## Features

- Asynchronous execution of the TypeScript compiler
- Progress notifications with spinner animation
- Quickfix list for navigating errors
- Automatic opening of the quickfix list if there are errors
- User-friendly command `:TSC`

## Installation

To install the plugin, use your preferred Neovim plugin manager.

### Packer

To install the plugin using packer.nvim, add the following to your plugin configuration:

```lua
use('dmmulroy/tsc.nvim')

```

### Vim-Plug

To install the plugin using vim-plug, add the following to your plugin configuration:

```vim
Plug 'dmmulroy/tsc.nvim'
```

Then run `:PlugInstall` to install the plugin.

## Setup

To set up the plugin, add the following line to your `init.vim` or `init.lua` file:

```lua
require('tsc').setup()
```

## Usage

To run TypeScript type-checking, execute the `:TSC` command in Neovim. The plugin will display a progress notification while the type-checking is in progress. When the type-checking is complete, it will show a notification with the results and open a quickfix list if there are any errors.

## Configuration

Currently, there are no configuration options for this plugin. It uses the default `tsc` command with the `--noEmit` flag to avoid generating output files during type-checking. If you need to customize the behavior, consider forking the plugin and modifying it to suit your needs.

## Contributing

Feel free to open issues or submit pull requests if you encounter any bugs or have suggestions for improvements. Your contributions are welcome!

## License

This plugin is released under the MIT License. See the [LICENSE](LICENSE) file for details.
