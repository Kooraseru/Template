# GitHub Configuration

This directory contains GitHub-facing policy, intake forms, repository
automation, MkDocs configuration, Pages deployment, and publication contracts.
MkDocs reads only rendered inputs from `content/pages/`, then writes
`.generated/site/`. Pages language selection updates the current document in
place and persists the selected locale in a cookie.

Private repository knowledge is intentionally not published in the repository. The
files in this directory must therefore be understandable and enforceable on
their own. Do not add a workflow, registry, or configuration file without an
active consumer and a responsible maintainer.

## Workflow Branches

<table>
  <tr>
    <td>Validation, dependency review, Pages, CodeQL, and publication</td>
    <td>Run from <code>source</code>, or for pull requests, validate changes whose base is <code>source</code>.</td>
  </tr>
  <tr>
    <td>First interaction, pull-request labeling, and scheduled stale processing</td>
    <td>Use the generated workflow definition on default branch <code>release</code> because GitHub dispatches these event types from the default branch. These jobs process metadata and do not check out or execute repository code.</td>
  </tr>
  <tr>
    <td>Manual stale processing</td>
    <td>Must be dispatched from <code>source</code>.</td>
  </tr>
</table>

The generated <code>release</code> branch is the repository default and public
landing branch. It is not an editing branch. Contributors target
<code>source</code>; only the owner or the protected publication workflow may
replace <code>pre-release</code> or <code>release</code>.
