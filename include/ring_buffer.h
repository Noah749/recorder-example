#pragma once

#include <vector>
#include <mutex>
#include <condition_variable>

class RingBuffer {
public:
    RingBuffer(size_t size);
    
    bool write(const float* data, size_t count);
    bool read(float* data, size_t count);
    
    size_t available_read() const;
    size_t available_write() const;
    
private:
    std::vector<float> buffer_;
    size_t read_pos_;
    size_t write_pos_;
    size_t size_;
    mutable std::mutex mutex_;
    std::condition_variable cv_;
    
    size_t overflow_count_;
    size_t underflow_count_;
    size_t max_used_size_;
}; 