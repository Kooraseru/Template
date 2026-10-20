use ed25519_dalek::{
    pkcs8::{
        spki::der::pem::LineEnding, DecodePrivateKey, DecodePublicKey, EncodePrivateKey,
        EncodePublicKey,
    },
    Signature, Signer, SigningKey, VerifyingKey,
};
use std::io::{self, Read, Write};

type Error = Box<dyn std::error::Error>;

fn decode_hex(text: &str) -> Result<Vec<u8>, Error> {
    if !text.is_ascii() || text.len() % 2 != 0 {
        return Err("invalid hexadecimal bytes".into());
    }
    text.as_bytes()
        .chunks_exact(2)
        .map(|pair| {
            let high = (pair[0] as char)
                .to_digit(16)
                .ok_or("invalid hexadecimal digit")?;
            let low = (pair[1] as char)
                .to_digit(16)
                .ok_or("invalid hexadecimal digit")?;
            Ok((high * 16 + low) as u8)
        })
        .collect()
}

fn encode_hex(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

fn field<'a>(value: &'a serde_json::Value, name: &str) -> Result<&'a str, Error> {
    value
        .get(name)
        .and_then(serde_json::Value::as_str)
        .ok_or_else(|| "missing native request field".into())
}

fn run() -> Result<(), Box<dyn std::error::Error>> {
    let command = std::env::args().nth(1).ok_or("missing native operation")?;
    let mut input = String::new();
    io::stdin().read_to_string(&mut input)?;
    match command.as_str() {
        "png" => {
            let request: serde_json::Value = serde_json::from_str(&input)?;
            let mut options = resvg::usvg::Options::default();
            options.font_family = "JetBrains Mono".into();
            options
                .fontdb_mut()
                .load_font_file(field(&request, "font")?)?;
            let tree = resvg::usvg::Tree::from_str(field(&request, "svg")?, &options)?;
            let size = tree.size().to_int_size();
            let pixels = u64::from(size.width()) * u64::from(size.height());
            if pixels > 100_000_000 {
                return Err("render exceeds pixel budget".into());
            }
            let mut pixmap = resvg::tiny_skia::Pixmap::new(size.width(), size.height())
                .ok_or("invalid render size")?;
            resvg::render(
                &tree,
                resvg::tiny_skia::Transform::default(),
                &mut pixmap.as_mut(),
            );
            io::stdout().write_all(&serde_json::to_vec(&encode_hex(&pixmap.encode_png()?))?)?;
        }
        "keyfile" | "keygen" => {
            let request: serde_json::Value = serde_json::from_str(&input)?;
            let destination = std::path::Path::new(field(&request, "path")?);
            if !destination.is_absolute() {
                return Err("absolute external key path required".into());
            }
            let workspace = std::fs::canonicalize(field(&request, "workspace")?)?;
            if command == "keyfile" {
                let resolved = std::fs::canonicalize(destination)?;
                if resolved.starts_with(&workspace) {
                    return Err("key must live outside repository".into());
                }
                io::stdout()
                    .write_all(&serde_json::to_vec(&std::fs::read_to_string(resolved)?)?)?;
            } else {
                let parent = destination.parent().ok_or("missing key directory")?;
                std::fs::create_dir_all(parent)?;
                let resolved_parent = std::fs::canonicalize(parent)?;
                if resolved_parent.starts_with(&workspace) {
                    return Err("key must live outside repository".into());
                }
                let mut seed = [0u8; 32];
                getrandom::getrandom(&mut seed).map_err(|error| error.to_string())?;
                let key = SigningKey::from_bytes(&seed);
                let mut options = std::fs::OpenOptions::new();
                options.write(true).create_new(true);
                #[cfg(unix)]
                {
                    use std::os::unix::fs::OpenOptionsExt;
                    options.mode(0o600);
                }
                let file =
                    resolved_parent.join(destination.file_name().ok_or("missing key filename")?);
                options
                    .open(file)?
                    .write_all(key.to_pkcs8_pem(LineEnding::LF)?.as_bytes())?;
                io::stdout().write_all(&serde_json::to_vec(
                    &key.verifying_key().to_public_key_pem(LineEnding::LF)?,
                )?)?;
            }
        }
        "uuid" => {
            let mut bytes = [0u8; 16];
            getrandom::getrandom(&mut bytes).map_err(|error| error.to_string())?;
            bytes[6] = (bytes[6] & 0x0f) | 0x40;
            bytes[8] = (bytes[8] & 0x3f) | 0x80;
            let hex = encode_hex(&bytes);
            let uuid = format!(
                "{}-{}-{}-{}-{}",
                &hex[..8],
                &hex[8..12],
                &hex[12..16],
                &hex[16..20],
                &hex[20..]
            );
            io::stdout().write_all(&serde_json::to_vec(&uuid)?)?;
        }
        "numbers" => {
            let numbers: Vec<String> = serde_json::from_str(&input)?;
            let mut buffer = ryu_js::Buffer::new();
            let output: Result<Vec<String>, _> = numbers
                .iter()
                .map(|text| {
                    text.parse::<f64>().map(|value| {
                        if !value.is_finite() {
                            "null".to_owned()
                        } else if value == 0.0 {
                            "0".to_owned()
                        } else {
                            buffer.format_finite(value).to_owned()
                        }
                    })
                })
                .collect();
            io::stdout().write_all(&serde_json::to_vec(&output?)?)?;
        }
        "sign" => {
            let request: serde_json::Value = serde_json::from_str(&input)?;
            let message = decode_hex(field(&request, "message_hex")?)?;
            let key = if let Some(pem) = request.get("key_pem").and_then(serde_json::Value::as_str)
            {
                SigningKey::from_pkcs8_pem(pem)?
            } else {
                SigningKey::from_pkcs8_der(&decode_hex(field(&request, "key_der_hex")?)?)?
            };
            let signature = key.sign(&message);
            io::stdout().write_all(&serde_json::to_vec(&encode_hex(&signature.to_bytes()))?)?;
        }
        "verify" => {
            let request: serde_json::Value = serde_json::from_str(&input)?;
            let message = decode_hex(field(&request, "message_hex")?)?;
            let key = if let Some(pem) = request.get("key_pem").and_then(serde_json::Value::as_str)
            {
                VerifyingKey::from_public_key_pem(pem)?
            } else {
                VerifyingKey::from_public_key_der(&decode_hex(field(&request, "key_der_hex")?)?)?
            };
            let signature = decode_hex(field(&request, "signature_hex")?)?;
            let accepted = Signature::from_slice(&signature)
                .is_ok_and(|signature| key.verify_strict(&message, &signature).is_ok());
            io::stdout().write_all(&serde_json::to_vec(&accepted)?)?;
        }
        _ => return Err("unknown native operation".into()),
    }
    Ok(())
}

fn main() {
    if let Err(error) = run() {
        eprintln!("ci-native: {error}");
        std::process::exit(1);
    }
}
