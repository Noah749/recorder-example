#include "mac_recorder.h"

MacRecorder::MacRecorder()
    : recorder_(nullptr)
    , systemCapture_(nullptr)
    , deviceManager_(nullptr)
    , isRecording_(false)
    , systemAudioVolume_(1.0f)
    , microphoneVolume_(1.0f) {
}

MacRecorder::MacRecorder(AudioRecorder* recorder)
    : recorder_(recorder)
    , systemCapture_(nullptr)
    , deviceManager_(nullptr)
    , isRecording_(false)
    , systemAudioVolume_(1.0f)
    , microphoneVolume_(1.0f) {
}

MacRecorder::~MacRecorder() {
}

bool MacRecorder::Start() {
    return true;
}

void MacRecorder::Stop() {
}

bool MacRecorder::IsRecording() const {
    return true;
}

void MacRecorder::Pause() {
}

void MacRecorder::Resume() {
}

bool MacRecorder::IsRunning() const {
    return true;
}

void MacRecorder::SetOutputPath(const std::string& path) {
    outputPath_ = path;
}

std::string MacRecorder::GetCurrentMicrophoneApp() const {
    return currentMicApp_;
}

void MacRecorder::SetSystemAudioVolume(float volume) {
    systemAudioVolume_ = volume;
}

void MacRecorder::SetMicrophoneVolume(float volume) {
    microphoneVolume_ = volume;
}
