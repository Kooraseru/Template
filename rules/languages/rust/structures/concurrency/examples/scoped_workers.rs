use std::thread;

/// Sums two halves in parallel while borrowing the caller's input.
///
/// Scoped threads cannot outlive the borrowed slice.
///
/// # Errors
/// Returns the worker's panic payload if the spawned half panics.
///
/// # Panics
/// Integer overflow can panic in builds with overflow checks enabled.
pub fn sum_parallel(values: &[u64]) -> thread::Result<u64> {
    // Split the input so the worker and caller read disjoint ranges.
    let (left, right) = values.split_at(values.len() / 2);

    thread::scope(|scope| {
        let worker = scope.spawn(|| left.iter().copied().sum::<u64>());
        let right_sum = right.iter().copied().sum::<u64>();

        // A scoped worker is joined before this function returns.
        worker.join().map(|left_sum| left_sum + right_sum)
    })
}
