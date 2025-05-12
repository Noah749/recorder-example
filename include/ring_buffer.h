#pragma once

#include <vector>
#include <mutex>
#include <condition_variable>

class RingBuffer {
public:
    explicit RingBuffer(size_t size);
    
    bool write(const float* data, size_t count);
    bool read(float* data, size_t count);
    size_t available_read() const;
    size_t available_write() const;
    
    // 获取统计信息
    struct Stats {
        size_t overflow_count;
        size_t underflow_count;
        size_t max_used_size;
        size_t current_size;
    };
    
    Stats get_stats() const;
    void clear();
    
private:
    std::vector<float> buffer_;
    size_t read_pos_;
    size_t write_pos_;
    size_t size_;
    mutable std::mutex mutex_;
    std::condition_variable cv_;
    
    // 统计信息
    size_t overflow_count_;    // 溢出次数
    size_t underflow_count_;   // 欠载次数
    size_t max_used_size_;     // 最大使用量
};