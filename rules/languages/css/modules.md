# CSS modules and cascade

Keep rules for one module together. A reusable component owns its default and
state styles. A page module may compose components and control placement, but
should not override a component's internal colors or focus treatment through
selector specificity. Add a documented variant or token slot when that choice
is genuinely part of the component API.

Declare cascade order deliberately, for example:

```css
@layer reset, foundation, themes, components, patterns, pages, utilities;
```

The actual layer names belong to the owning design system. Keep authored rules
inside the declared layers; unlayered rules have different precedence and can
silently defeat the intended order. Avoid `!important` as a normal override
mechanism. Prefer one class for a module root, clear state attributes, and
selectors that do not depend on accidental nesting.

Put responsive rules next to the component or page module they change. Test
states across narrow and wide layouts, keyboard focus, reduced motion, and
supported themes. If a component only works inside one page's DOM tree, it is
not yet reusable.

Keep layout geometry with the layout owner. Keep a component's internal spacing
with the component. This distinction prevents global element selectors from
changing every field or button on unrelated pages.

