--!strict
local process = require("@lune/process")
local context = require("./context")
local policy = require("./policy")
local rules = require("../lib/rules")

assert(policy.canPublish(context.read(process.env)), "publication context is not eligible")
rules.validate(process.env, rules.read("ci/access/operation.rules.json"))
