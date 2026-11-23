"use strict";

function addedLines(patch) {
  const lines = new Set();
  let line = null;
  for (const entry of patch.split("\n")) {
    const hunk = /^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@/.exec(entry);
    if (hunk) line = Number(hunk[1]);
    else if (line !== null && entry.startsWith("+")) lines.add(line++);
    else if (line !== null && entry.startsWith(" ")) line++;
  }
  return lines;
}

module.exports = { addedLines };
