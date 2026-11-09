# Script layout

Use the [structure guides](../README.md) to pick a starter. Rules infer the layout from the returned callable or module table. Objects take precedence when a constructor returns an instance using the exported table as its metatable. Ambiguous return shapes stay unclassified.

The optional settings `entryPoints`, `ecsComponents`, and `ecsSystems` accept exact workspace-relative Luau paths. Declared paths take precedence over inference. Add ECS paths when an ECS integration exists.

When a file uses top-level section markers, keep the sections in the order shown in its starter. Omit sections you do not use. Small files can omit markers. The check reports duplicate or misplaced sections and declarations with clear roles. Describe behavior and invariants in prose above functions and inside substantial phases.

[Copyable starters](examples/) show the complete section order in their opening comments. Replace each example body with the behavior your file owns.

Use Modules for imports, Types for type declarations, Constants for fixed values, Variables for shared mutable state, and Helpers for private functions. Functions exposes the module’s callable surface, Constructor creates instances, Methods acts on instances, and Initialization wires up startup behavior.
