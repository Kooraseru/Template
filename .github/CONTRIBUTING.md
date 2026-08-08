# Contributing

## Before You Start

Read [`SOURCE.md`](../SOURCE.md) and the relevant files under [`docs/`](../docs/).
Use Discussions for open-ended ideas or support questions. Use the appropriate
issue form for a reproducible defect or concrete proposal. Report
vulnerabilities privately through the repository Security tab.

## Contribution Flow

1. Fork or branch from current `source`.
2. Keep the change focused on one agreed problem.
3. Update tests and human documentation with the implementation.
4. Run the same validation commands owned by GitHub Actions.
5. Open a pull request targeting `source`.
6. Include the problem, implementation, compatibility impact, and exact test
   results in the pull request.
7. Address review feedback and keep the branch current until merge.

Never target `pre-release` or `release`; automation owns both branches.

## Review Expectations

Maintainers review correctness, scope, security, compatibility, tests,
documentation, and ownership boundaries. Approval does not waive required
checks. A maintainer may ask that a broad proposal return to Discussion before
implementation continues.

By contributing, you agree to follow the repository Code of Conduct.
