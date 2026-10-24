# GitHub Projects

Each lowercase directory owns one project. `project.toml` identifies its title,
visibility and management mode. Files in `fields/`, `views/`, and `automations/`
are discovered by shape, not declared in an inventory or numbered schema.

`managed` projects are reconciled for this repository. `template` describes a
canonical project that contributors can copy; personal copies are never managed.
Organization-owned projects can be marked as GitHub-native templates; user-owned
projects cannot. The canonical Workspace is still copyable through GitHub's API.

Issue and PR state remains authoritative. Project fields express planning intent,
not repository permissions. Public project automations must not expose private
repository issues. Views currently manage names and layouts only; filters and
grouping need GitHub UI configuration until supported by the adapter.

See `ci/integration/github/README.md` for execution and authorization.
