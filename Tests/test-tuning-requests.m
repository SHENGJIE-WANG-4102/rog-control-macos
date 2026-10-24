#import "Bridge.h"
#include <assert.h>
int main(void){@autoreleasepool{
    NSArray *curve=@[@30,@40,@50,@60,@70,@80,@90,@100,@0,@10,@20,@30,@50,@70,@90,@100];
    NSDictionary *valid=@{@"command":@"tuningApply",@"curves":@[curve,curve,curve],@"pl1":@80,@"pl2":@100};
    assert(ROGValidRequest(valid));
    for(NSString *key in @[@"pl1",@"pl2"]){
        for(id n in @[@(-1),@0,@4,@176,@255,@(UINT32_MAX),@YES,@"80",@80.5]){NSMutableDictionary *r=[valid mutableCopy];r[key]=n;assert(!ROGValidRequest(r));}
    }
    NSMutableDictionary *r=[valid mutableCopy];r[@"pl1"]=@175;r[@"pl2"]=@175;assert(ROGValidRequest(r));r[@"pl1"]=@101;r[@"pl2"]=@100;assert(!ROGValidRequest(r));
    r=[valid mutableCopy];r[@"endpoint"]=@0x1200a3;assert(!ROGValidRequest(r));
    r=[valid mutableCopy];r[@"curves"]=@[curve,curve];assert(!ROGValidRequest(r));
    for(unsigned i=0;i<16;i++){
        for(id n in @[@YES,@(-1),@101,@1.5,@"50"]){NSMutableArray *bad=[curve mutableCopy];bad[i]=n;r=[valid mutableCopy];r[@"curves"]=@[bad,curve,curve];assert(!ROGValidRequest(r));}
    }
    NSMutableArray *bad=[curve mutableCopy];bad[1]=@30;r=[valid mutableCopy];r[@"curves"]=@[bad,curve,curve];assert(!ROGValidRequest(r));
    bad=[curve mutableCopy];bad[12]=@20;r[@"curves"]=@[bad,curve,curve];assert(!ROGValidRequest(r));
    bad=[curve mutableCopy];bad[15]=@89;r[@"curves"]=@[bad,curve,curve];assert(!ROGValidRequest(r));
    assert(ROGValidRequest(@{@"command":@"tuningRead"})&&ROGValidRequest(@{@"command":@"tuningRestore"}));
    assert(!ROGValidRequest(@{@"command":@"tuningRead",@"mode":@1}));
    assert(!ROGValidRequest(@{@"command":@"tuningRestore",@"endpoint":@1}));
    puts("PASS: tuning request shapes, byte/integer types, curve shape/order, 175W bounds and extra-key rejection");
}return 0;}
