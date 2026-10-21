#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Platform {
    Linux,
    Windows,
    MacOs,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BuildTarget {
    name: String,
    platform: Platform,
}

impl BuildTarget {
    pub fn try_new(name: impl Into<String>, platform: Platform) -> Option<Self> {
        let name = name.into();
        if name.trim().is_empty() {
            return None;
        }

        Some(Self { name, platform })
    }

    pub fn name(&self) -> &str {
        &self.name
    }

    pub fn platform(&self) -> &Platform {
        &self.platform
    }
}
