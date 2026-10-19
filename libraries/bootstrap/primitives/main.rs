use ed25519_dalek::{
    pkcs8::{DecodePrivateKey, DecodePublicKey},
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
