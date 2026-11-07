// This is the processing kernel; query selection and scheduling belong to an ECS framework.

/// Position in the simulation's two-dimensional coordinate system.
pub struct Position {
    pub x: f32,
    pub y: f32,
}

/// Velocity measured in coordinate units per second.
pub struct Velocity {
    pub dx: f32,
    pub dy: f32,
}

/// Advances one position with its velocity for a positive time step.
///
/// Nonpositive deltas are intentionally ignored; callers must validate non-finite
/// values at their data-ingress boundary.
pub fn integrate(position: &mut Position, velocity: &Velocity, delta_seconds: f32) {
    if delta_seconds <= 0.0 {
        return;
    }

    // Keep the integration rule independent of entity storage and scheduling.
    position.x += velocity.dx * delta_seconds;
    position.y += velocity.dy * delta_seconds;
}
