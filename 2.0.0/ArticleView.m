//
//  ArticleView.m
//  Vienna
//
//  Created by Steve on Tue Jul 05 2005.
//  Copyright (c) 2004-2005 Steve Palmer. All rights reserved.
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

#import "ArticleView.h"

@interface NSObject(ArticleViewDelegate)
-(BOOL)handleKeyDown:(unichar)keyChar withFlags:(unsigned int)flags;
@end

@implementation ArticleView

/* setDelegate
 * Assign the delegate for this view.
 */
-(void)setDelegate:(id)newDelegate
{
	[newDelegate retain];
	[theDelegate release];
	theDelegate = newDelegate;
}

/* delegate
 * Returns the delegate for this view.
 */
-(id)delegate
{
	return theDelegate;
}

/* keyDown
 * Here is where we handle special keys when the message list view
 * has the focus so we can do custom things.
 */
-(void)keyDown:(NSEvent *)theEvent
{
	if ([[theEvent characters] length] == 1)
	{
		unichar keyChar = [[theEvent characters] characterAtIndex:0];
		if ([[self delegate] handleKeyDown:keyChar withFlags:[theEvent modifierFlags]])
			return;
	}
	[super keyDown:theEvent];
}
@end
