//
//  ViennaPlugin.h
//  Vienna
//
//  Created by Daniel Crosta on 1/2/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@protocol ViennaPlugin

/* startup
 * Called by Vienna at an appropriate time to initialize anything in the
 * plugin. Preferences has already been loaded, as have all NIBs.
 */
-(void)startup;

/* shutdown
 * Called by Vienna before quitting so that plugins can deinitialize
 * anything as necessary.
 */
-(void)shutdown;

/* name
 * Return a human-friendly string name, which should be localized
 * if possible.
 */
-(NSString *)name;

@end
