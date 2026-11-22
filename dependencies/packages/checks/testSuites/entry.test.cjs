"use strict";

const test = require("node:test");
const { run } = require("./run.cjs");

// The pinned CI Engine discovers package tests. Project suites are discovered here.
test("project test suites", () => run());
