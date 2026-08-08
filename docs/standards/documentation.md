# Documentation Standards

Human-facing rules and project documentation live under `docs/` and are built
with MkDocs. Personal agent interpretation and private planning are not public
documentation and must not be referenced from these pages.

Prefer present tense, active voice, direct requirements, and canonical links.
Use “must” for requirements, “should” for recommendations, and “can” for
optional behavior. Format paths, commands, identifiers, and literals as code.

Keep examples short and executable. Do not document speculative APIs or
workflows as implemented behavior.

MkDocs writes only to `.generated/site/`. Never commit generated site output.
