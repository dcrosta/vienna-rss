//
//  PluginPreferences.m
//  Vienna
//
//  Created by Daniel Crosta on 2/17/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "PluginPreferences.h"

#import "PluginHelper.h"

@implementation PluginPreferences

/* init
 * Initialize the class
 */
-(id)init
{
	if ((self = [super initWithWindowNibName:@"PluginPreferences"]) != nil)
	{
		plugins = [[[PluginHelper helper] plugins] retain];
	}
	return self;
}

-(void)awakeFromNib
{
	if ([plugins count] > 0)
	{	
		[self showContentViewForPlugin:[plugins objectAtIndex:0]];
	}	
}

-(void)dealloc
{
	[plugins release];
	[super dealloc];
}

-(void)showContentViewForPlugin:(id<ViennaPlugin>)plugin
{
	NSView * subview = [plugin preferencePaneView];
	if (subview != nil)
	{
		[subview setFrame:[subpane bounds]];
		[subpane setSubviews:[NSArray arrayWithObject:subview]];
	}
}

#pragma mark -
#pragma mark TableViewDelegate

-(void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
	NSLog(@"tableView selectionDidChange");
	NSLog(@"tableView selection: %d", [pluginList selectedRow]);
}


@end
