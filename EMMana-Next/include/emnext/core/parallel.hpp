#pragma once

#include <algorithm>
#include <atomic>
#include <cstddef>
#include <exception>
#include <mutex>
#include <thread>
#include <vector>

namespace emnext {

[[nodiscard]] int configured_parallel_workers();

template <class Fn>
void parallel_for_ordered(std::size_t count, int workers, Fn&& fn) {
    if (count == 0) return;
    const int actual = std::max(1, std::min(workers, static_cast<int>(count)));
    if (actual == 1) {
        for (std::size_t i = 0; i < count; ++i) fn(i);
        return;
    }

    std::atomic<std::size_t> next{0};
    std::atomic<bool> failed{false};
    std::exception_ptr error;
    std::mutex error_mutex;
    std::vector<std::thread> threads;
    threads.reserve(static_cast<std::size_t>(actual));
    for (int w = 0; w < actual; ++w) {
        threads.emplace_back([&]() {
            while (!failed.load(std::memory_order_relaxed)) {
                const std::size_t i = next.fetch_add(1, std::memory_order_relaxed);
                if (i >= count) break;
                try {
                    fn(i);
                } catch (...) {
                    {
                        std::lock_guard<std::mutex> lock(error_mutex);
                        if (!error) error = std::current_exception();
                    }
                    failed.store(true, std::memory_order_relaxed);
                    break;
                }
            }
        });
    }
    for (auto& t : threads) t.join();
    if (error) std::rethrow_exception(error);
}

} // namespace emnext
