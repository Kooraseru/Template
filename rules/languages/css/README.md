# CSS system

CSS owns presentation. Organize it by responsibility: foundation, reusable
components, composed patterns, and page-specific layout. A theme supplies
semantic values rather than a second copy of every component rule.

When editing CSS, choose in this order:

1. whether the rule is a token, component, pattern, or page layout rule
2. the owner of the element and its states
3. the intended cascade layer and selector scope
4. responsive and interaction behavior
5. whether the rule should be public to consuming projects

[`modules.md`](modules.md) owns module boundaries and cascade.
[`tokens-and-themes.md`](tokens-and-themes.md) owns reusable values and theme
contracts. A repository design system decides its exact class and token names.
