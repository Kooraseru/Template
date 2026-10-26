/// Dimensions received from a foreign C-compatible API.
///
/// Layout compatibility does not imply that the values are valid.
#[repr(C)]
pub struct RawDimensions {
    pub width: u32,
    pub height: u32,
}

/// Validated dimensions with nonzero width and height.
#[derive(Debug, PartialEq, Eq)]
pub struct Dimensions {
    width: u32,
    height: u32,
}

/// Error returned when foreign dimensions violate the Rust-side invariant.
#[derive(Debug)]
pub enum DimensionsError {
    /// One or both dimensions were zero.
    ZeroSize,
}

impl TryFrom<RawDimensions> for Dimensions {
    type Error = DimensionsError;

    fn try_from(raw: RawDimensions) -> Result<Self, Self::Error> {
        // Validate at the boundary before constructing the trusted domain type.
        if raw.width == 0 || raw.height == 0 {
            return Err(DimensionsError::ZeroSize);
        }

        Ok(Self {
            width: raw.width,
            height: raw.height,
        })
    }
}

impl Dimensions {
    /// Returns the validated width.
    pub fn width(&self) -> u32 {
        self.width
    }

    /// Returns the validated height.
    pub fn height(&self) -> u32 {
        self.height
    }
}
