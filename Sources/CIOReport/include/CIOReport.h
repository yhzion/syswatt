#ifndef CIOPENREPORT_H
#define CIOPENREPORT_H

#include <CoreFoundation/CoreFoundation.h>

/*
 * IOReport는 /usr/lib/libIOReport.dylib에 있는 비공개 C API입니다.
 * SDK 헤더가 없아서 선언을 직접 맞춥니다. 시그니처는 dyld가 실제로 export하는
 * 심볼(`dyld_info -exports /usr/lib/libIOReport.dylib`)과 동일해야 합니다.
 *
 * 사용 모델은 콜백 없는 pull입니다:
 *   CopyAllChannels → 구독할 채널 고르기 → CreateSubscription
 *   → CreateSamples(현재) → CreateSamplesDelta(이전, 현재) → 값 읽기
 * 에너지 채널은 누적값(mJ/uJ/nJ)으로 오므로 경과시간으로 나눠 W를 얻습니다.
 */

__BEGIN_DECLS

CFDictionaryRef IOReportCopyAllChannels(uint64_t a, uint64_t b);

/*
 * 구독 핸들과 샘플 사전은 CFTypeRef 처 보이지만 CF 객체가 아닙니다(IOReportSubscription*
 * 전방 선언만 있는 불투명 포인터). Swift 가 ARC 로 retain/release 하면 깨지므로
 * 반드시 const void * 로 받아 손으로 관리합니다.
 */
const void *IOReportCreateSubscription(void *unused,
                                       CFMutableDictionaryRef channels,
                                       CFMutableDictionaryRef *outSamples,
                                       uint64_t state,
                                       const void *descriptor);

CFDictionaryRef IOReportCreateSamples(const void *subscription,
                                      CFMutableDictionaryRef channels,
                                      const void *descriptor);

CFDictionaryRef IOReportCreateSamplesDelta(CFDictionaryRef previous,
                                           CFDictionaryRef current,
                                           const void *descriptor);

CFStringRef IOReportChannelGetGroup(CFDictionaryRef channel);
CFStringRef IOReportChannelGetSubGroup(CFDictionaryRef channel);
CFStringRef IOReportChannelGetChannelName(CFDictionaryRef channel);
CFStringRef IOReportChannelGetUnitLabel(CFDictionaryRef channel);
int64_t IOReportSimpleGetIntegerValue(CFDictionaryRef channel, int32_t index);

__END_DECLS

#endif
