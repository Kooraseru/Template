# Project source

Organize implementation by subsystem. A subsystem may use Luau, C/C++, Rust,
or another configured toolchain. Keep subsystem tests near their implementation;
put tests spanning subsystems under `tests/`.

Configure actual build and test commands in `ci/config.toml`. The template has
no application build commands until a consuming project supplies them.
