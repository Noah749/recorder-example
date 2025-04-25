{
  "targets": [
    {
      "target_name": "recorder",
      "cflags!": [ "-fno-exceptions" ],
      "cflags_cc!": [ "-fno-exceptions" ],
      "sources": [ 
        "src/recorder.cpp",
        "src/recorder.h",
        "src/mac_recorder.cpp",
        "src/mac_recorder.h",
        "src/audio_system_capture.mm",
        "src/audio_system_capture.h",
        "src/audio_device_manager.mm",
        "src/audio_device_manager.h",
        "src/logger.cpp",
        "src/logger.h",
        "src/ring_buffer.cpp",
        "src/ring_buffer.h",
        "src/nodejs/recorder_bindings.cpp"
      ],
      "include_dirs": [
        "<!@(node -p \"require('node-addon-api').include\")",
        "<!@(node -p \"require('node-addon-api').include_dir\")",
        "<!@(node -p \"require('node-addon-api').node_root_dir\")",
        "./include",
        "./src",
        "./src/nodejs",
        "./deps/spdlog-1.12.0/include"
      ],
      "defines": [
        "NAPI_DISABLE_CPP_EXCEPTIONS",
        "SPDLOG_HEADER_ONLY"
      ],
      "conditions": [
        ["OS=='mac'", {
          "xcode_settings": {
            "GCC_ENABLE_CPP_EXCEPTIONS": "YES",
            "CLANG_CXX_LIBRARY": "libc++",
            "MACOSX_DEPLOYMENT_TARGET": "14.2",
            "OTHER_CPLUSPLUSFLAGS": [ "-std=c++17", "-stdlib=libc++" ],
            "OTHER_CFLAGS": [ "-x", "objective-c++" ]
          },
          "link_settings": {
            "libraries": [
              "-framework CoreAudio",
              "-framework AudioToolbox",
              "-framework CoreFoundation",
              "-framework AVFoundation",
              "-framework Foundation"
            ]
          }
        }]
      ],
      "dependencies": [
        "<!@(node -p \"require('node-addon-api').gyp\")"
      ],
      "cflags_cc": ["-std=c++17"],
      "xcode_settings": {
        "OTHER_CPLUSPLUSFLAGS": ["-std=c++17"],
        "CLANG_CXX_LANGUAGE_STANDARD": "c++17",
        "CLANG_CXX_LIBRARY": "libc++",
        "MACOSX_DEPLOYMENT_TARGET": "14.2"
      }
    }
  ]
} 