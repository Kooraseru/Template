# Development And Validation

Repository validation is owned by `.github/workflows/validate.yml`. Local
checks run the same scripts used by GitHub Actions:

```bash
python .github/scripts/validate-repository.py
python .github/scripts/test-publication.py
python .github/scripts/test-publication-manifests.py
python .github/scripts/build-docs.py
bash -n .github/scripts/publish-generated-branch.sh
bash .github/scripts/run-actionlint.sh
```

The validation workflow checks GitHub configuration, issue form structure,
workflow security invariants, local Markdown links, project residue, and
publication boundary tests. An external link check runs separately because it
requires network access.

Projects add formatting, linting, static analysis, unit tests, integration
tests, and build checks only when the corresponding source exists. Every added
check must have a GitHub Actions stage and an identical local command.
