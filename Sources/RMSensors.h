#import <Foundation/Foundation.h>
// Opens a private RM client for one snapshot; releases all mappings and objects.
// No GPU initialisation, raw register reads, clock/power setters or shell commands.
NSDictionary *ROGRMSensors(void);
