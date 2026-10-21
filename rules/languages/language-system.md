# Language system

Language guidance is organized by language and concept. A source file first
chooses its responsibility and runtime boundary, then its file role and shape,
then the language-specific rules that apply to that shape. Do not make every
file follow a decorative skeleton.

The universal [`comments.md`](comments.md) owns why and where to comment.
Language documents own syntax, semantics, browser or runtime boundaries, and
examples. Repository documents own actual paths, build commands, catalogs,
design tokens, supported themes, and publication behavior.

## Shared ownership rules

- A fact has one authoritative editable owner. Other files consume or derive
  it. Do not repeat a locale list, theme list, image list, or default value in
  multiple hand-edited places.
- Separate source data, validation, rendering, and runtime state. Generated
  output is recognizable and changed through its source or generator.
- Keep validation at the boundary where uncertain data enters. Internal code
  can rely on a validated contract without rechecking it everywhere.
- Let each module or component own the smallest coherent responsibility.
  A directory is useful when children share a real contract, not merely to
  make a tree look complete.
- Name the role of a value or module. Equal-looking values are not automatically
  the same policy; duplicate policy is a reason to share an owner.

When a language-specific rule conflicts with a universal rule for a real syntax
or runtime reason, the language concept owns that exception and explains it.
Application-specific exceptions belong in the application's knowledge tree.


The cross-language control-flow preference is guard-first reasoning: resolve failure or absence before writing the successful path. See [Luau guards](luau/language/control-flow.md) and [Rust guards](rust/language/control-flow.md). This is a readability default, not a ban on positive conditions.
