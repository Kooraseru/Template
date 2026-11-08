# Phase comment fixtures

- [Unexplained workflow](invalid/unexplained-workflow.luau) reports the first transition despite a section marker and a trailing comment.
- [Explained workflow](valid/explained-workflow.luau) accepts an attached block comment before the loop and an attached line comment before the next phase.
- [Long literal](valid/long-literal.luau) keeps a long data table below the executable statement threshold.
