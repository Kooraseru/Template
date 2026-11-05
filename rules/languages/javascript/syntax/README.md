# JavaScript Syntax Check

`check.js` runs Node's parser over workspace JavaScript source without running
the files. Its fixture test proves that valid syntax passes and invalid syntax
is reported. The rule runner is declared in the checker, so adding it required
no shared registry entry.
