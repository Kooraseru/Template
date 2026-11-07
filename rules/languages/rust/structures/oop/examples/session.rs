/// Owns a single session's lifecycle and operation count.
///
/// Once closed, the session cannot be reactivated.
pub struct Session {
    active: bool,
    operations: usize,
}

impl Session {
    /// Starts an active session with no recorded operations.
    pub fn new() -> Self {
        Self {
            active: true,
            operations: 0,
        }
    }

    /// Records an operation if the session is active.
    ///
    /// Returns false when the session has already been closed.
    pub fn record_operation(&mut self) -> bool {
        if !self.active {
            return false;
        }

        self.operations += 1;
        true
    }

    /// Closes the session. Repeated calls have no additional effect.
    pub fn close(&mut self) {
        self.active = false;
    }

    /// Returns the number of operations accepted before closure.
    pub fn operations(&self) -> usize {
        self.operations
    }
}

impl Default for Session {
    fn default() -> Self {
        Self::new()
    }
}
