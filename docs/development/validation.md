# Development And Validation

Repository validation is owned by `.github/workflows/validate.yml`. Local
checks run the same scripts used by GitHub Actions:

```bash
python .github/scripts/validate-repository.py
python .github/scripts/test-localization.py
python .github/scripts/test-publication.py
python .github/scripts/test-publication-manifests.py
python .github/scripts/build-docs.py
bash -n .github/scripts/publish-generated-branch.sh
bash .github/scripts/run-actionlint.sh
```

Build both local publication payloads with:

```bash
python .github/scripts/build-local-publications.py --version 0.0.0-local
```

The command requires the `source` branch. A clean worktree records exact HEAD.
A worktree with pending changes is captured in a temporary Git snapshot commit
without modifying the index, current branch, or source history. It writes
`.generated/repo/pre-release/` and `.generated/repo/release/` without modifying
branch refs. Remote publication continues to require committed canonical source.

The validation workflow checks GitHub configuration, issue form structure,
workflow security invariants, local Markdown links, project residue, and
localization and publication boundary tests. Localization rendering validates
the locale manifest, component trees, template keys, fallback graph, and
default English coverage. An external link check runs separately because it
requires network access.

Projects add formatting, linting, static analysis, unit tests, integration
tests, and build checks only when the corresponding source exists. Every added
check must have a GitHub Actions stage and an identical local command.
