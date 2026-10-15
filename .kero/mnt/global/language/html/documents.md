# HTML documents

Start a document with a doctype, language, character encoding, viewport, a
meaningful title, and the metadata the page actually needs. The visible heading
structure should describe the page, not simulate a visual size scale.

Use landmarks for real regions. Put navigation in `nav`, primary content in
`main`, and stand-alone grouped content in `section` or `article` when those
meanings apply. Keep source order usable without CSS. Do not add wrappers merely
to satisfy a selector; add one when it represents a layout or interaction
boundary with an owner.

Use `button` for actions and `a` for destinations. Native form controls should
have associated visible labels, correct types, constraints, and error text
that can be understood without color alone. A clickable `div` must justify the
extra keyboard and accessibility work it creates. Decorative images have empty
alt text; informative images describe their purpose in context.

Every interactive control needs a stable accessible name and visible keyboard
focus. Dynamic regions must expose state through the appropriate native
attribute or ARIA state; do not add ARIA that contradicts native semantics.
Page-specific modal, disclosure, and carousel behavior belongs to their
component contract, including keyboard operation and focus behavior.

