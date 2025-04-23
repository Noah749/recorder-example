#include "ring_buffer.h"
#include "logger.h"

RingBuffer::RingBuffer(size_t size) 
    : buffer_(size)
    , read_pos_(0)
    , write_pos_(0)
    , size_(size)
    , overflow_count_(0)
    , underflow_count_(0)
    , max_used_size_(0) {
}

bool RingBuffer::write(const float* data, size_t count) {
    std::unique_lock<std::mutex> lock(mutex_);
    
    if (available_write() < count) {
        overflow_count_++;
        if (overflow_count_ % 100 == 0) {
            Logger::warn("环形缓冲区溢出次数: %zu", overflow_count_);
        }
        return false;
    }
    
    for (size_t i = 0; i < count; ++i) {
        buffer_[write_pos_] = data[i];
        write_pos_ = (write_pos_ + 1) % size_;
    }
    
    size_t used_size = available_read();
    if (used_size > max_used_size_) {
        max_used_size_ = used_size;
    }
    
    cv_.notify_one();
    return true;
}

bool RingBuffer::read(float* data, size_t count) {
    std::unique_lock<std::mutex> lock(mutex_);
    
    if (available_read() < count) {
        if (cv_.wait_for(lock, std::chrono::milliseconds(10), 
                       [this, count] { return available_read() >= count; })) {
            underflow_count_++;
            if (underflow_count_ % 100 == 0) {
                Logger::warn("环形缓冲区欠载次数: %zu", underflow_count_);
            }
            return false;
        }
    }
    
    for (size_t i = 0; i < count; ++i) {
        data[i] = buffer_[read_pos_];
        read_pos_ = (read_pos_ + 1) % size_;
    }
    return true;
}

size_t RingBuffer::available_read() const {
    if (write_pos_ >= read_pos_) {
        return write_pos_ - read_pos_;
    }
    return size_ - read_pos_ + write_pos_;
}

size_t RingBuffer::available_write() const {
    return size_ - available_read() - 1;
} 