#include "av_engine_test.h"
#include "logger.h"
#import <CoreAudio/CoreAudio.h>
#import <CoreAudio/CoreAudioTypes.h>
#import <CoreAudio/AudioHardware.h>
#import <CoreAudio/AudioHardwareTapping.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AudioUnit/AudioUnit.h>
#import <CoreAudio/CATapDescription.h>
#include <CoreFoundation/CoreFoundation.h>

void TestCoreAudioTaps() {
    @autoreleasepool {
        Logger::info("开始测试 core audio taps");

        // 创建 tap
        Logger::info("正在创建 CATapDescription 实例...");
        CATapDescription *tapDescription = [[CATapDescription alloc] initStereoGlobalTapButExcludeProcesses:@[]];

        tapDescription.processes = [NSMutableArray array];
        tapDescription.name = @"System Audio Capture";
        tapDescription.muteBehavior = CATapUnmuted;  // 同时捕获和播放音频
        tapDescription.privateTap = NO;  // 设置为公有捕获
        tapDescription.exclusive = NO;  // 不排除任何进程
        tapDescription.mixdown = YES;  // 启用混音
        tapDescription.mono = NO;  // 使用立体声

        Logger::info("CATapDescription 实例化完成，配置信息:");
        Logger::info("名称: %s", [tapDescription.name UTF8String]);
        Logger::info("进程列表: %s", [[tapDescription.processes description] UTF8String]);
        Logger::info("静音行为: %d", (int)tapDescription.muteBehavior);
        Logger::info("是否为私有捕获: %s", tapDescription.privateTap ? "是" : "否");
        Logger::info("是否独占: %s", tapDescription.exclusive ? "是" : "否");
        Logger::info("是否混音: %s", tapDescription.mixdown ? "是" : "否");
        Logger::info("是否为单声道: %s", tapDescription.mono ? "是" : "否");

        Logger::info("正在创建音频捕获 tap...");
        AudioObjectID tapID = AudioObjectID(kAudioObjectUnknown);
        OSStatus status = AudioHardwareCreateProcessTap(tapDescription, &tapID);
        
        if (status != noErr) {
            Logger::error("创建音频捕获 tap 失败，错误码: %d", (int)status);
            char errorString[5] = {0};
            *(UInt32*)errorString = CFSwapInt32HostToBig(status);
            Logger::error("错误详情: %s", errorString);
            return;
        }
        
        Logger::info("音频捕获 tap 创建成功，ID: %u", tapID);

        // 创建聚合设备
        @try {
            Logger::info("开始创建聚合设备...");
            
            CFStringRef name = CFSTR("Sample Aggregate Audio Device");
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
                return;
            }
            
            Logger::info("正在创建聚合设备...");
            AudioObjectID aggregateDeviceID = 0;
            status = AudioHardwareCreateAggregateDevice(description, &aggregateDeviceID);
            
            if (status == noErr) {
                Logger::info("聚合设备创建成功，ID: %u", aggregateDeviceID);
            } else {
                Logger::error("聚合设备创建失败，错误码: %d", (int)status);
                char errorString[5] = {0};
                *(UInt32*)errorString = CFSwapInt32HostToBig(status);
                Logger::error("错误详情: %s", errorString);
            }
            
            CFRelease(description);
            CFRelease(name);
            CFRelease(uid);
            CFRelease(uuid);
            
            Logger::info("聚合设备创建过程完成");
            
            // 获取 tap 的 UID
            Logger::info("正在获取 tap 的 UID...");
            AudioObjectPropertyAddress propertyAddress = {
                kAudioTapPropertyUID,
                kAudioObjectPropertyScopeGlobal,
                kAudioObjectPropertyElementMain
            };
            
            UInt32 propertySize = sizeof(CFStringRef);
            CFStringRef tapUID = NULL;
            status = AudioObjectGetPropertyData(tapID, &propertyAddress, 0, NULL, &propertySize, &tapUID);
            
            if (status == noErr && tapUID) {
                Logger::info("成功获取 tap UID: %s", [(__bridge NSString *)tapUID UTF8String]);
                
                // 获取当前的 tap 列表
                Logger::info("正在获取当前的 tap 列表...");
                propertyAddress.mSelector = kAudioAggregateDevicePropertyTapList;
                propertyAddress.mScope = kAudioObjectPropertyScopeGlobal;
                propertyAddress.mElement = kAudioObjectPropertyElementMain;
                
                // 获取属性大小
                propertySize = 0;
                status = AudioObjectGetPropertyDataSize(aggregateDeviceID, &propertyAddress, 0, NULL, &propertySize);
                
                if (status == noErr) {
                    CFArrayRef tapList = NULL;
                    status = AudioObjectGetPropertyData(aggregateDeviceID, &propertyAddress, 0, NULL, &propertySize, &tapList);
                    
                    if (status == noErr) {
                        Logger::info("成功获取 tap 列表");
                        // 创建新的 tap 列表
                        CFMutableArrayRef newTapList = CFArrayCreateMutableCopy(kCFAllocatorDefault, 0, tapList);
                        if (!newTapList) {
                            Logger::info("创建新的 tap 列表");
                            newTapList = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
                        }
                        
                        // 添加新的 tap
                        Logger::info("正在将 tap 添加到列表中...");
                        CFArrayAppendValue(newTapList, tapUID);
                        
                        // 设置新的 tap 列表
                        status = AudioObjectSetPropertyData(aggregateDeviceID, &propertyAddress, 0, NULL, sizeof(CFArrayRef), &newTapList);
                        
                        if (status == noErr) {
                            Logger::info("成功将 tap 添加到聚合设备");
                            
                            // 获取并打印更新后的 tap 列表
                            Logger::info("正在获取更新后的 tap 列表...");
                            propertySize = 0;
                            status = AudioObjectGetPropertyDataSize(aggregateDeviceID, &propertyAddress, 0, NULL, &propertySize);
                            
                            if (status == noErr) {
                                CFArrayRef updatedTapList = NULL;
                                status = AudioObjectGetPropertyData(aggregateDeviceID, &propertyAddress, 0, NULL, &propertySize, &updatedTapList);
                                
                                if (status == noErr) {
                                    CFIndex count = CFArrayGetCount(updatedTapList);
                                    Logger::info("当前 tap 列表包含 %d 个 tap:", (int)count);
                                    
                                    for (CFIndex i = 0; i < count; i++) {
                                        CFStringRef tapUID = (CFStringRef)CFArrayGetValueAtIndex(updatedTapList, i);
                                        Logger::info("  Tap[%d]: %s", (int)i, [(__bridge NSString *)tapUID UTF8String]);
                                    }
                                    
                                    CFRelease(updatedTapList);
                                } else {
                                    Logger::error("获取更新后的 tap 列表失败，错误码: %d", (int)status);
                                }
                            } else {
                                Logger::error("获取更新后的 tap 列表大小失败，错误码: %d", (int)status);
                            }
                        } else {
                            Logger::error("添加 tap 到聚合设备失败，错误码: %d", (int)status);
                        }
                        
                        CFRelease(newTapList);
                        if (tapList) {
                            CFRelease(tapList);
                        }
                    } else {
                        Logger::error("获取 tap 列表失败，错误码: %d", (int)status);
                    }
                } else {
                    Logger::error("获取 tap 列表大小失败，错误码: %d", (int)status);
                }
                
                CFRelease(tapUID);
            } else {
                Logger::error("获取 tap UID 失败，错误码: %d", (int)status);
            }
        } @catch (NSException *exception) {
            Logger::error("Objective-C 异常: %s", [exception.description UTF8String]);
            Logger::error("异常名称: %s", [exception.name UTF8String]);
            Logger::error("异常原因: %s", [exception.reason UTF8String]);
            Logger::error("异常调用栈: %s", [[exception.callStackSymbols description] UTF8String]);
        } @catch (...) {
            Logger::error("未知异常发生");
        }

        Logger::info("测试完成");
    }
} 