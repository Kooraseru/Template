# JavaScript browser boundaries

Browser input includes fetched data, URL state, cookies, form fields, DOM
attributes, and third-party globals. Validate or normalize at the boundary;
do not spread uncertain shapes through the application. Define failure and
loading behavior where asynchronous work begins.

Keep a canonical data source and derive view state from it. For a localized
view, cache the source catalog when appropriate and recompute presentation for
the selected locale. Preserve one configured fallback rather than embedding
language-specific branches throughout UI code. Update text and translated
attributes in place when the product uses one route.

DOM controllers own the elements and listeners they create. Re-rendering must
not orphan nodes, duplicate listeners, lose focus without reason, or reset user
input unnecessarily. Use event delegation for repeated dynamic controls when
it reduces lifecycle complexity. Stop propagation only when a nested action
really needs its own behavior.

Use `textContent` for plain text. When HTML is intentionally rendered, define
the trusted source and escaping or sanitization boundary. Encode URL path
segments; do not interpolate untrusted strings into selectors or attributes
without suitable handling. Network errors should leave a usable page state.

When behavior depends on layout, measure the actual container and reachable
range rather than assuming a fixed card count or viewport width. Recalculate
when size or content changes. Respect reduced-motion preference for animated
behavior.

