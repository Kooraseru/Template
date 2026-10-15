# HTML system

HTML owns document meaning, content order, and native interaction semantics.
Choose an element for its meaning and behavior before styling it. CSS owns
appearance; JavaScript owns enhancement and state transitions; neither repairs
an incorrect document structure by itself.

When editing HTML, choose in this order:

1. document or fragment responsibility
2. semantic structure and reading order
3. form, navigation, and accessibility contract
4. templating and localization boundaries
5. styling hooks and enhancement hooks

[`documents.md`](documents.md) owns whole-page shape and semantic controls.
[`templates.md`](templates.md) owns generated markup and localization
boundaries. Repository knowledge owns its actual routes and catalogs.

