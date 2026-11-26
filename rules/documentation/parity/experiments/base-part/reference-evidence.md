# Reference evidence

Source: user-provided rendered DOM export of the official BasePart Creator Hub page, received 2026-11-26. The captured document identified the site asset revision `4abb18a21bce7bbd4d173b333e54a277c1a1cf38`. The raw export contains browser-extension markup and potentially account-specific UI; it is deliberately not committed.

The original page title is a styled span (not an h1). API member titles are also spans with case-sensitive member IDs. The experiment maps the respective semantic elements rather than assuming identical markup. All three reference selectors were checked for a unique match against the supplied DOM.

Observed stylesheet declarations (not computed browser measurements):

| Component | Declarations |
|---|---|
| Page title | Builder Sans, 28px, weight 700, line-height 130% |
| API member heading | Builder Sans, 24px, weight 700, line-height 120% |
| Signature panel | Builder Mono, 14px, line-height 140%, 12px padding, 4px radius, background rgb(25, 26, 31) |
| Multiline parameter indentation | 24px |
| Code controls | rgb(188, 190, 200) normal, rgb(247, 247, 248) hover |
| Scrollbar | thin, grey thumb, transparent track |

This evidence does not substitute for screenshot baselines or computed styles. Capture the live reference explicitly using the workflow dispatch or local capture command. Do not treat static declarations as a passing visual comparison.

## Captured browser evidence

Workflow dispatch [45876453646](https://github.com/Kooraseru/Template/actions/runs/45876453646) successfully acquired all four reference scenarios. The committed reference metrics and screenshot digests originate from its downloaded capture artifact, not Template's candidate output. See `reference/provenance.json` for provenance. The raw PNG archive is not yet committed; the exact image equality criterion is retained by its digests.

## Structural reference

The complete article structure was independently recovered from the original rendered HTML export, parsed with Chromium DOMParser without executing page scripts or fetching resources. See `reference/structure-provenance.json` and `reference/structure.json.gz.b64`. The baseline covers all 13,877 elements in the article root, not just the title and signatures.
