// Candidate Rust-free native primitives. Not a production replacement until tests pass.
import { createPrivateKey, createPublicKey, generateKeyPairSync, randomUUID, sign, verify } from "node:crypto";
import { closeSync, mkdirSync, openSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import { basename, dirname, isAbsolute, join, relative, sep } from "node:path";

function unhex(hex) {
  if (typeof hex !== "string" || hex.length % 2 !== 0 || !/^[a-f0-9]*$/i.test(hex)) throw Error("invalid hexadecimal input");
  return Buffer.from(hex, "hex");
}

function decodeKey(input, kind) {
  if (typeof input.key_pem === "string")
    return kind === "private" ? createPrivateKey(input.key_pem) : createPublicKey(input.key_pem);
  const key = unhex(input.key_der_hex);
  return kind === "private"
    ? createPrivateKey({ key, format: "der", type: "pkcs8" })
    : createPublicKey({ key, format: "der", type: "spki" });
}

function outsideWorkspace(path, workspace, forRead) {
  if (typeof path !== "string" || !isAbsolute(path) || typeof workspace !== "string")
    throw Error("absolute external key path required");
  const root = realpathSync(workspace);
  const resolved = realpathSync(forRead ? path : dirname(path));
  const rel = relative(root, resolved);
  if (rel === "" || (rel !== ".." && !rel.startsWith(".." + sep) && !isAbsolute(rel)))
    throw Error("key must live outside repository");
  return forRead ? resolved : join(resolved, basename(path));
}

function call(op, input) {
  switch (op) {
    case "numbers":
      if (!Array.isArray(input)) throw Error("number array required");
      return input.map((text) => {
        if (typeof text !== "string" || !/^[-+]?(?:(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?|Infinity|inf|NaN|nan)$/.test(text))
          throw Error("invalid number spelling");
        return JSON.stringify(Number(text));
      });
    case "sign":
      return sign(null, unhex(input.message_hex), decodeKey(input, "private")).toString("hex");
    case "verify": {
      const signature = unhex(input.signature_hex);
      return signature.length === 64 && verify(null, unhex(input.message_hex), decodeKey(input, "public"), signature);
    }
    case "uuid":
      return randomUUID();
    case "keyfile":
      return readFileSync(outsideWorkspace(input.path, input.workspace, true), "utf8");
    case "keygen": {
      if (typeof input.path !== "string" || !isAbsolute(input.path)) throw Error("absolute external key path required");
      mkdirSync(dirname(input.path), { recursive: true });
      const filename = outsideWorkspace(input.path, input.workspace, false);
      const keys = generateKeyPairSync("ed25519", {
        privateKeyEncoding: { format: "pem", type: "pkcs8" },
        publicKeyEncoding: { format: "pem", type: "spki" },
      });
      const fd = openSync(filename, "wx", 0o600);
      try { writeFileSync(fd, keys.privateKey); } finally { closeSync(fd); }
      return keys.publicKey;
    }
    default:
      throw Error("unsupported native operation");
  }
}

try {
  if (process.argv.length !== 3) throw Error("expected one native operation");
  process.stdout.write(JSON.stringify(call(process.argv[2], JSON.parse(readFileSync(0, "utf8")))));
} catch (error) {
  process.stderr.write("Native adapter: " + (error instanceof Error ? error.message : "unknown error") + "\n");
  process.exitCode = 1;
}
