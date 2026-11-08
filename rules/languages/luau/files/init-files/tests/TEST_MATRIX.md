# Directory head fixtures

- [Forwards child](invalid/forwards-child/init.luau) reports the full return statement; `Child.luau` is present beside the head.
- [Empty head](invalid/empty-head/init.luau) reports the full return statement; `Reserved.luau` demonstrates the directory's child module.
- [Forwards binding](invalid/forwards-binding/init.luau) reports the import and return together; `Renderer.luau` is present beside the head.
- [Mirrors children](invalid/mirrors-children/init.luau) reports a record consisting entirely of direct child imports; both modules exist in the directory.
- [Mixed facade](review/mixed-facade/init.luau) has behavior alongside a child import and produces no warning; its `Renderer.luau` child is present.
- [Owns surface](valid/owns-surface/init.luau) passes because the head defines an API; `Child.luau` is present beside it.
- [Runtime resolver](review/runtime-resolver/init.luau) produces no warning. The meaning of the path depends on its runtime; `Child.luau` is present to make the directory concrete.
- [Parent facade](review/parent-facade/init.luau) produces no warning. A parent import may be a deliberate compatibility surface; `Shared.luau` is included in the fixture directory.

Each case is a directory tree. The fixture runner preserves its paths under a virtual `source/` root, so the validator receives the actual `init.luau` path and sibling modules in the same input set.
