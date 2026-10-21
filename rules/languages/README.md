# Global language guidance drafts

These files are review drafts for `.kero/mnt/global/language/`. They are placed
here because that mount is a read-only KERO snapshot. The local host currently
reports no valid provenance or sync baseline for this mount. The authoritative
global source requires a healthy mount, signed source-owned grant, and explicit
sync before these can be promoted. Do not treat this folder as a second global
language source.

The intended destination preserves this relative tree:

```text
language/
  language-system.md
  comments.md
  html/
    README.md
    documents.md
    templates.md
  css/
    README.md
    modules.md
    tokens-and-themes.md
  javascript/
    README.md
    modules.md
    browser-boundaries.md
```

The existing Luau guidance remains authoritative for Luau. These drafts borrow
its responsibility-first file selection, explicit ownership, boundary handling,
and comment style without forcing Luau syntax onto browser languages.
The proposed `language-system.md` extends the existing global document and must
be merged with it during promotion, not blindly replace it.
