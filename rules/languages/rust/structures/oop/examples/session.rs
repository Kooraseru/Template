pub struct Session {
    active: bool,
    operations: usize,
}

impl Session {
    pub fn new() -> Self {
        Self {
            active: true,
            operations: 0,
        }
    }

    pub fn record_operation(&mut self) -> bool {
        if !self.active {
            return false;
        }

        self.operations += 1;
        true
    }

    pub fn close(&mut self) {
        self.active = false;
    }

    pub fn operations(&self) -> usize {
        self.operations
    }
}
