# Comments and documentation

Comments explain the information a maintainer cannot reliably infer from the
nearby syntax. Write them for ownership, intent, constraints, assumptions,
failure modes, ordering, side effects, lifecycle, accessibility, security,
compatibility, and unusual performance costs. A comment should help someone
decide whether a change is safe.

## Placement

- Put a short file-level comment at the top only when the file's role is not
  evident from its name and location. State what it owns, not a slogan.
- Put a comment beside the rule or operation it explains. A distant overview
  does not replace a local explanation for a surprising condition.
- Document public contracts at their declaration: inputs, outputs, important
  constraints, side effects, and caller obligations. Use the language's native
  documentation form where one exists.
- Keep data-field documentation close to the field or schema. Describe groups
  and invariants; do not annotate every obvious leaf.
- For generated files, identify the generator and editable source. Do not put
  the only explanation in generated output.

## Content

Explain **why** a rule exists or **what must remain true**. Do not paraphrase a
function name, selector, element, or assignment. Avoid banners and repeated
section headers in tiny files. Use stable terms from the module's contract.
When a workaround is temporary, name the exit condition and its owner; a bare
`TODO` is not a migration plan.

Keep comments accurate when behavior changes. Delete comments that no longer
describe the code. Cite an external source beside the behavior it influenced
when that source is needed to understand the design; prefer specifications and
official documentation. Do not paste long external text into comments.

## Examples

Useful:

```js
// Keep the cached catalog across locale changes; only presentation values vary.
```

Hollow:

```js
// Load the catalog.
```

Useful:

```css
/* The last card snaps to the track edge so navigation never reveals filler. */
```

Hollow:

```css
/* Project card styles. */
```

