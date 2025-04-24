{
  "targets": [
    {
      "target_name": "meeting_recorder",
      "cflags!": [ "-fno-exceptions" ],
      "cflags_cc!": [ "-fno-exceptions" ],
      "sources": [ 
        "src/recorder.cpp",
        "src/logger.cpp",
        "src/mac_recorder.cpp",
        "src/mic_recorder.mm",
        "src/mic_recorder_main.mm",
        "src/system_capture_recorder_main.mm",
        "src/nodejs/recorder_bindings.cpp"
      ],
      "include_dirs": [
        "<!@(node -p \"require('node-addon-api').include\")",
        "<!@(node -p \"require('node-addon-api').include_dir\")",
        "<!@(node -p \"require('node-addon-api').node_root_dir\")",
        "./deps/spdlog-1.12.0/include",
        "./src",
        "./src/nodejs"
      ],
      "defines": [
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
              "-framework AudioUnit",
              "-framework CoreFoundation",
              "-framework CoreServices",
              "-framework AVFoundation",
              "-framework Foundation"
            ]
          }
        }],
        ["OS=='win'", {
          "libraries": [
            "-lwinmm.lib",
            "-lole32.lib"
          ],
          "msvs_settings": {
            "VCCLCompilerTool": {
              "ExceptionHandling": 1
            }
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