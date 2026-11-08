# Directory head fixtures

- [Forwards child](invalid/forwards-child/init.luau) reports the full return statement; `Child.luau` is present beside the head.
- [Empty head](invalid/empty-head/init.luau) reports the full return statement; `Reserved.luau` demonstrates the directory's child module.
- [Forwards binding](invalid/forwards-binding/init.luau) reports the import and return together; `Renderer.luau` is present beside the head.
- [Mirrors children](invalid/mirrors-children/init.luau) reports a record consisting entirely of direct child imports; both modules exist in the directory.
- [Mixed facade](valid/mixed-facade/init.luau) has behavior alongside a child import and produces no warning; its `Renderer.luau` child is present.
- [Owns surface](valid/owns-surface/init.luau) passes because the head defines an API; `Child.luau` is present beside it.

Each case is a directory tree. The fixture runner preserves its paths under a virtual `source/` root, so the validator receives the actual `init.luau` path and sibling modules in the same input set.
