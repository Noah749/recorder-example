#include <napi.h>
#include "node_recorder.h"
#include "logger.h"

Napi::Object InitAll(Napi::Env env, Napi::Object exports) {
    // 初始化日志系统
    Logger::init();
    Logger::setLevel(Logger::Level::DEBUG);
    Logger::info("初始化 meeting_recorder 模块");
    return RecorderWrapper::Init(env, exports);
}

NODE_API_MODULE(meeting_recorder, InitAll);