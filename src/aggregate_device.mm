#import "aggregate_device.h"
#import "logger.h"
#import <CoreAudio/CoreAudio.h>
#import <CoreFoundation/CoreFoundation.h>
#import <CoreAudio/AudioHardware.h>
#import <CoreAudio/AudioHardwareTapping.h>
#import <CoreAudio/CATapDescription.h>

void AggregateDevice::InitializeTaps() {
    AudioObjectPropertyAddress propertyAddress = {
        kAudioHardwarePropertyTapList,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    
    UInt32 propertySize = 0;
    OSStatus status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, NULL, &propertySize);
    
    if (status == noErr) {
        if (propertySize % sizeof(AudioObjectID) != 0) {
            Logger::error("无效的属性数据大小: %u，不是 AudioObjectID 的整数倍", propertySize);
        } else {
            int tapCount = propertySize / sizeof(AudioObjectID);
            
            if (tapCount > 0) {
                std::vector<AudioObjectID> list(tapCount);
                status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, NULL, &propertySize, list.data());
                
                if (status == noErr) {
                    for (AudioObjectID tapID : list) {
                        if (tapID == kAudioObjectUnknown) {
                            Logger::error("发现无效的 tapID (kAudioObjectUnknown)");
                            continue;
                        }
                        
                        AudioObjectPropertyAddress uidPropertyAddress = {
                            kAudioTapPropertyUID,
                            kAudioObjectPropertyScopeGlobal,
                            kAudioObjectPropertyElementMain
                        };
                        
                        UInt32 uidSize = sizeof(CFStringRef);
                        CFStringRef tapUID = NULL;
                        OSStatus uidStatus = AudioObjectGetPropertyData(tapID, &uidPropertyAddress, 0, NULL, &uidSize, &tapUID);
                        
                        if (uidStatus == noErr && tapUID) {
                            char buffer[256];
                            CFStringGetCString(tapUID, buffer, sizeof(buffer), kCFStringEncodingUTF8);
                            taps.push_back({tapID, std::string(buffer)});
                            CFRelease(tapUID);
                        } else {
                            Logger::error("获取 tapID %u 的 UID 失败，错误码: %d (0x%X)", 
                                        (unsigned int)tapID, 
                                        (int)uidStatus,
                                        (unsigned int)uidStatus);
                        }
                    }
                } else {
                    Logger::error("获取 tap 列表数据失败，错误码: %d (0x%X)", (int)status, (unsigned int)status);
                }
            }
        }
    } else {
        Logger::error("获取 tap 列表大小失败，错误码: %d (0x%X)", (int)status, (unsigned int)status);
    }
}

AggregateDevice::AggregateDevice(const std::string& deviceName) : deviceID(kAudioObjectUnknown), deviceName(deviceName) {
    CFStringRef name = CFStringCreateWithCString(kCFAllocatorDefault, deviceName.c_str(), kCFStringEncodingUTF8);
    CFUUIDRef uuid = CFUUIDCreate(kCFAllocatorDefault);
    CFStringRef uid = CFUUIDCreateString(kCFAllocatorDefault, uuid);
    
    const void *keys[] = {
        CFSTR(kAudioAggregateDeviceNameKey),
        CFSTR(kAudioAggregateDeviceUIDKey),
        CFSTR(kAudioAggregateDeviceIsPrivateKey)
    };
    
    const void *values[] = {
        name,
        uid,
        kCFBooleanTrue
    };
    
    CFDictionaryRef description = CFDictionaryCreate(
        kCFAllocatorDefault,
        keys,
        values,
        3,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks
    );
    
    if (!description) {
        Logger::error("创建设备描述字典失败");
        CFRelease(name);
        CFRelease(uid);
        CFRelease(uuid);
        return;
    }
    
    OSStatus status = AudioHardwareCreateAggregateDevice(description, &deviceID);
    
    if (status != noErr) {
        Logger::error("聚合设备创建失败，错误码: %d", (int)status);
        char errorString[5] = {0};
        *(UInt32*)errorString = CFSwapInt32HostToBig(status);
        Logger::error("错误详情: %s", errorString);
        deviceID = kAudioObjectUnknown;
    } else {
        AudioObjectID tapID = CreateTap("Plaud.ai.Tap");
        AddTap(tapID);
    }
    
    CFRelease(description);
    CFRelease(name);
    CFRelease(uid);
    CFRelease(uuid);
}

void AggregateDevice::ReleaseTaps() {
    for (const auto& tap : taps) {
        ReleaseTap(tap.tapID);
    }
    taps.clear();
}

AggregateDevice::~AggregateDevice() {
    if (deviceID != kAudioObjectUnknown) {
        ReleaseTaps();  // 先释放所有 taps
        OSStatus status = AudioHardwareDestroyAggregateDevice(deviceID);
        if (status != noErr) {
            Logger::error("删除聚合设备失败，错误码: %d", (int)status);
            char errorString[5] = {0};
            *(UInt32*)errorString = CFSwapInt32HostToBig(status);
            Logger::error("错误详情: %s", errorString);
        }
    }
}

std::vector<Tap> AggregateDevice::GetTaps() const {
    return taps;
}

bool AggregateDevice::AddTap(AudioObjectID tapID) {
    AudioObjectPropertyAddress propertyAddress = {
        kAudioTapPropertyUID,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    
    UInt32 propertySize = sizeof(CFStringRef);
    CFStringRef tapUID = NULL;
    OSStatus status = AudioObjectGetPropertyData(tapID, &propertyAddress, 0, NULL, &propertySize, &tapUID);
    
    if (status != noErr || !tapUID) {
        Logger::error("获取 tap UID 失败，错误码: %d", (int)status);
        return false;
    }
    
    propertyAddress.mSelector = kAudioAggregateDevicePropertyTapList;
    propertySize = 0;
    status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, NULL, &propertySize);
    
    if (status == noErr) {
        CFArrayRef tapList = NULL;
        status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, NULL, &propertySize, &tapList);
        
        if (status == noErr) {
            CFMutableArrayRef newTapList = CFArrayCreateMutableCopy(kCFAllocatorDefault, 0, tapList);
            if (!newTapList) {
                newTapList = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
            }
            
            CFArrayAppendValue(newTapList, tapUID);
            status = AudioObjectSetPropertyData(deviceID, &propertyAddress, 0, NULL, sizeof(CFArrayRef), &newTapList);
            
            CFRelease(newTapList);
            if (tapList) {
                CFRelease(tapList);
            }
            
            if (status == noErr) {
                CFRelease(tapUID);
                taps.push_back({tapID, GetTapName(tapID)});
                return true;
            }
        }
    }
    
    CFRelease(tapUID);
    return false;
}

bool AggregateDevice::RemoveTap(AudioObjectID tapID) {
    AudioObjectPropertyAddress propertyAddress = {
        kAudioTapPropertyUID,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    
    UInt32 propertySize = sizeof(CFStringRef);
    CFStringRef tapUID = NULL;
    OSStatus status = AudioObjectGetPropertyData(tapID, &propertyAddress, 0, NULL, &propertySize, &tapUID);
    
    if (status != noErr || !tapUID) {
        Logger::error("获取 tap UID 失败，错误码: %d", (int)status);
        return false;
    }
    
    propertyAddress.mSelector = kAudioAggregateDevicePropertyTapList;
    propertySize = 0;
    status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, NULL, &propertySize);
    
    if (status == noErr) {
        CFArrayRef tapList = NULL;
        status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, NULL, &propertySize, &tapList);
        
        if (status == noErr) {
            CFMutableArrayRef newTapList = CFArrayCreateMutableCopy(kCFAllocatorDefault, 0, tapList);
            if (!newTapList) {
                newTapList = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
            }
            
            CFIndex index = CFArrayGetFirstIndexOfValue(newTapList, CFRangeMake(0, CFArrayGetCount(newTapList)), tapUID);
            if (index != -1) {
                CFArrayRemoveValueAtIndex(newTapList, index);
                status = AudioObjectSetPropertyData(deviceID, &propertyAddress, 0, NULL, sizeof(CFArrayRef), &newTapList);
            }
            
            CFRelease(newTapList);
            if (tapList) {
                CFRelease(tapList);
            }
            
            if (status == noErr) {
                CFRelease(tapUID);
                taps.erase(std::remove_if(taps.begin(), taps.end(), [tapID](const Tap& tap) { return tap.tapID == tapID; }), taps.end());
                return true;
            }
        }
    }
    
    CFRelease(tapUID);

    return false;
}


AudioObjectID AggregateDevice::CreateTap(const std::string& tapName) {
    CATapDescription *tapDescription = [[CATapDescription alloc] initStereoGlobalTapButExcludeProcesses:@[]];
    
    tapDescription.processes = [NSMutableArray array];
    tapDescription.name = [NSString stringWithUTF8String:tapName.c_str()];
    tapDescription.muteBehavior = CATapUnmuted;
    tapDescription.privateTap = YES;
    tapDescription.exclusive = YES;
    tapDescription.mixdown = YES;
    tapDescription.mono = NO;
    
    AudioObjectID tapID = kAudioObjectUnknown;
    OSStatus status = AudioHardwareCreateProcessTap(tapDescription, &tapID);
    
    if (status != noErr) {
        Logger::error("创建音频捕获 tap 失败，错误码: %d", (int)status);
        return kAudioObjectUnknown;
    }
    
    return tapID;
}

std::string AggregateDevice::GetTapName(AudioObjectID tapID) {
    AudioObjectPropertyAddress propertyAddress = {
        kAudioObjectPropertyName,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    
    UInt32 propertySize = sizeof(CFStringRef);
    CFStringRef name = NULL;
    OSStatus status = AudioObjectGetPropertyData(tapID, &propertyAddress, 0, NULL, &propertySize, &name);
    
    if (status != noErr || !name) {
        Logger::error("获取 tap 名称失败，错误码: %d", (int)status);
        return "";
    }
    
    char buffer[256];
    CFStringGetCString(name, buffer, sizeof(buffer), kCFStringEncodingUTF8);
    CFRelease(name);
    
    return std::string(buffer);
}

bool AggregateDevice::ReleaseTap(AudioObjectID tapID) {
    // 先停止 tap
    AudioObjectPropertyAddress propertyAddress = {
        kAudioProcessPropertyIsRunning,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    
    UInt32 isRunning = 0;
    UInt32 propertySize = sizeof(isRunning);
    OSStatus status = AudioObjectGetPropertyData(tapID, &propertyAddress, 0, NULL, &propertySize, &isRunning);
    
    if (status == noErr && isRunning) {
        isRunning = 0;
        status = AudioObjectSetPropertyData(tapID, &propertyAddress, 0, NULL, propertySize, &isRunning);
        if (status != noErr) {
            Logger::error("停止 tap 失败，错误码: %d", (int)status);
            return false;
        }
    }
    
    // 从设备中移除 tap
    RemoveTap(tapID);
    
    // 销毁 tap
    status = AudioHardwareDestroyProcessTap(tapID);
    if (status != noErr) {
        Logger::error("删除 tap 失败，错误码: %d", (int)status);
        return false;
    }
    
    return true;
} 