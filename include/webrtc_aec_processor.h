 #ifndef WEBRTC_AEC_PROCESSOR_H_
#define WEBRTC_AEC_PROCESSOR_H_

#include <memory>
#include "modules/audio_processing/include/audio_processing.h"

class WebRTCAECProcessor {
public:
    WebRTCAECProcessor();
    ~WebRTCAECProcessor();

    // 送入远端（扬声器）音频数据
    void FeedReverseStream(const float* const* data, int sample_rate, int channels, int frames);
    // 处理本地采集音频数据
    void ProcessCaptureStream(float* const* data, int sample_rate, int channels, int frames);

private:
    std::unique_ptr<webrtc::AudioProcessing> apm_;
};

#endif // WEBRTC_AEC_PROCESSOR_H_
