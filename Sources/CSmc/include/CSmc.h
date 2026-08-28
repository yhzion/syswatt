#ifndef CSMC_H
#define CSMC_H

#include <stdint.h>
#include <string.h>

/*
 * AppleSMC IOConnectCallStructMethod(index 2)가 주고받는 펌웨어 구조체입니다.
 * 레이아웃은 커널이 기대하는 그대로여 하니까 필드 순서/정렬을 바꾸면 안 됩니다.
 * Swift에서 C 구조체를 직접 조립하면 레이아웃이 어긋날 위험이 있어서
 * 생성 코드를 여기 C 쪽에 두었습니다.
 */

typedef struct {
    uint8_t major, minor, build, reserved;
    uint16_t release;
} PWKeyDataVer;

typedef struct {
    uint16_t version, length;
    uint32_t cpuPLimit, gpuPLimit, memPLimit;
} PWPLimitData;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;      /* FourCC, 예: "flt " */
    uint8_t dataAttributes;
} PWKeyInfo;

typedef struct {
    uint32_t key;
    PWKeyDataVer vers;
    PWPLimitData pLimitData;
    PWKeyInfo keyInfo;
    uint8_t result;
    uint8_t status;
    uint8_t data8;          /* 명령 */
    uint32_t data32;
    uint8_t bytes[32];
} PWKeyData;

/* SMC 명령 */
enum {
    kPWReadBytes   = 5,     /* keyInfo로 값 바이트 읽기 */
    kPWReadKeyIdx  = 8,     /* 인덱스로 키 이름 */
    kPWReadKeyInfo = 9      /* 키 메타데이터 */
};

/* "PSTR" 같은 4문자 키를 big-endian 정수로 */
static inline uint32_t pwKey(const char *name) {
    return ((uint32_t)(uint8_t)name[0] << 24) | ((uint32_t)(uint8_t)name[1] << 16)
         | ((uint32_t)(uint8_t)name[2] << 8)  |  (uint32_t)(uint8_t)name[3];
}

/* FourCC 정수 → 문자 4글자 (단위/타입 이름 역변환용) */
static inline void pwFourCC(uint32_t value, char out[5]) {
    out[0] = (char)(value >> 24); out[1] = (char)(value >> 16);
    out[2] = (char)(value >> 8);  out[3] = (char)value;
    out[4] = 0;
}

static inline PWKeyData pwRequestReadKeyInfo(uint32_t key) {
    PWKeyData d;
    memset(&d, 0, sizeof(d));
    d.key = key;
    d.data8 = kPWReadKeyInfo;
    return d;
}

static inline PWKeyData pwRequestReadKeyByIndex(uint32_t index) {
    PWKeyData d;
    memset(&d, 0, sizeof(d));
    d.data8 = kPWReadKeyIdx;
    d.data32 = index;
    return d;
}

static inline PWKeyData pwRequestReadBytes(uint32_t key, PWKeyInfo info) {
    PWKeyData d;
    memset(&d, 0, sizeof(d));
    d.key = key;
    d.keyInfo = info;
    d.data8 = kPWReadBytes;
    return d;
}

/*읽은 바이트를 little-endian float로 (PSTR 등) */
static inline float pwFloatValue(const PWKeyData *d) {
    float f = 0.0f;
    memcpy(&f, d->bytes, 4);
    return f;
}

#endif
