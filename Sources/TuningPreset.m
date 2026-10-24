#import "TuningPreset.h"
#import "Bridge.h"

static id invalid(NSError **error,NSString *message) {
    if(error)*error=[NSError errorWithDomain:@"com.macdriver.ROGControl.Preset" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
    return nil;
}
NSData *ROGEncodeTuningPreset(NSDictionary *request,NSError **error) {
    if(!ROGValidRequest(request)||![request[@"command"] isEqual:@"tuningApply"])
        return invalid(error,@"方案包含无效的风扇曲线或功耗目标。");
    NSDictionary *document=@{@"format":@"rog-control-tuning",@"version":@1,@"model":@"G815LW",@"curves":request[@"curves"],@"pl1":request[@"pl1"],@"pl2":request[@"pl2"]};
    return [NSJSONSerialization dataWithJSONObject:document options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:error];
}
NSDictionary *ROGDecodeTuningPreset(NSData *data,NSError **error) {
    if(!data.length||data.length>4096)return invalid(error,@"方案文件为空或超过 4 KB。");
    id value=[NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if(!value)return nil;
    if(![value isKindOfClass:NSDictionary.class])return invalid(error,@"方案文件须为 JSON 对象。");
    NSDictionary *d=value;id version=d[@"version"];
    if(d.count!=6||![d[@"format"] isEqual:@"rog-control-tuning"]||![version isKindOfClass:NSNumber.class]||
       CFGetTypeID((__bridge CFTypeRef)version)==CFBooleanGetTypeID()||[version doubleValue]!=1||![d[@"model"] isEqual:@"G815LW"])
        return invalid(error,@"不支持此方案格式、版本或机型；当前仅接受 G815LW 方案。");
    if(!d[@"curves"]||!d[@"pl1"]||!d[@"pl2"])return invalid(error,@"方案缺少曲线或功耗目标。");
    NSDictionary *request=@{@"command":@"tuningApply",@"curves":d[@"curves"],@"pl1":d[@"pl1"],@"pl2":d[@"pl2"]};
    if(!ROGValidRequest(request))return invalid(error,@"方案须包含三个有效八点曲线及 5 ≤ PL1 ≤ PL2 ≤ 175W 的目标。");
    return request;
}
