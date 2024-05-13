# tsc.nvim

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

For [yarn2](https://yarnpkg.com/) projects, you will need to generate the base SDK for handling typescript correctly:

```bash
yarn dlx @yarnpkg/sdks base
```

See [Editor SDKs](https://yarnpkg.com/getting-started/editor-sdks) for more information about configuring your IDE.

## Usage

To run TypeScript type-checking, execute the `:TSC` command in Neovim. The plugin will display a progress notification while the type-checking is in progress. When the type-checking is complete, it will show a notification with the results and open a quickfix list if there are any errors.

If `watch` mode is enabled, tsc.nvim will automatically run in the background every time you save in a typescript or tsx file and report the results back to you. In addition, if `auto_start_watch_mode` is enabled, the `:TSC` command will be executed on your behalf when you enter a typescript or tsx files.

To stop any running `:TSC` command, use the `:TSCStop` command in Neovim.

## Configuration

By default, the plugin uses the default `tsc` command with the `--noEmit` flag to avoid generating output files during type-checking. It also emulates the default tsc behavior of performing a backward search from the current directory for a `tsconfig` file. The flags option can accept both a string and a table. Here's the default configuration:

```lua
{
  auto_open_qflist = true,
  auto_close_qflist = false,
  auto_focus_qflist = false,
  auto_start_watch_mode = false,
  use_trouble_qflist = false,
  run_as_monorepo = false,
  bin_path = utils.find_tsc_bin(),
  enable_progress_notifications = true,
  flags = {
    noEmit = true,
    project = function()
      return utils.find_nearest_tsconfig()
    end,
    watch = false,
  },
  hide_progress_notifications_from_history = true,
  spinner = { "⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷" },
  pretty_errors = true,
}
```

With this configuration, you can use keys for flag names and their corresponding values to enable/disable the flag (in the case of `noEmit = true`), provide a function (as in the case of the `project`) or enable watch mode. This makes the configuration more explicit and easier to read. Additionally, the flags option is backwards compatible and can accept a string value if you prefer a simpler configuration:

```lua
flags = "--noEmit",
```

## Manual Opening and Closing the Quickfix List

There are two user commands you can use to open and close the quickfix list:

`TSCOpen` - open the quickfix list
`TSCClose` - close the quickfix list

These commands will respect your configuration options:

- `auto_open_qflist`
- `auto_close_qflist`
- `use_trouble_qflist`

### Example key maps:

```lua
vim.keymap.set('n', '<leader>to', ':TSCOpen<CR>')
vim.keymap.set('n', '<leader>tc', ':TSCClose<CR>')
```

## FAQs

### I'm using `nvim-notify` and being spammed by progress notifications, what's going on?

It's likely that the overwritten default `vim.notify` function isn't returning `nvim-notify`'s notification record, which is used to replace the existing notification. Make sure that you're nvim-notify configuration looks something like this:

```lua
local notify = require('notify')

vim.notify = function(message, level, opts)
  return notify(message, level, opts) -- <-- Important to return the value from `nvim-notify`
end

```

### Why doesn't tsc.nvim typecheck my entire monorepo?

By default, tsc.nvim will check only the nearest `tsconfig` file. If you would like it to use all `tsconfig` files in the current working directory, set `run_as_monorepo = true`. All other options will work as usual such as `auto_start_watch_mode`, `flags.watch`, etc.

```lua
require('tsc').setup({
    run_as_monorepo = true,
})
```

With this configuration, tsc.nvim will typecheck all projects in the monorepo, taking into account project references and incremental builds.

### Can I use `Trouble` for the quickfix list?

Yes, as long as you have the plugin installed you can set `use_trouble_qflist = true` in the configuration.

```lua
require('tsc').setup({
    use_trouble_qflist = true,
})
```

This will use Trouble for the quickfix list. This will work with all other options such as `auto_open_qflist`, `auto_close_qflist`, `auto_focus_qflist`.

## Contributing

Feel free to open issues or submit pull requests if you encounter any bugs or have suggestions for improvements. Your contributions are welcome!

## License

This plugin is released under the MIT License. See the [LICENSE](LICENSE) file for details.
