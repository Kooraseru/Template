-- libraries/bootstrap/native.luau
--!strict

local Native = {}

--# Modules

local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Serde = require("@lune/serde")
local Rules = require("../registry/rules")
local Bytes = require("./bytes")

--# Helpers

local function executable(): string
	return "build/native/release/ci-native" .. (if Process.os == "windows" then ".exe" else "")
end

--# Functions

function Native.Ensure(): string
	local sources = {
		"libraries/bootstrap/primitives/Cargo.toml",
		"libraries/bootstrap/primitives/Cargo.lock",
		"libraries/bootstrap/primitives/main.rs",
	}
	local identity = {}

	for _, path in sources do
		table.insert(identity, Serde.hash("sha256", Fs.readFile(path)))
	end

	local expected = table.concat(identity, "\n")
	local stamp = "build/native/inputs.sha256"
	local binary = executable()

	if not Fs.isFile(binary) or not Fs.isFile(stamp) or Fs.readFile(stamp) ~= expected then
		local build = Process.exec("cargo", {
			"build",
			"--locked",
			"--release",
			"--manifest-path",
			"libraries/bootstrap/primitives/Cargo.toml",
			"--target-dir",
			"build/native",
		})
		assert(build.ok, "cannot build native CI primitives: " .. build.stdout .. build.stderr)
		assert(Fs.isFile(binary), "native CI executable was not produced")
		Fs.writeFile(stamp, expected)
	end

	return binary
end

function Native.Call(operation: string, input: unknown): unknown
	assert(
		table.find({ "numbers", "sign", "verify", "uuid", "png", "keyfile", "keygen" }, operation),
		"invalid native operation"
	)
	local child = Process.create(Native.Ensure(), { operation })
	child.stdin:write(Serde.encode("json", input))
	child.stdin:close()
	local stdout = child.stdout:readToEnd()
	local stderr = child.stderr:readToEnd()
	assert(child:status().ok, "native " .. operation .. " failed: " .. stderr)

	return Serde.decode("json", stdout)
end

function Native.Numbers(values: { number }): { string }
	if #values == 0 then
		return {}
	end

	local input = {}

	for _, value in values do
		-- Seventeen significant digits preserve the original binary64 value. The
		-- native formatter selects ECMAScript's shortest round-tripping spelling.
		table.insert(input, string.format("%.17g", value))
	end

	local output = {}

	for _, value in Rules.Array(Native.Call("numbers", input)) do
		assert(type(value) == "string", "invalid native number representation")
		table.insert(output, value)
	end

	assert(#output == #values, "native number serialization changed the value count")

	return output
end

function Native.Sign(message: string, key: string, der: boolean?): string
	local input = { message_hex = Bytes.Hex(message), [if der then "key_der_hex" else "key_pem"] = key }
	local signature = Native.Call("sign", input)
	assert(type(signature) == "string" and #signature == 128 and signature:match("^%x+$"), "invalid native signature")

	return Bytes.FromHex(signature)
end

function Native.Verify(message: string, signature: string, key: string, der: boolean?): boolean
	local input = {
		message_hex = Bytes.Hex(message),
		signature_hex = Bytes.Hex(signature),
		[if der then "key_der_hex" else "key_pem"] = key,
	}
	local accepted = Native.Call("verify", input)
	assert(type(accepted) == "boolean", "invalid native verification result")

	return accepted
end

function Native.Run()
	Native.Ensure()
end

function Native.UUID(): string
	local value = Native.Call("uuid", {})
	assert(type(value) == "string", "invalid native UUID")
	return value
end

return Native
