# rust-tdd
Neovim Plugin for TDD with Rust

![image](https://github.com/daic0r/rust-tdd/assets/13116881/04e9b7d1-1916-49a7-9b99-19b5dd4d0b4c)

Runs `cargo test` when a buffer containing a Rust source file that contains tests is written (see screenshot).

# Installation

## lazy.nvim

```lua
{
    'daic0r/rust-tdd',
    config = function()
        require('rust-tdd').setup()
    end
}
```
