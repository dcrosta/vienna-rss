//
//  ViennaPlugin.h
//  Vienna
//
//  Created by Daniel Crosta on 1/2/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "Message.h"

#import <Cocoa/Cocoa.h>


@protocol ViennaPlugin


/* initialize
 * Called by Vienna at an appropriate time to initialize anything in the
 * plugin. Preferences has already been loaded, as have all NIBs.
 */
-(void)initialize;

/* deInitialize
 * Called by Vienna before quitting so that plugins can deinitialize
 * anything as necessary.
 */
-(void)deInitialize;

@end
