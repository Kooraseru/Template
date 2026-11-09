# Blank-line separation fixtures

- [Bunched blocks](invalid/bunched-blocks.luau) warns on adjacent multi-line module-level functions.
- [Separated blocks](valid/separated-blocks.luau) passes when functions and the return statement have blank-line separation.
- [Compact guards](review/nested-blocks.luau) leaves consecutive early exits grouped.
- [Crowded nested phases](invalid/nested-phases.luau) warns between a guard and a loop, then between the loop and a local declaration.
- [Separated nested phases](valid/nested-phases.luau) accepts a blank line or a standalone comment at those same boundaries.
- [Single nested boundary](valid/single-boundary.luau) leaves an isolated transition alone.
- [Adjacent compact functions](invalid/adjacent-compact-functions.luau) warns at the second module-level function even when both fit on one line.
- [Compact return chain](invalid/compact-return-chain.luau) reports all crowded boundaries, including the fallback.
- [Separated return chain](valid/separated-return-chain.luau) accepts the same branches with blank lines.
