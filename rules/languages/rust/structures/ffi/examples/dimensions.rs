#[repr(C)]
pub struct RawDimensions {
    pub width: u32,
    pub height: u32,
}

#[derive(Debug, PartialEq, Eq)]
pub struct Dimensions {
    pub width: u32,
    pub height: u32,
}

#[derive(Debug)]
pub enum DimensionsError {
    ZeroSize,
}

impl TryFrom<RawDimensions> for Dimensions {
    type Error = DimensionsError;

    fn try_from(raw: RawDimensions) -> Result<Self, Self::Error> {
        if raw.width == 0 || raw.height == 0 {
            return Err(DimensionsError::ZeroSize);
        }

        Ok(Self {
            width: raw.width,
            height: raw.height,
        })
    }
}
