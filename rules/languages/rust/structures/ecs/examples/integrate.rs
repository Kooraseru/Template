// A system processing kernel: actual ECS query and scheduling belong to the chosen framework.
pub struct Position {
    pub x: f32,
    pub y: f32,
}

pub struct Velocity {
    pub dx: f32,
    pub dy: f32,
}

pub fn integrate(position: &mut Position, velocity: &Velocity, delta_seconds: f32) {
    if delta_seconds <= 0.0 {
        return;
    }

    position.x += velocity.dx * delta_seconds;
    position.y += velocity.dy * delta_seconds;
}
