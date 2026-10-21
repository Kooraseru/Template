#[derive(Debug, Clone, Copy)]
pub struct Target {
    pub id: u64,
    pub enabled: bool,
}

pub fn enabled_ids(targets: &[Target]) -> Vec<u64> {
    targets
        .iter()
        .filter(|target| target.enabled)
        .map(|target| target.id)
        .collect()
}
