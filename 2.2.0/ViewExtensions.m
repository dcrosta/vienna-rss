//
//  ViewExtensions.m
//  Vienna
//
//  Created by Steve Palmer on 27/05/2007.
//  Copyright (c) 2004-2007 Steve Palmer. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "ViewExtensions.h"

@interface NSObject (ObjectWithTags)
-(void)MA_setTag:(int)newTag;
-(int)MA_tag;
@end

@implementation NSObject (ObjectWithTags)

/* MA_tagDict
 * A dictionary used to simulate instance variables for our category
 */
- (NSMutableDictionary *)MA_tagDict
{
	static NSMutableDictionary *tagDict = nil;
	NSMutableDictionary *returnDict = nil;
	// The tagDict will only be used once.
	if (tagDict)
	{
		returnDict = [tagDict autorelease];
		tagDict = nil;
	}
	else
	{
		tagDict = [[NSMutableDictionary alloc] init];
		returnDict = tagDict;
	}
	return returnDict;
}

/* MA_setTag
 * Assigns the specified tag value to the animation object.
 */
-(void)MA_setTag:(int)newTag
{
	[[self MA_tagDict] setObject:[NSNumber numberWithInt:newTag]
					   forKey:[NSValue valueWithPointer:self]];
}

/* MA_tag
 * Returns the associated tag.
 */
-(int)MA_tag
{
	return [[[self MA_tagDict] objectForKey:[NSValue valueWithPointer:self]] intValue];
}
@end

@implementation NSView (ViewExtensions)

/* resizeViewWithAnimation
 * On Mac OSX 10.4 or later, resizes the specified view with animation. On earlier versions, just resizes the view.
 */
-(void)resizeViewWithAnimation:(NSRect)newFrame withTag:(int)viewTag
{
	Class viewAnimationClass = NSClassFromString(@"NSViewAnimation");
	if (viewAnimationClass) {
		NSDictionary * dict = [NSDictionary dictionaryWithObjectsAndKeys:
			[NSValue valueWithRect:newFrame], NSViewAnimationEndFrameKey,
			self, NSViewAnimationTargetKey,
			nil];

		id animation = [[viewAnimationClass alloc] initWithViewAnimations:[NSArray arrayWithObject:dict]];
		[animation setAnimationBlockingMode:NSAnimationNonblocking];
		[animation setDuration:0.1];
		[animation setAnimationCurve:NSAnimationEaseInOut];
		[animation setDelegate:self];
		[animation MA_setTag:viewTag];
		[animation startAnimation];

	} else {
		[self setFrame:newFrame];

		//Inform the delegate immediately since we're not animating
		if ([[[self window] delegate] respondsToSelector:@selector(viewAnimationCompleted:withTag:)])
			[[[self window] delegate] viewAnimationCompleted:self withTag:viewTag];
	}
}

/* animationDidEnd
 * Delegate function called when animation completes. (Mac OSX 10.4 or later only).
 */
-(void)animationDidEnd:(id)animation
{
	NSWindow * viewWindow = [self window];
	int viewTag = [animation MA_tag];

	[animation release];
	if ([[viewWindow delegate] respondsToSelector:@selector(viewAnimationCompleted:withTag:)])
		[[viewWindow delegate] viewAnimationCompleted:self withTag:viewTag];
}

@end
