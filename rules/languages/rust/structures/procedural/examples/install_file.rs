use std::fs;
use std::io::{self, ErrorKind};
use std::path::Path;

pub fn install_file(source: &Path, destination: &Path) -> io::Result<u64> {
    if !source.is_file() {
        return Err(io::Error::new(ErrorKind::NotFound, "source file is missing"));
    }

    let Some(parent) = destination.parent() else {
        return Err(io::Error::new(ErrorKind::InvalidInput, "invalid destination"));
    };

    fs::create_dir_all(parent)?;
    fs::copy(source, destination)
}
