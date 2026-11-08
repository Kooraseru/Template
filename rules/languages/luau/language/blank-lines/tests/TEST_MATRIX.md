# Blank-line separation fixtures

- [Bunched blocks](invalid/bunched-blocks.luau) warns on adjacent multi-line module-level functions.
- [Separated blocks](valid/separated-blocks.luau) passes when functions and the return statement have blank-line separation.
- [Nested blocks](review/nested-blocks.luau) records the unresolved policy for adjacent blocks inside a function; this first validator only checks module scope.
