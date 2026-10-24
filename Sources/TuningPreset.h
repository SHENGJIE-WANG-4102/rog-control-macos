#import <Foundation/Foundation.h>

// Local documents only. Parsing or creating a preset never contacts firmware.
NSData *ROGEncodeTuningPreset(NSDictionary *request,NSError **error);
NSDictionary *ROGDecodeTuningPreset(NSData *data,NSError **error);
