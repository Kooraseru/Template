-- dependencies/packages/core/dataFormats/test.luau
--!strict
local Json = require("./json")
local Toml = require("./toml")
local Yaml = require("./yaml")
local Hash = require("./hash")

local decoded = Json.record(Json.decode(Json.encode({ message = "hello", items = { "one", "two" }, nested = { enabled = true } })))
assert(decoded.message == "hello")
assert(Json.record(decoded.nested).enabled == true)
local fields = 0
for _key in decoded do fields += 1 end
assert(fields == 3, "JSON decoding must hide internal object markers")
local config = Json.record(Toml.decode('[tool]\nname = "lute"\nenabled = true\n'))
assert(Json.record(config.tool).name == "lute")
local form = Json.record(Yaml.decode('name: Bug report\nbody:\n  - type: textarea\n    attributes:\n      label: Details\n'))
assert(form.name == "Bug report")
local roundTrip = Json.record(Yaml.decode(Yaml.encode({ jobs = { check = { ["runs-on"] = "ubuntu-latest" } } })))
assert(Json.record(Json.record(roundTrip.jobs).check)["runs-on"] == "ubuntu-latest")
assert(Hash.sha256("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
print("Data format checks passed")
