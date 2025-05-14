#include "webrtc_aec_processor.h"
#include "api/audio/audio_processing.h"
#include "api/audio/builtin_audio_processing_builder.h"
#include "api/environment/environment.h"
#include "api/environment/environment_factory.h"

using namespace webrtc;

WebRTCAECProcessor::WebRTCAECProcessor() {
    AudioProcessing::Config config;
    config.echo_canceller.enabled = true;
    config.echo_canceller.mobile_mode = false; // 使用 AEC3
    config.noise_suppression.enabled = true;
    config.gain_controller1.enabled = true;
    config.gain_controller1.mode = AudioProcessing::Config::GainController1::kAdaptiveDigital;
    

    apm_->ApplyConfig(config);
    // auto env = EnvironmentFactory().Create();
    // auto apm = BuiltinAudioProcessingBuilder(config).Build(env);
    // apm_ = std::unique_ptr<AudioProcessing>(apm.get());
}

WebRTCAECProcessor::~WebRTCAECProcessor() {
    apm_.reset();
}

void WebRTCAECProcessor::FeedReverseStream(const float* const* data, int sample_rate, int channels, int frames) {
    if (!apm_) return;
    StreamConfig config(sample_rate, channels);
    apm_->ProcessReverseStream(data, config, config, nullptr);
}

void WebRTCAECProcessor::ProcessCaptureStream(float* const* data, int sample_rate, int channels, int frames) {
    if (!apm_) return;
    StreamConfig config(sample_rate, channels);
    apm_->ProcessStream(data, config, config, data);
}
