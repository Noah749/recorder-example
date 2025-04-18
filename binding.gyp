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
        "src/nodejs/main_node.cpp",
        "src/nodejs/node_recorder.cpp"
      ],
      "include_dirs": [
        "<!@(node -p \"require('node-addon-api').include\")",
        "./deps/spdlog-1.12.0/include",
        "./src"
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
            "MACOSX_DEPLOYMENT_TARGET": "10.15",
            "OTHER_CPLUSPLUSFLAGS": [ "-std=c++17", "-stdlib=libc++" ]
          },
          "link_settings": {
            "libraries": [
              "-framework CoreAudio",
              "-framework AudioToolbox",
              "-framework AudioUnit",
              "-framework CoreFoundation",
              "-framework CoreServices"
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
      ]
    }
  ]
} 