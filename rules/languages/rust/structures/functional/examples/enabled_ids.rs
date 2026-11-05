/// A target and its selection flag.
#[derive(Debug, Clone, Copy)]
pub struct Target {
    pub id: u64,
    pub enabled: bool,
}

/// Collects enabled IDs, retaining their original input order.
///
/// This is a direct transformation; its iterator chain needs no phase comments.
pub fn enabled_ids(targets: &[Target]) -> Vec<u64> {
    targets
        .iter()
        .filter(|target| target.enabled)
        .map(|target| target.id)
        .collect()
}
