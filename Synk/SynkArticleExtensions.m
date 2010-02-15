//
//  SynkArticleExtensions.m
//  Vienna
//
//  Created by Daniel Crosta on 2/11/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "SynkArticleExtensions.h"

#import "SynkStringExtensions.h"

@implementation Article (SynkArticleExtensions)

/* synkId
 * The Synk ID for an article is the MD5 hex digest of the Article's URL.
 * The NSString returned is autoreleased.
 */
- (NSString *)synkId
{
	return [[self link] stringByCalculatingMD5HexDigest];
}

@end
