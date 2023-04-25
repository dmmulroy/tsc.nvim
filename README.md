# tsc.nvim

![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/ellisonleao/nvim-plugin-template/default.yml?branch=main&style=for-the-badge)
![Lua](https://img.shields.io/badge/Made%20with%20Lua-blueviolet.svg?style=for-the-badge&logo=lua)

<img width="569" alt="image" src="https://user-images.githubusercontent.com/2755722/233876554-efb9cfe6-c038-46c8-a7cb-b7a4aa9eac5b.png">

This Neovim plugin provides an asynchronous interface to run project-wide TypeScript type-checking using the TypeScript compiler (`tsc`). It displays the type-checking results in a quickfix list and provides visual notifications about the progress and completion of type-checking.

## Features

- Project-wide type checking
- Asynchronous execution of the TypeScript compiler to prevent lock ups and input lag
- Progress notifications with spinner animation
- Quickfix list for navigating errors
- Automatic opening of the quickfix list if there are errors
- User-friendly command `:TSC`


## Demo Videos
### Type-checking with Errors
https://user-images.githubusercontent.com/2755722/233818168-de95bc9a-c406-4c71-9ef9-021f80db1da9.mov

### Type-checking without Errors
https://user-images.githubusercontent.com/2755722/233818163-bd2c2dda-88fc-41ea-a4bc-40972ad3ce9e.mov

### Usage without [nvim-notify](https://github.com/rcarriga/nvim-notify)
https://user-images.githubusercontent.com/2755722/233843746-ee116863-bef5-4e26-ba0a-afb906a2f111.mov


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

### Notify

For an enhanced UI/UX experience, it is recommended to install the [nvim_notify](https://github.com/rcarriga/nvim-notify) plugin as well. This plugin is optional, and the plugin will work without it.

## Setup

To set up the plugin, add the following line to your `init.vim` or `init.lua` file:

```lua
require('tsc').setup()
```

## Usage

To run TypeScript type-checking, execute the `:TSC` command in Neovim. The plugin will display a progress notification while the type-checking is in progress. When the type-checking is complete, it will show a notification with the results and open a quickfix list if there are any errors.

## Configuration

By default it uses the default `tsc` command with the `--noEmit` flag to avoid generating output files during type-checking. Here's the default configuration:

```lua
{
  flags = "--noEmit",
  spinner = { "⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷" },
}
```

## Contributing

Feel free to open issues or submit pull requests if you encounter any bugs or have suggestions for improvements. Your contributions are welcome!

## License

This plugin is released under the MIT License. See the [LICENSE](LICENSE) file for details.
