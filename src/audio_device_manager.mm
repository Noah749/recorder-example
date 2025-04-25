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
    CFStringRef name = CFStringCreateWithCString(kCFAllocatorDefault, deviceName, kCFStringEncodingUTF8);
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
        return kAudioObjectUnknown;
    }
    
    AudioObjectID aggregateDeviceID = 0;
    OSStatus status = AudioHardwareCreateAggregateDevice(description, &aggregateDeviceID);
    
    if (status == noErr) {
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
    
    return aggregateDeviceID;
}

bool AudioDeviceManager::RemoveAggregateDevice(AudioObjectID deviceID) {
    OSStatus status = AudioHardwareDestroyAggregateDevice(deviceID);
    if (status == noErr) {
        return true;
    } else {
        Logger::error("删除聚合设备失败，错误码: %d", (int)status);
        return false;
    }
}

AudioObjectID AudioDeviceManager::CreateTap(const char* name) {
    CATapDescription *tapDescription = [[CATapDescription alloc] initStereoGlobalTapButExcludeProcesses:@[]];

    tapDescription.processes = [NSMutableArray array];
    tapDescription.name = [NSString stringWithUTF8String:name];
    tapDescription.muteBehavior = CATapUnmuted;
    tapDescription.privateTap = YES;
    tapDescription.exclusive = YES;
    tapDescription.mixdown = YES;
    tapDescription.mono = NO;

    AudioObjectID tapID = AudioObjectID(kAudioObjectUnknown);
    OSStatus status = AudioHardwareCreateProcessTap(tapDescription, &tapID);
    
    if (status != noErr) {
        Logger::error("创建音频捕获 tap 失败，错误码: %d", (int)status);
        return kAudioObjectUnknown;
    }
    
    return tapID;
}

bool AudioDeviceManager::RemoveTap(AudioObjectID tapID) {
    OSStatus status = AudioHardwareDestroyProcessTap(tapID);
    if (status == noErr) {
        return true;
    } else {
        Logger::error("删除 tap 失败，错误码: %d", (int)status);
        return false;
    }
}

bool AudioDeviceManager::AddTapToDevice(AudioObjectID tapID, AudioObjectID deviceID) {
    OSStatus status;
    
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
                return true;
            }
        }
    }
    
    CFRelease(tapUID);
    return false;
}

bool AudioDeviceManager::RemoveTapFromDevice(AudioObjectID tapID, AudioObjectID deviceID) {
    OSStatus status;
    
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
            return taps;
        }
        
        int tapCount = propertySize / sizeof(AudioObjectID);
        
        if (tapCount == 0) {
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
                
                AudioObjectPropertyAddress uidPropertyAddress = {
                    kAudioTapPropertyUID,
                    kAudioObjectPropertyScopeGlobal,
                    kAudioObjectPropertyElementMain
                };
                
                UInt32 uidSize = sizeof(CFStringRef);
                CFStringRef tapUID = NULL;
                OSStatus uidStatus = AudioObjectGetPropertyData(tapID, &uidPropertyAddress, 0, NULL, &uidSize, &tapUID);
                
                if (uidStatus == noErr && tapUID) {
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
    
    auto allDevices = GetAggregateDevices();
    
    CFStringRef targetName = CFStringCreateWithCString(kCFAllocatorDefault, deviceName.c_str(), kCFStringEncodingUTF8);
    
    for (AudioObjectID deviceID : allDevices) {
        AudioObjectPropertyAddress propertyAddress = {
            kAudioObjectPropertyName,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain
        };
        
        CFStringRef deviceNameRef = NULL;
        UInt32 propertySize = sizeof(CFStringRef);
        OSStatus status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, NULL, &propertySize, &deviceNameRef);
        
        if (status == noErr && deviceNameRef) {
            if (CFStringCompare(deviceNameRef, targetName, 0) == kCFCompareEqualTo) {
                filteredDevices.push_back(deviceID);
            }
            CFRelease(deviceNameRef);
        }
    }
    
    CFRelease(targetName);
    return filteredDevices;
} 