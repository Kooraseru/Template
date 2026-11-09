# Function documentation fixture matrix

- [Malformed tags](invalid/malformed-tags.luau) has a two-dash annotation and an empty return tag.
- [Documented function](valid/documented-function.luau) passes.
- [Method parameters](valid/method-parameters.luau) accepts an optional parameter tag and the implicit receiver.
- [Moonwave and string](valid/moonwave-and-string.luau) accepts a correctly attached block and ignores tag-like string text.
- [Parameter binding](invalid/parameter-binding.luau) reports a tag left behind after a parameter rename.
- [Detached documentation](invalid/detached-doc.luau) does not document the small module-level helper below it.
- [Function metadata](invalid/function-metadata.luau) reports property metadata and a redundant declaration tag on a named function.
- [Property metadata](valid/property-metadata.luau) accepts a readonly annotation on a binding and lifecycle metadata on a function.

- [Moonwave spacing](invalid/moonwave-spacing.luau) reports a tag that immediately follows prose.
- [Undocumented classifier](invalid/undocumented-classifier.luau) requires a description above a function with three branches.
- [Block documented classifier](valid/block-documented-classifier.luau) accepts the plain long-comment form.
- [Block parameter binding](invalid/block-parameter-binding.luau) reports a stale parameter name inside that form.
- [Exported getter](invalid/exported-getter.luau) requires documentation for a public function with a one-line body.
- [Assigned export](invalid/exported-assignment.luau) requires documentation for a function expression assigned to the returned module.
- [Documented assigned export](valid/exported-assignment.luau) accepts an attached description.
- [Opening line prose](valid/block-opening-prose.luau) accepts a description on the opening line of a multiline block.
