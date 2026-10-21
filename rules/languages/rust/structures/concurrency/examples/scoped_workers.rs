use std::thread;

pub fn sum_parallel(values: &[u64]) -> thread::Result<u64> {
    let (left, right) = values.split_at(values.len() / 2);

    thread::scope(|scope| {
        let worker = scope.spawn(|| left.iter().copied().sum::<u64>());
        let right_sum = right.iter().copied().sum::<u64>();

        worker.join().map(|left_sum| left_sum + right_sum)
    })
}
