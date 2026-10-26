/// A build target's operating-system family.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Platform {
    Linux,
    Windows,
    MacOs,
}

/// A validated build target descriptor.
///
/// Fields remain private so construction enforces a nonblank name.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BuildTarget {
    name: String,
    platform: Platform,
}

impl BuildTarget {
    /// Creates a target, rejecting names containing only whitespace.
    pub fn try_new(name: impl Into<String>, platform: Platform) -> Option<Self> {
        let name = name.into();
        if name.trim().is_empty() {
            return None;
        }

        Some(Self { name, platform })
    }

    /// Returns the configured target name.
    pub fn name(&self) -> &str {
        &self.name
    }

    /// Returns the target operating-system family.
    pub fn platform(&self) -> &Platform {
        &self.platform
    }
}
