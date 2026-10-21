import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { test } from "node:test";

const helper = resolve("ci/libraries/bootstrap/native.mjs");
const fixtures = JSON.parse(readFileSync("libraries/bootstrap/ruleset.json", "utf8"));

function call(operation, input, succeeds = true) {
  const result = spawnSync(process.execPath, [helper, operation], {
    input: JSON.stringify(input),
    encoding: "utf8",
    maxBuffer: 4 * 1024 * 1024,
  });
  if (succeeds) {
    assert.equal(result.status, 0, result.stderr);
    return JSON.parse(result.stdout);
  }
  assert.notEqual(result.status, 0, "expected native operation to fail");
  return result.stderr;
}

test("ECMAScript number spellings match every canonical JSON fixture", () => {
  const vectors = fixtures.canonical.cases.filter((entry) => entry.input.kind === "number");
  assert.ok(vectors.length >= 20, "number vectors unexpectedly missing");
  assert.deepEqual(
    call("numbers", vectors.map((entry) => entry.input.text)),
    vectors.map((entry) => entry.expected.text),
  );
  call("numbers", ["invalid"], false);
});

test("RFC8032 Ed25519 signatures match existing golden vectors", () => {
  for (const vector of fixtures.authentication.vectors) {
    const signature = call("sign", {
      message_hex: vector.message_utf8_hex,
      key_der_hex: vector.private_pkcs8_der_hex,
    });
    assert.equal(signature, vector.signature_hex, vector.name);
    const request = {
      message_hex: vector.message_utf8_hex,
      signature_hex: signature,
      key_der_hex: vector.public_spki_der_hex,
    };
    assert.equal(call("verify", request), true);
    assert.equal(call("verify", { ...request, message_hex: request.message_hex + "0a" }), false);
    assert.equal(call("verify", { ...request, signature_hex: signature.slice(0, -2) }), false);
    assert.equal(call("verify", { ...request, signature_hex: "00".repeat(64) }), false);
  }
});

test("UUID is random RFC4122 version 4", () => {
  const id = call("uuid", {});
  assert.match(id, /^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/);
  assert.notEqual(id, call("uuid", {}));
});

test("private key lifecycle respects external key restrictions", () => {
  const root = mkdtempSync(join(tmpdir(), "template-native-"));
  try {
    const workspace = join(root, "workspace");
    mkdirSync(workspace);
    const filename = join(root, "private.pem");
    const publicPem = call("keygen", { path: filename, workspace });
    assert.match(publicPem, /BEGIN PUBLIC KEY/);
    assert.match(readFileSync(filename, "utf8"), /BEGIN PRIVATE KEY/);
    if (process.platform !== "win32") assert.equal(statSync(filename).mode & 0o777, 0o600);
    const privatePem = call("keyfile", { path: filename, workspace });
    const signature = call("sign", { message_hex: "74657374", key_pem: privatePem });
    assert.equal(call("verify", { message_hex: "74657374", signature_hex: signature, key_pem: publicPem }), true);
    call("keygen", { path: filename, workspace }, false);
    const inside = join(workspace, "secret.pem");
    call("keygen", { path: inside, workspace }, false);
    writeFileSync(inside, privatePem);
    call("keyfile", { path: inside, workspace }, false);
    call("keyfile", { path: "relative.pem", workspace }, false);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("unsupported png operation fails closed", () => {
  call("png", {}, false);
});
