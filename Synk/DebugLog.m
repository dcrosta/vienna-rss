//
//  DebugLog.m
//  Vienna
//
//  Created by Daniel Crosta on 2/14/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//


// prototype defined in Synk_Prefix.pch
void DebugLog(NSString * fmt, ...)
{
#ifdef DEBUG_LOGGING
	va_list args;
	va_start(args, fmt);
	NSLogv(fmt, args);
	va_end(args);
#endif
}
