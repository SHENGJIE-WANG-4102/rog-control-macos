#pragma once
#include <stdint.h>

// A new model/BIOS entry requires an AML and endpoint audit. Series membership
// alone is not sufficient to authorize firmware writes.
struct ROGModelProfile {
    const char *model;
    uint32_t dsdtLength;
    uint64_t dsdtFNV1a;
    const char *ecRegistryPath;
};
static constexpr ROGModelProfile ROGProfiles[]={
    {"G815LW",567571,0x9f2ea51319b741f9ULL,
     "IOACPIPlane:/_SB/PC00@0/LPCB@1f0000/EC0"},
};
