use std::fs;
use std::io::{self, ErrorKind};
use std::path::Path;

/// Copies a source file to a destination, creating its parent directory.
///
/// An existing destination may be replaced. This is not an atomic deployment
/// operation; callers requiring rollback or transactional publication must use
/// an appropriately staged workflow.
///
/// # Errors
/// Returns an I/O error for a missing source, invalid destination parent,
/// directory creation failure, or unsuccessful copy.
pub fn install_file(source: &Path, destination: &Path) -> io::Result<u64> {
    // Reject missing source files before making changes to the destination.
    if !source.is_file() {
        return Err(io::Error::new(ErrorKind::NotFound, "source file is missing"));
    }

    let Some(parent) = destination.parent() else {
        return Err(io::Error::new(ErrorKind::InvalidInput, "invalid destination"));
    };

    // The target directory must exist before copying; errors propagate unchanged.
    fs::create_dir_all(parent)?;
    fs::copy(source, destination)
}
