#include <napi.h>
#include "../../include/recorder.h"
#include "../../include/aggregate_device.h"
#include "../../include/audio_system_capture.h"
#include <iostream>
#include <memory>
#include <queue>
#include <mutex>
#include <condition_variable>
#include <thread>

class RecorderWrapper : public Napi::ObjectWrap<RecorderWrapper> {
public:
    static Napi::Object Init(Napi::Env env, Napi::Object exports) {
        Napi::Function func = DefineClass(env, "Recorder", {
            InstanceMethod("start", &RecorderWrapper::Start),
            InstanceMethod("stop", &RecorderWrapper::Stop),
            InstanceMethod("pause", &RecorderWrapper::Pause),
            InstanceMethod("resume", &RecorderWrapper::Resume),
            InstanceMethod("isRecording", &RecorderWrapper::IsRecording),
            InstanceMethod("setOutputPath", &RecorderWrapper::SetOutputPath),
            InstanceMethod("getCurrentMicrophoneApp", &RecorderWrapper::GetCurrentMicrophoneApp),
            InstanceMethod("createAggregateDevice", &RecorderWrapper::CreateAggregateDevice),
            InstanceMethod("releaseAggregateDevice", &RecorderWrapper::ReleaseAggregateDevice),
            InstanceMethod("initSystemCapture", &RecorderWrapper::InitSystemCapture),
            InstanceMethod("startSystemCapture", &RecorderWrapper::StartSystemCapture),
            InstanceMethod("stopSystemCapture", &RecorderWrapper::StopSystemCapture),
            InstanceMethod("setSystemCaptureCallback", &RecorderWrapper::SetSystemCaptureCallback),
            InstanceMethod("getAudioFormat", &RecorderWrapper::GetAudioFormat)
        });

        exports.Set("Recorder", func);
        return exports;
    }

    RecorderWrapper(const Napi::CallbackInfo& info) : Napi::ObjectWrap<RecorderWrapper>(info) {
        try {
            recorder_ = new AudioRecorder();
            if (!recorder_) {
                throw std::runtime_error("Failed to create AudioRecorder");
            }
        } catch (const std::exception& e) {
            Napi::Error::New(info.Env(), e.what()).ThrowAsJavaScriptException();
        }
    }

    ~RecorderWrapper() {
        if (recorder_) {
            try {
                delete recorder_;
                recorder_ = nullptr;
            } catch (const std::exception& e) {
            }
        }
        if (aggregateDevice_) {
            try {
                delete aggregateDevice_;
                aggregateDevice_ = nullptr;
            } catch (const std::exception& e) {
            }
        }
        if (systemCapture_) {
            try {
                delete systemCapture_;
                systemCapture_ = nullptr;
            } catch (const std::exception& e) {
            }
        }
        if (tsfn_) {
            tsfn_.Release();
        }
    }

private:
    void CheckRecorder(const Napi::CallbackInfo& info) {
        if (!recorder_) {
            Napi::Error::New(info.Env(), "AudioRecorder is not initialized").ThrowAsJavaScriptException();
        }
    }

    Napi::Value Start(const Napi::CallbackInfo& info) {
        Napi::Env env = info.Env();
        CheckRecorder(info);
        bool success = recorder_->Start();
        return Napi::Boolean::New(env, success);
    }

    void Stop(const Napi::CallbackInfo& info) {
        CheckRecorder(info);
        recorder_->Stop();
    }

    void Pause(const Napi::CallbackInfo& info) {
        CheckRecorder(info);
        recorder_->Pause();
    }

    void Resume(const Napi::CallbackInfo& info) {
        CheckRecorder(info);
        recorder_->Resume();
    }

    Napi::Value IsRecording(const Napi::CallbackInfo& info) {
        Napi::Env env = info.Env();
        CheckRecorder(info);
        bool isRecording = recorder_->IsRecording();
        return Napi::Boolean::New(env, isRecording);
    }

    void SetOutputPath(const Napi::CallbackInfo& info) {
        Napi::Env env = info.Env();
        CheckRecorder(info);
        
        if (info.Length() < 1 || !info[0].IsString()) {
            Napi::TypeError::New(env, "String expected").ThrowAsJavaScriptException();
            return;
        }

        try {
            std::string path = info[0].As<Napi::String>().Utf8Value();
            recorder_->SetOutputPath(path);
        } catch (const std::exception& e) {
            Napi::Error::New(env, e.what()).ThrowAsJavaScriptException();
        }
    }

    Napi::Value GetCurrentMicrophoneApp(const Napi::CallbackInfo& info) {
        Napi::Env env = info.Env();
        CheckRecorder(info);
        try {
            std::string appName = recorder_->GetCurrentMicrophoneApp();
            return Napi::String::New(env, appName);
        } catch (const std::exception& e) {
            Napi::Error::New(env, e.what()).ThrowAsJavaScriptException();
            return Napi::String::New(env, "");
        }
    }

    Napi::Value CreateAggregateDevice(const Napi::CallbackInfo& info) {
        Napi::Env env = info.Env();
        
        if (info.Length() < 1 || !info[0].IsString()) {
            Napi::TypeError::New(env, "String expected for device name").ThrowAsJavaScriptException();
            return env.Null();
        }

        try {
            std::string deviceName = info[0].As<Napi::String>().Utf8Value();
            aggregateDevice_ = new AggregateDevice(deviceName);
            
            if (aggregateDevice_->deviceID == kAudioObjectUnknown) {
                Napi::Error::New(env, "Failed to create aggregate device").ThrowAsJavaScriptException();
                return env.Null();
            }
            
            return Napi::Number::New(env, aggregateDevice_->deviceID);
        } catch (const std::exception& e) {
            Napi::Error::New(env, e.what()).ThrowAsJavaScriptException();
            return env.Null();
        }
    }

    Napi::Value ReleaseAggregateDevice(const Napi::CallbackInfo& info) {
        Napi::Env env = info.Env();
        
        if (!aggregateDevice_) {
            Napi::Error::New(env, "No aggregate device to release").ThrowAsJavaScriptException();
            return env.Null();
        }

        try {
            delete aggregateDevice_;
            aggregateDevice_ = nullptr;
            return Napi::Boolean::New(env, true);
        } catch (const std::exception& e) {
            Napi::Error::New(env, e.what()).ThrowAsJavaScriptException();
            return env.Null();
        }
    }

    Napi::Value InitSystemCapture(const Napi::CallbackInfo& info) {
        Napi::Env env = info.Env();
        
        if (!aggregateDevice_) {
            Napi::Error::New(env, "Aggregate device not initialized").ThrowAsJavaScriptException();
            return env.Null();
        }

        try {
            systemCapture_ = new AudioSystemCapture(aggregateDevice_);
            return Napi::Boolean::New(env, true);
        } catch (const std::exception& e) {
            Napi::Error::New(env, e.what()).ThrowAsJavaScriptException();
            return env.Null();
        }
    }

    Napi::Value StartSystemCapture(const Napi::CallbackInfo& info) {
        Napi::Env env = info.Env();
        
        if (!systemCapture_) {
            Napi::Error::New(env, "System capture not initialized").ThrowAsJavaScriptException();
            return env.Null();
        }

        try {
            bool success = systemCapture_->StartRecording();
            return Napi::Boolean::New(env, success);
        } catch (const std::exception& e) {
            Napi::Error::New(env, e.what()).ThrowAsJavaScriptException();
            return env.Null();
        }
    }

    Napi::Value StopSystemCapture(const Napi::CallbackInfo& info) {
        Napi::Env env = info.Env();
        
        if (!systemCapture_) {
            Napi::Error::New(env, "System capture not initialized").ThrowAsJavaScriptException();
            return env.Null();
        }

        try {
            isProcessing_ = false;
            queueCondition_.notify_one();
            
            systemCapture_->StopRecording();
            
            if (tsfn_) {
                tsfn_.Release();
                tsfn_ = nullptr;
            }
            
            return Napi::Boolean::New(env, true);
        } catch (const std::exception& e) {
            Napi::Error::New(env, e.what()).ThrowAsJavaScriptException();
            return env.Null();
        }
    }

    struct AudioData {
        std::vector<float> data;
        UInt32 numberFrames;
        UInt32 numberChannels;
        double timestamp;
    };

    std::queue<AudioData> audioDataQueue_;
    std::mutex queueMutex_;
    std::condition_variable queueCondition_;
    Napi::ThreadSafeFunction tsfn_;
    bool isProcessing_ = false;

    void ProcessAudioData() {
        while (isProcessing_) {
            AudioData audioData;
            {
                std::unique_lock<std::mutex> lock(queueMutex_);
                queueCondition_.wait(lock, [this] { return !audioDataQueue_.empty() || !isProcessing_; });
                
                if (!isProcessing_) break;
                
                audioData = std::move(audioDataQueue_.front());
                audioDataQueue_.pop();
            }

            auto callback = [](Napi::Env env, Napi::Function jsCallback, AudioData* data) {
                Napi::Object audioDataObj = Napi::Object::New(env);
                audioDataObj.Set("numberFrames", Napi::Number::New(env, data->numberFrames));
                audioDataObj.Set("numberChannels", Napi::Number::New(env, data->numberChannels));
                audioDataObj.Set("timestamp", Napi::Number::New(env, data->timestamp));
                
                Napi::ArrayBuffer arrayBuffer = Napi::ArrayBuffer::New(env, data->data.size() * sizeof(float));
                memcpy(arrayBuffer.Data(), data->data.data(), data->data.size() * sizeof(float));
                Napi::Float32Array audioArray = Napi::Float32Array::New(env, data->data.size(), arrayBuffer, 0);
                audioDataObj.Set("data", audioArray);
                
                jsCallback.Call({audioDataObj});
                delete data;
            };

            auto* data = new AudioData(std::move(audioData));
            tsfn_.BlockingCall(data, callback);
        }
    }

    Napi::Value SetSystemCaptureCallback(const Napi::CallbackInfo& info) {
        Napi::Env env = info.Env();
        
        if (!systemCapture_) {
            Napi::Error::New(env, "System capture not initialized").ThrowAsJavaScriptException();
            return env.Null();
        }

        if (info.Length() < 1 || !info[0].IsFunction()) {
            Napi::TypeError::New(env, "Function expected").ThrowAsJavaScriptException();
            return env.Null();
        }

        try {
            Napi::Function callback = info[0].As<Napi::Function>();
            
            tsfn_ = Napi::ThreadSafeFunction::New(
                env,
                callback,
                "AudioDataCallback",
                0,
                1
            );

            isProcessing_ = true;
            std::thread([this] { ProcessAudioData(); }).detach();

            systemCapture_->SetAudioDataCallback([this](const AudioBufferList* bufferList, UInt32 numberFrames, double timestamp) {
                if (bufferList && bufferList->mNumberBuffers > 0) {
                    const AudioBuffer& audioBuffer = bufferList->mBuffers[0];
                    float* audioData = static_cast<float*>(audioBuffer.mData);
                    size_t sampleCount = numberFrames * audioBuffer.mNumberChannels;
                    
                    AudioData data;
                    data.data.assign(audioData, audioData + sampleCount);
                    data.numberFrames = numberFrames;
                    data.numberChannels = audioBuffer.mNumberChannels;
                    data.timestamp = timestamp;
                    
                    {
                        std::lock_guard<std::mutex> lock(queueMutex_);
                        audioDataQueue_.push(std::move(data));
                    }
                    queueCondition_.notify_one();
                }
            });
            
            return Napi::Boolean::New(env, true);
        } catch (const std::exception& e) {
            Napi::Error::New(env, e.what()).ThrowAsJavaScriptException();
            return env.Null();
        }
    }

    Napi::Value GetAudioFormat(const Napi::CallbackInfo& info) {
        Napi::Env env = info.Env();
        
        if (!systemCapture_) {
            Napi::Error::New(env, "System capture not initialized").ThrowAsJavaScriptException();
            return env.Null();
        }

        try {
            AudioStreamBasicDescription format;
            if (!systemCapture_->GetAudioFormat(format)) {
                Napi::Error::New(env, "Failed to get audio format").ThrowAsJavaScriptException();
                return env.Null();
            }
            
            Napi::Object formatObj = Napi::Object::New(env);
            formatObj.Set("sampleRate", Napi::Number::New(env, format.mSampleRate));
            formatObj.Set("channels", Napi::Number::New(env, format.mChannelsPerFrame));
            formatObj.Set("bitsPerChannel", Napi::Number::New(env, format.mBitsPerChannel));
            formatObj.Set("formatID", Napi::Number::New(env, format.mFormatID));
            formatObj.Set("formatFlags", Napi::Number::New(env, format.mFormatFlags));
            formatObj.Set("bytesPerFrame", Napi::Number::New(env, format.mBytesPerFrame));
            formatObj.Set("framesPerPacket", Napi::Number::New(env, format.mFramesPerPacket));
            formatObj.Set("bytesPerPacket", Napi::Number::New(env, format.mBytesPerPacket));
            
            return formatObj;
        } catch (const std::exception& e) {
            Napi::Error::New(env, e.what()).ThrowAsJavaScriptException();
            return env.Null();
        }
    }

    AudioRecorder* recorder_ = nullptr;
    AggregateDevice* aggregateDevice_ = nullptr;
    AudioSystemCapture* systemCapture_ = nullptr;
};

Napi::Object Init(Napi::Env env, Napi::Object exports) {
    return RecorderWrapper::Init(env, exports);
}

NODE_API_MODULE(recorder, Init) 