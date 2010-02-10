//
//  SynkStringExtensions.m
//  Vienna
//
//  Created by Daniel Crosta on 2/10/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import <openssl/md5.h>

#import "SynkStringExtensions.h"

@implementation NSString (SynkStringExtensions)

/* md5HexDigest
 * compute and return the MD5 hash digest's hexadecimal representation for the string
 * code taken from http://blog.andrewpaulsimmons.com/2008/07/md5-hash-on-iphone.html
 */
-(NSString *)md5HexDigest
{
	NSData *data = [self dataUsingEncoding:NSUTF8StringEncoding];
	unsigned char buf[MD5_DIGEST_LENGTH];
	
	MD5([data bytes], [data length], buf);
	
	// TODO: probably a better way to do this
	NSString * out = [NSString stringWithFormat:@"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
					  buf[0], buf[1], buf[2], buf[3], buf[4], buf[5], buf[6], buf[7],
					  buf[8], buf[9], buf[10], buf[11], buf[12], buf[13], buf[14], buf[15]];
	return out;
}

@end
