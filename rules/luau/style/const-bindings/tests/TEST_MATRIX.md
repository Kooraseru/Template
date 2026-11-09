# Const binding fixtures

- An import read inside a closure and a table whose fields change can both use const.
- A compound assignment and a direct reassignment inside a closure keep their bindings mutable.
- The former naming fixture still checks scalar const advice under this rule.
- A returned module table and its method's temporary local produce no findings.
