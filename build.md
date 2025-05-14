# build webrtc

## install Depot Tools
```bash
git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git

export PATH=/path/to/depot_tools:$PATH
```


## 拉取并同步代码

```bash
fetch --nohooks webrtc

gclient sync
```

## 编译

```bash
gn gen out/Default

autoninja -C out/Default

# autoninja all -C out/Default
```

## 编译 macos audio_processor 静态库

```bash
# args.gn

is_debug=false
use_lld=false
```

```bash
gn gen out/apm --args='is_debug=false use_lld=false'

ninja -C out/apm modules/audio_processing:audio_processing
```
