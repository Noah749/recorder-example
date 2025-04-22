#include "audio_device_manager.h"
#include "logger.h"
#import <CoreAudio/CoreAudio.h>
#import <CoreAudio/CoreAudioTypes.h>
#import <CoreAudio/AudioHardware.h>
#import <CoreAudio/AudioHardwareTapping.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AudioUnit/AudioUnit.h>
#import <CoreAudio/CATapDescription.h>
#include <CoreFoundation/CoreFoundation.h>

std::vector<AudioObjectID> AudioDeviceManager::GetAggregateDevices() {
    std::vector<AudioObjectID> aggregateDevices;
    
    AudioObjectPropertyAddress deviceListAddress = {
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    
    UInt32 propertySize = 0;
    AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &deviceListAddress, 0, NULL, &propertySize);
    
    int deviceCount = propertySize / sizeof(AudioObjectID);
    std::vector<AudioObjectID> list(deviceCount);
    AudioObjectGetPropertyData(kAudioObjectSystemObject, &deviceListAddress, 0, NULL, &propertySize, list.data());
    
    for (AudioObjectID id : list) {
        AudioObjectPropertyAddress propertyAddress = {
            kAudioDevicePropertyTransportType,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain
        };
        UInt32 transportType = 0;
        UInt32 transportTypeSize = sizeof(transportType);
        
        AudioObjectGetPropertyData(id, &propertyAddress, 0, NULL, &transportTypeSize, &transportType);
        
        if (transportType == kAudioDeviceTransportTypeAggregate) {
            aggregateDevices.push_back(id);
        }
    }
    
    return aggregateDevices;
}

AudioObjectID AudioDeviceManager::CreateAggregateDevice(const char* deviceName) {
    Logger::info("开始创建聚合设备...");
    
    CFStringRef name = CFStringCreateWithCString(kCFAllocatorDefault, deviceName, kCFStringEncodingUTF8);
    CFUUIDRef uuid = CFUUIDCreate(kCFAllocatorDefault);
    CFStringRef uid = CFUUIDCreateString(kCFAllocatorDefault, uuid);
    
    Logger::info("设备名称: %s", [(__bridge NSString *)name UTF8String]);
    Logger::info("设备 UID: %s", [(__bridge NSString *)uid UTF8String]);
    
    const void *keys[] = {
        CFSTR(kAudioAggregateDeviceNameKey),
        CFSTR(kAudioAggregateDeviceUIDKey)
    };
    
    const void *values[] = {
        name,
        uid
    };
    
    CFDictionaryRef description = CFDictionaryCreate(
        kCFAllocatorDefault,
        keys,
        values,
        2,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks
    );
    
    if (!description) {
        Logger::error("创建设备描述字典失败");
        CFRelease(name);
        CFRelease(uid);
        CFRelease(uuid);
        return kAudioObjectUnknown;
    }
    
    Logger::info("正在创建聚合设备...");
    AudioObjectID aggregateDeviceID = 0;
    OSStatus status = AudioHardwareCreateAggregateDevice(description, &aggregateDeviceID);
    
    if (status == noErr) {
        Logger::info("聚合设备创建成功，ID: %u", aggregateDeviceID);
    } else {
        Logger::error("聚合设备创建失败，错误码: %d", (int)status);
        char errorString[5] = {0};
        *(UInt32*)errorString = CFSwapInt32HostToBig(status);
        Logger::error("错误详情: %s", errorString);
        aggregateDeviceID = kAudioObjectUnknown;
    }
    
    CFRelease(description);
    CFRelease(name);
    CFRelease(uid);
    CFRelease(uuid);
    
    Logger::info("聚合设备创建过程完成");
    return aggregateDeviceID;
}

bool AudioDeviceManager::RemoveAggregateDevice(AudioObjectID deviceID) {
    OSStatus status = AudioHardwareDestroyAggregateDevice(deviceID);
    if (status == noErr) {
        Logger::info("成功删除聚合设备 ID: %u", (unsigned int)deviceID);
        return true;
    } else {
        Logger::error("删除聚合设备失败，错误码: %d", (int)status);
        return false;
    }
}

AudioObjectID AudioDeviceManager::CreateTap(NSString *name) {
    Logger::info("正在创建 CATapDescription 实例...");
    CATapDescription *tapDescription = [[CATapDescription alloc] initStereoGlobalTapButExcludeProcesses:@[]];

    tapDescription.processes = [NSMutableArray array];
    tapDescription.name = name;
    tapDescription.muteBehavior = CATapUnmuted;
    tapDescription.privateTap = NO;
    tapDescription.exclusive = YES;
    tapDescription.mixdown = YES;
    tapDescription.mono = NO;

    Logger::info("正在创建音频捕获 tap...");
    AudioObjectID tapID = AudioObjectID(kAudioObjectUnknown);
    OSStatus status = AudioHardwareCreateProcessTap(tapDescription, &tapID);
    
    if (status != noErr) {
        Logger::error("创建音频捕获 tap 失败，错误码: %d", (int)status);
        return kAudioObjectUnknown;
    }
    
    Logger::info("音频捕获 tap 创建成功，ID: %u", tapID);
    return tapID;
}

bool AudioDeviceManager::RemoveTap(AudioObjectID tapID) {
    OSStatus status = AudioHardwareDestroyProcessTap(tapID);
    if (status == noErr) {
        Logger::info("成功删除 tap ID: %u", (unsigned int)tapID);
        return true;
    } else {
        Logger::error("删除 tap 失败，错误码: %d", (int)status);
        return false;
    }
}

bool AudioDeviceManager::AddTapToDevice(AudioObjectID tapID, AudioObjectID deviceID) {
    OSStatus status;
    
    // 获取 tap 的 UID
    AudioObjectPropertyAddress propertyAddress = {
        kAudioTapPropertyUID,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    
    UInt32 propertySize = sizeof(CFStringRef);
    CFStringRef tapUID = NULL;
    status = AudioObjectGetPropertyData(tapID, &propertyAddress, 0, NULL, &propertySize, &tapUID);
    
    if (status != noErr || !tapUID) {
        Logger::error("获取 tap UID 失败，错误码: %d", (int)status);
        return false;
    }
    
    // 获取当前的 tap 列表
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
                Logger::info("成功将 tap 添加到聚合设备");
                CFRelease(tapUID);
                return true;
            }
        }
    }
    
    CFRelease(tapUID);
    return false;
}

bool AudioDeviceManager::RemoveTapFromDevice(AudioObjectID tapID, AudioObjectID deviceID) {
    OSStatus status;
    
    // 获取 tap 的 UID
    AudioObjectPropertyAddress propertyAddress = {
        kAudioTapPropertyUID,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    
    UInt32 propertySize = sizeof(CFStringRef);
    CFStringRef tapUID = NULL;
    status = AudioObjectGetPropertyData(tapID, &propertyAddress, 0, NULL, &propertySize, &tapUID);
    
    if (status != noErr || !tapUID) {
        Logger::error("获取 tap UID 失败，错误码: %d", (int)status);
        return false;
    }
    
    // 获取当前的 tap 列表
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
            
            // 查找并移除指定的 tap
            CFIndex count = CFArrayGetCount(newTapList);
            for (CFIndex i = 0; i < count; i++) {
                CFStringRef currentUID = (CFStringRef)CFArrayGetValueAtIndex(newTapList, i);
                if (CFStringCompare(currentUID, tapUID, 0) == kCFCompareEqualTo) {
                    CFArrayRemoveValueAtIndex(newTapList, i);
                    break;
                }
            }
            
            status = AudioObjectSetPropertyData(deviceID, &propertyAddress, 0, NULL, sizeof(CFArrayRef), &newTapList);
            
            CFRelease(newTapList);
            if (tapList) {
                CFRelease(tapList);
            }
            
            if (status == noErr) {
                Logger::info("成功从聚合设备移除 tap");
                CFRelease(tapUID);
                return true;
            }
        }
    }
    
    CFRelease(tapUID);
    return false;
}

std::vector<AudioObjectID> AudioDeviceManager::GetDeviceTaps(AudioObjectID deviceID) {
    std::vector<AudioObjectID> taps;
    
    Logger::info("开始获取设备 %u 的 tap 列表", (unsigned int)deviceID);
    
    AudioObjectPropertyAddress propertyAddress = {
        kAudioHardwarePropertyTapList,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    
    UInt32 propertySize = 0;
    OSStatus status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, NULL, &propertySize);
    Logger::info("获取到的属性数据大小: %u", propertySize);
    
    if (status == noErr) {
        // 验证数据大小是否合理
        if (propertySize % sizeof(AudioObjectID) != 0) {
            Logger::error("无效的属性数据大小: %u，不是 AudioObjectID 的整数倍", propertySize);
            return taps;
        }
        
        int tapCount = propertySize / sizeof(AudioObjectID);
        Logger::info("预计 tap 数量: %d", tapCount);
        
        if (tapCount == 0) {
            Logger::info("设备上没有 tap");
            return taps;
        }
        
        std::vector<AudioObjectID> list(tapCount);
        status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, NULL, &propertySize, list.data());
        
        if (status == noErr) {
            for (AudioObjectID tapID : list) {
                if (tapID == kAudioObjectUnknown) {
                    Logger::error("发现无效的 tapID (kAudioObjectUnknown)");
                    continue;
                }
                
                // 获取 tap 的 UID 进行验证
                AudioObjectPropertyAddress uidPropertyAddress = {
                    kAudioTapPropertyUID,
                    kAudioObjectPropertyScopeGlobal,
                    kAudioObjectPropertyElementMain
                };
                
                UInt32 uidSize = sizeof(CFStringRef);
                CFStringRef tapUID = NULL;
                OSStatus uidStatus = AudioObjectGetPropertyData(tapID, &uidPropertyAddress, 0, NULL, &uidSize, &tapUID);
                
                if (uidStatus == noErr && tapUID) {
                    Logger::info("tapID: %u, UID: %s", 
                               (unsigned int)tapID,
                               [(__bridge NSString *)tapUID UTF8String]);
                    CFRelease(tapUID);
                    taps.push_back(tapID);
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
    } else {
        Logger::error("获取 tap 列表大小失败，错误码: %d (0x%X)", (int)status, (unsigned int)status);
    }
    
    return taps;
}

std::vector<AudioObjectID> AudioDeviceManager::GetAggregateDevicesByName(const std::string& deviceName) {
    std::vector<AudioObjectID> filteredDevices;
    
    // 获取所有聚合设备
    auto allDevices = GetAggregateDevices();
    
    // 将设备名称转换为 CFStringRef
    CFStringRef targetName = CFStringCreateWithCString(kCFAllocatorDefault, deviceName.c_str(), kCFStringEncodingUTF8);
    
    for (AudioObjectID deviceID : allDevices) {
        // 获取设备名称
        AudioObjectPropertyAddress propertyAddress = {
            kAudioObjectPropertyName,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain
        };
        
        CFStringRef deviceNameRef = NULL;
        UInt32 propertySize = sizeof(CFStringRef);
        OSStatus status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, NULL, &propertySize, &deviceNameRef);
        
        if (status == noErr && deviceNameRef) {
            // 比较设备名称
            if (CFStringCompare(deviceNameRef, targetName, 0) == kCFCompareEqualTo) {
                filteredDevices.push_back(deviceID);
                Logger::info("找到匹配的设备: ID = %u, 名称 = %s", 
                           (unsigned int)deviceID, 
                           [(__bridge NSString *)deviceNameRef UTF8String]);
            }
            CFRelease(deviceNameRef);
        }
    }
    
    CFRelease(targetName);
    return filteredDevices;
} 