/*
 * NVIDIA RM ABI subset, derived from open-gpu-kernel-modules 610.57.04:
 * src/common/sdk/nvidia/inc/{nvos.h,class/cl00de.h}.
 * SPDX-FileCopyrightText: Copyright (c) 2022-2026 NVIDIA CORPORATION & AFFILIATES.
 * SPDX-License-Identifier: MIT
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
 * THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */
#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <string.h>

typedef struct { uint32_t root,parent,object,cls; uint64_t params; uint32_t size,status; } ROGRMAlloc;
typedef struct { uint32_t client,object,cmd,flags; uint64_t params; uint32_t size,status; } ROGRMControl;
typedef struct { uint32_t root,parent,object,status; } ROGRMFree;
typedef struct { uint32_t client,pid; char name[100]; uint64_t osPid; } ROGRMRootParams;
typedef struct { uint32_t gpuId,flags,device,subdevice,sli,board,instance; int32_t numa; } ROGRMIdInfo;
typedef struct { uint32_t device,share,targetClient,targetDevice,flags; uint64_t vaSize,vaStart,vaLimit; uint32_t vaMode; } ROGRMDeviceParams;
typedef struct { uint32_t client,device,memory; uint64_t offset,length,address; uint32_t status,flags; int32_t fd; } ROGRMMap;

typedef struct { uint64_t timestamp,total,free; } ROGRMVRAM;
typedef struct { uint32_t targetMHz,actualKHz; } ROGRMClock;
typedef struct { uint64_t timestamp; ROGRMClock domains[4]; } ROGRMClocks;
typedef struct { uint64_t timestamp; int32_t fixedCelsius; } ROGRMTemperature;
typedef struct { uint64_t timestamp; uint32_t gpuMW,moduleMW,otherMW; } ROGRMPower;
typedef struct { uint32_t busy,periodUS; } ROGRMEngineUtil;
typedef struct { uint64_t timestamp; uint32_t gpuBusy,memoryBusy; ROGRMEngineUtil engines[4]; } ROGRMUtil;
typedef struct { uint64_t timestamp; uint32_t mask; } ROGRMPState;

// Offsets verified by compiling the complete upstream 610.57.04 NV00DE_SHARED_DATA.
// Opaque gaps are unused ABI sections, not registers or physical memory addresses.
enum { ROGRUSDSize=3152, ROGRUSDMemory=16, ROGRUSDClocks=72,
       ROGRUSDUtil=1992, ROGRUSDPState=2280, ROGRUSDTemperature=2312,
       ROGRUSDMemoryTemperature=2328, ROGRUSDAveragePower=2440, ROGRUSDInstantPower=2464 };
#define ROGRUSDSequenceStart UINT64_C(0xff00000000000000)
_Static_assert(sizeof(ROGRMAlloc)==32 && sizeof(ROGRMControl)==32 && sizeof(ROGRMFree)==16,"RM command ABI");
_Static_assert(sizeof(ROGRMRootParams)==120 && sizeof(ROGRMDeviceParams)==56 && sizeof(ROGRMIdInfo)==32 && sizeof(ROGRMMap)==56,"RM allocation ABI");
_Static_assert(sizeof(ROGRMVRAM)==24 && sizeof(ROGRMClocks)==40 && sizeof(ROGRMTemperature)==16 && sizeof(ROGRMPower)==24 && sizeof(ROGRMUtil)==48 && sizeof(ROGRMPState)==16,"RUSD field ABI");

static inline bool ROGRMValidSequence(uint64_t t) {
    return t && (t<ROGRUSDSequenceStart || !(t&1));
}
typedef struct { uint64_t timestamp,lastAdvanceNS,lastObservationNS; bool confirmed; } ROGRMProgress;
// RM's timestamp clock can differ from NSDate/CLOCK_REALTIME after clock slew.
// Require observed advancement, then expire frozen values using a local monotonic
// clock. After a long idle gap or a backwards RM timestamp, confirm again.
static inline bool ROGRMObserve(ROGRMProgress *p,uint64_t t,uint64_t now) {
    if(!t||t>=ROGRUSDSequenceStart){memset(p,0,sizeof *p);return false;}
    if(!p->timestamp||t<p->timestamp||now<p->lastObservationNS||now-p->lastObservationNS>UINT64_C(3000000000)) {
        *p=(ROGRMProgress){t,now,now,false};return false;
    }
    p->lastObservationNS=now;
    if(t>p->timestamp){p->timestamp=t;p->lastAdvanceNS=now;p->confirmed=true;}
    return p->confirmed&&now>=p->lastAdvanceNS&&now-p->lastAdvanceNS<=UINT64_C(3000000000);
}
static inline bool ROGRMReadSection(const volatile void *base,size_t length,size_t offset,void *out,size_t size) {
    memset(out,0,size);
    if(size<8 || (offset&7) || offset>length || size>length-offset)return false;
    const volatile uint8_t *src=(const volatile uint8_t*)base+offset;
    const volatile uint64_t *seq=(const volatile uint64_t*)src;
    for(unsigned attempt=0;attempt<10;attempt++) {
        uint64_t before=__atomic_load_n(seq,__ATOMIC_ACQUIRE);
        if(!ROGRMValidSequence(before))continue;
        for(size_t i=0;i<size;i++)((uint8_t*)out)[i]=src[i];
        __atomic_thread_fence(__ATOMIC_ACQUIRE);
        uint64_t copied=0;memcpy(&copied,out,8);
        if(before==__atomic_load_n(seq,__ATOMIC_ACQUIRE) && before==copied)return true;
    }
    memset(out,0,size);return false;
}
