使用 AUGraph 或 AudioComponentInstance 创建每个节点

使用两个 AUHAL 单元：

一个采集麦克风

一个采集系统音频（通过虚拟音频设备）

将 mic buffer 送入 WebRTC 的 ProcessStream

将系统音频送入 ProcessReverseStream

混合最终音频后写入文件