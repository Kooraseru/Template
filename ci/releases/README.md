# Release generation

Release generation is optional. Enable it in `ci/config.toml`, select an explicit
version, and author `ci/releases/records/<version>.md`. Every eligible execution
generates that release's notes and validated distribution files under
`build/releases/`; a push alone does not select a new version.

Publication and optional signing belong in trusted jobs after the shared CI gate.
Use the repository's `GITHUB_TOKEN` where supported. External publication and
signing require configuration by the consuming repository.
