//
//  RichXMLParser.m
//  Vienna
//
//  Created by Steve on 5/22/05.
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

#import "RichXMLParser.h"
#import <CoreFoundation/CoreFoundation.h>
#import "StringExtensions.h"

@interface FeedItem (Private)
	-(void)setTitle:(NSString *)newTitle;
	-(void)setDescription:(NSString *)newDescription;
	-(void)setAuthor:(NSString *)newAuthor;
	-(void)setDate:(NSDate *)newDate;
	-(void)setGuid:(NSString *)newGuid;
	-(void)setLink:(NSString *)newLink;
@end

@interface RichXMLParser (Private)
	-(void)reset;
	-(BOOL)initRSSFeed:(XMLParser *)feedTree isRDF:(BOOL)isRDF;
	-(XMLParser *)channelTree:(XMLParser *)feedTree;
	-(BOOL)initRSSFeedHeader:(XMLParser *)feedTree;
	-(BOOL)initRSSFeedItems:(XMLParser *)feedTree;
	-(BOOL)initAtomFeed:(XMLParser *)feedTree;
	-(void)setTitle:(NSString *)newTitle;
	-(void)setLink:(NSString *)newLink;
	-(void)setDescription:(NSString *)newDescription;
	-(void)setLastModified:(NSDate *)newDate;
	-(void)ensureTitle:(FeedItem *)item;
	-(NSString *)guidFromItem:(FeedItem *)item;
@end

@implementation FeedItem

/* init
 * Creates a FeedItem instance
 */
-(id)init
{
	if ((self = [super init]) != nil)
	{
		[self setTitle:@""];
		[self setDescription:@""];
		[self setAuthor:@""];
		[self setGuid:@""];
		[self setDate:nil];
		[self setLink:@""];
	}
	return self;
}

/* setTitle
 * Set the item title.
 */
-(void)setTitle:(NSString *)newTitle
{
	[newTitle retain];
	[title release];
	title = newTitle;
}

/* setDescription
 * Set the item description.
 */
-(void)setDescription:(NSString *)newDescription
{
	[newDescription retain];
	[description release];
	description = newDescription;
}

/* setAuthor
 * Set the item author.
 */
-(void)setAuthor:(NSString *)newAuthor
{
	[newAuthor retain];
	[author release];
	author = newAuthor;
}

/* setDate
 * Set the item date
 */
-(void)setDate:(NSDate *)newDate
{
	[newDate retain];
	[date release];
	date = newDate;
}

/* setGuid
 * Set the item GUID.
 */
-(void)setGuid:(NSString *)newGuid
{
	[newGuid retain];
	[guid release];
	guid = newGuid;
}

/* setLink
 * Set the item link.
 */
-(void)setLink:(NSString *)newLink
{
	[newLink retain];
	[link release];
	link = newLink;
}

/* title
 * Returns the item title.
 */
-(NSString *)title
{
	return title;
}

/* description
 * Returns the item description
 */
-(NSString *)description
{
	return description;
}

/* author
 * Returns the item author
 */
-(NSString *)author
{
	return author;
}

/* date
 * Returns the item date
 */
-(NSDate *)date
{
	return date;
}

/* guid
 * Returns the item GUID.
 */
-(NSString *)guid
{
	return guid;
}

/* link
 * Returns the item link.
 */
-(NSString *)link
{
	return link;
}

/* dealloc
 * Clean up when we're released.
 */
-(void)dealloc
{
	[guid release];
	[title release];
	[description release];
	[author release];
	[date release];
	[link release];
	[super dealloc];
}
@end

@implementation RichXMLParser

/* init
 * Creates a RichXMLParser instance.
 */
-(id)init
{
	if ((self = [super init]) != nil)
	{
		title = nil;
		description = nil;
		lastModified = nil;
		link = nil;
		items = nil;
	}
	return self;
}

/* reset
 * Reset to remove existing feed info.
 */
-(void)reset
{
	[title release];
	[description release];
	[lastModified release];
	[link release];
	[items release];
	title = nil;
	description = nil;
	link = nil;
	items = nil;
}

/* parseRichXML
 * Given an XML feed in xmlData, parses the feed as either an RSS or an Atom feed.
 * The actual parsed items can subsequently be accessed through the interface.
 */
-(BOOL)parseRichXML:(NSData *)xmlData
{
	BOOL success = NO;
	if ([self setData:xmlData])
	{
		XMLParser * subtree;
		
		// If this RSS?
		if ((subtree = [self treeByName:@"rss"]) != nil)
			success = [self initRSSFeed:subtree isRDF:NO];

		// If this RSS:RDF?
		else if ((subtree = [self treeByName:@"rdf:RDF"]) != nil)
			success = [self initRSSFeed:subtree isRDF:YES];

		// Atom?
		else if ((subtree = [self treeByName:@"feed"]) != nil)
			success = [self initAtomFeed:subtree];
	}
	return success;
}

/* initRSSFeed
 * Prime the feed with header and items from an RSS feed
 */
-(BOOL)initRSSFeed:(XMLParser *)feedTree isRDF:(BOOL)isRDF
{
	BOOL success = [self initRSSFeedHeader:[self channelTree:feedTree]];
	if (success)
	{
		if (isRDF)
			success = [self initRSSFeedItems:feedTree];
		else
			success = [self initRSSFeedItems:[self channelTree:feedTree]];
	}
	return success;
}

/* channelTree
 * Return the root of the RSS feed's channel.
 */
-(XMLParser *)channelTree:(XMLParser *)feedTree
{
	XMLParser * channelTree = [feedTree treeByName:@"channel"];
	if (channelTree == nil)
		channelTree = [feedTree treeByName:@"rss:channel"];
	return channelTree;
}

/* initRSSFeedHeader
 * Parse an RSS feed header items.
 */
-(BOOL)initRSSFeedHeader:(XMLParser *)feedTree
{
	BOOL success = YES;
	
	// Iterate through the channel items
	int count = [feedTree countOfChildren];
	int index;
	
	for (index = 0; index < count; ++index)
	{
		XMLParser * subTree = [feedTree treeByIndex:index];
		NSString * nodeName = [subTree nodeName];

		// Parse title
		if ([nodeName isEqualToString:@"title"])
		{
			[self setTitle:[XMLParser processAttributes:[subTree valueOfElement]]];
			continue;
		}

		// Parse description
		if ([nodeName isEqualToString:@"description"])
		{
			[self setDescription:[subTree valueOfElement]];
			continue;
		}			
		
		// Parse link
		if ([nodeName isEqualToString:@"link"])
		{
			[self setLink:[subTree valueOfElement]];
			continue;
		}			
		
		// Parse the date when this feed was last updated
		if ([nodeName isEqualToString:@"lastBuildDate"])
		{
			NSString * dateString = [subTree valueOfElement];
			[self setLastModified:[XMLParser parseXMLDate:dateString]];
			continue;
		}
		
		// Parse item date
		if ([nodeName isEqualToString:@"dc:date"])
		{
			NSString * dateString = [subTree valueOfElement];
			[self setLastModified:[XMLParser parseXMLDate:dateString]];
			continue;
		}

		// Parse item date
		if ([nodeName isEqualToString:@"pubDate"])
		{
			NSString * dateString = [subTree valueOfElement];
			[self setLastModified:[XMLParser parseXMLDate:dateString]];
			continue;
		}
	}
	return success;
}

/* initRSSFeedItems
 * Parse the items from an RSS feed
 */
-(BOOL)initRSSFeedItems:(XMLParser *)feedTree
{
	BOOL success = YES;

	// Allocate an items array
	NSAssert(items == nil, @"initRSSFeedItems called more than once per initialisation");
	items = [[NSMutableArray alloc] initWithCapacity:10];
	
	// Iterate through the channel items
	int count = [feedTree countOfChildren];
	int index;
	
	for (index = 0; index < count; ++index)
	{
		XMLParser * subTree = [feedTree treeByIndex:index];
		NSString * nodeName = [subTree nodeName];
		
		// Parse a single item to construct a FeedItem object which is appended to
		// the items array we maintain.
		if ([nodeName isEqualToString:@"item"])
		{
			FeedItem * newItem = [[FeedItem alloc] init];
			int itemCount = [subTree countOfChildren];
			BOOL hasDetailedContent = NO;
			BOOL hasGUID = NO;
			int itemIndex;

			[newItem setDate:[self lastModified]];
			for (itemIndex = 0; itemIndex < itemCount; ++itemIndex)
			{
				XMLParser * subItemTree = [subTree treeByIndex:itemIndex];
				NSString * itemNodeName = [subItemTree nodeName];

				// Parse item title
				if ([itemNodeName isEqualToString:@"title"])
				{
					[newItem setTitle:[XMLParser processAttributes:[[subItemTree valueOfElement] firstNonBlankLine]]];
					continue;
				}
				
				// Parse item description
				if ([itemNodeName isEqualToString:@"description"] && !hasDetailedContent)
				{
					[newItem setDescription:[subItemTree valueOfElement]];
					continue;
				}
				
				// Parse GUID
				if ([itemNodeName isEqualToString:@"guid"])
				{
					[newItem setGuid:[subItemTree valueOfElement]];
					hasGUID = YES;
					continue;
				}
				
				// Parse detailed item description. This overrides the existing
				// description for this item.
				if ([itemNodeName isEqualToString:@"content:encoded"])
				{
					[newItem setDescription:[subItemTree valueOfElement]];
					hasDetailedContent = YES;
					continue;
				}
				
				// Parse item author
				if ([itemNodeName isEqualToString:@"author"])
				{
					[newItem setAuthor:[subItemTree valueOfElement]];
					continue;
				}
				
				// Parse item author
				if ([itemNodeName isEqualToString:@"dc:creator"])
				{
					[newItem setAuthor:[subItemTree valueOfElement]];
					continue;
				}
				
				// Parse item date
				if ([itemNodeName isEqualToString:@"dc:date"])
				{
					NSString * dateString = [subItemTree valueOfElement];
					[newItem setDate:[XMLParser parseXMLDate:dateString]];
					continue;
				}
				
				// Parse item author
				if ([itemNodeName isEqualToString:@"link"])
				{
					NSString * linkName = [subItemTree valueOfElement];
					[newItem setLink:linkName];
					continue;
				}
				
				// Parse item date
				if ([itemNodeName isEqualToString:@"pubDate"])
				{
					NSString * dateString = [subItemTree valueOfElement];
					[newItem setDate:[XMLParser parseXMLDate:dateString]];
					continue;
				}
			}

			// If no explicit GUID is specified, use the link as the GUID
			if (!hasGUID)
				[newItem setGuid:[self guidFromItem:newItem]];

			// Derive any missing title
			[self ensureTitle:newItem];
			[items addObject:newItem];
			[newItem release];
		}
	}
	return success;
}

/* initAtomFeed
 * Prime the feed with header and items from an Atom feed
 */
-(BOOL)initAtomFeed:(XMLParser *)feedTree
{
	BOOL success = YES;
	
	// Allocate an items array
	NSAssert(items == nil, @"initAtomFeed called more than once per initialisation");
	items = [[NSMutableArray alloc] initWithCapacity:10];
	
	// Iterate through the atom items
	int count = [feedTree countOfChildren];
	int index;
	
	for (index = 0; index < count; ++index)
	{
		XMLParser * subTree = [feedTree treeByIndex:index];
		NSString * nodeName = [subTree nodeName];
		NSString * defaultAuthor = @"";

		// Parse title
		if ([nodeName isEqualToString:@"title"])
		{
			[self setTitle:[XMLParser processAttributes:[subTree valueOfElement]]];
			continue;
		}
		
		// Parse description
		if ([nodeName isEqualToString:@"tagline"])
		{
			[self setDescription:[subTree valueOfElement]];
			continue;
		}			
		
		// Parse link
		if ([nodeName isEqualToString:@"link"])
		{
			[self setLink:[subTree valueOfAttribute:@"href"]];
			continue;
		}			
		
		// Parse author at the feed level. This is the default for any entry
		// that doesn't have an explicit author.
		if ([nodeName isEqualToString:@"author"])
		{
			defaultAuthor = [subTree valueOfElement];
			continue;
		}			
		
		// Parse the date when this feed was last updated
		if ([nodeName isEqualToString:@"modified"])
		{
			NSString * dateString = [subTree valueOfElement];
			[self setLastModified:[XMLParser parseXMLDate:dateString]];
			continue;
		}
		
		// Parse a single item to construct a FeedItem object which is appended to
		// the items array we maintain.
		if ([nodeName isEqualToString:@"entry"])
		{
			FeedItem * newItem = [[FeedItem alloc] init];
			[newItem setAuthor:defaultAuthor];
			int itemCount = [subTree countOfChildren];
			int itemIndex;
			BOOL hasGUID = NO;

			[newItem setDate:[self lastModified]];
			for (itemIndex = 0; itemIndex < itemCount; ++itemIndex)
			{
				XMLParser * subItemTree = [subTree treeByIndex:itemIndex];
				NSString * itemNodeName = [subItemTree nodeName];
				
				// Parse item title
				if ([itemNodeName isEqualToString:@"title"])
				{
					[newItem setTitle:[XMLParser processAttributes:[[subItemTree valueOfElement] firstNonBlankLine]]];
					continue;
				}

				// Parse item description
				if ([itemNodeName isEqualToString:@"content"])
				{
					[newItem setDescription:[subItemTree valueOfElement]];
					continue;
				}
				
				// Parse item description
				if ([itemNodeName isEqualToString:@"summary"])
				{
					[newItem setDescription:[subItemTree valueOfElement]];
					continue;
				}
				
				// Parse item author
				if ([itemNodeName isEqualToString:@"author"])
				{
					XMLParser * emailTree = [subItemTree treeByName:@"name"];
					[newItem setAuthor:[emailTree valueOfElement]];
					continue;
				}
				
				// Parse item link
				if ([itemNodeName isEqualToString:@"link"])
				{
					[newItem setLink:[subItemTree valueOfAttribute:@"href"]];
					continue;
				}
				
				// Parse item link
				if ([itemNodeName isEqualToString:@"id"])
				{
					[newItem setGuid:[subItemTree valueOfElement]];
					hasGUID = YES;
					continue;
				}
				
				// Parse item date
				if ([itemNodeName isEqualToString:@"modified"])
				{
					NSString * dateString = [subItemTree valueOfElement];
					[newItem setDate:[XMLParser parseXMLDate:dateString]];
					continue;
				}
			}

			// If no explicit GUID is specified, use the link as the GUID
			if (!hasGUID)
				[newItem setGuid:[self guidFromItem:newItem]];

			// Derive any missing title
			[self ensureTitle:newItem];
			[items addObject:newItem];
			[newItem release];
		}
	}
	
	return success;
}

/* setTitle
 * Set this feed's title string.
 */
-(void)setTitle:(NSString *)newTitle
{
	[newTitle retain];
	[title release];
	title = newTitle;
}

/* setDescription
 * Set this feed's description string.
 */
-(void)setDescription:(NSString *)newDescription
{
	[newDescription retain];
	[description release];
	description = newDescription;
}

/* setLink
 * Sets this feed's link
 */
-(void)setLink:(NSString *)newLink
{
	[newLink retain];
	[link release];
	link = newLink;
}

/* setLastModified
 * Set the date when this feed was last updated.
 */
-(void)setLastModified:(NSDate *)newDate
{
	[newDate retain];
	[lastModified release];
	lastModified = newDate;
}

/* title
 * Return the title string.
 */
-(NSString *)title
{
	return title;
}

/* description
 * Return the description string.
 */
-(NSString *)description
{
	return description;
}

/* link
 * Returns the URL of this feed
 */
-(NSString *)link
{
	return link;
}

/* items
 * Returns the array of items.
 */
-(NSArray *)items
{
	return items;
}

/* lastModified
 * Returns the feed's last update
 */
-(NSDate *)lastModified
{
	return lastModified;
}

/* guidFromItem
 * This routine attempts to synthesize a GUID from an incomplete item that lacks an
 * ID field. Generally we'll have three things to work from: a link, a title and a
 * description. The link alone is not sufficiently unique and I've seen feeds where
 * the description is also not unique. The title field generally does vary but we need
 * to be careful since separate articles with different descriptions may have the same
 * title. The solution is to hash the link and title and build a GUID from those.
 */
-(NSString *)guidFromItem:(FeedItem *)item
{
	return [NSString stringWithFormat:@"%X-%X", [[item link] hash], [[item title] hash]];
}

/* ensureTitle
 * Make sure we have a title and synthesize one from the description if we don't.
 */
-(void)ensureTitle:(FeedItem *)item
{
	if (![item title] || [[item title] isBlank])
		[item setTitle:[NSString stringByRemovingHTML:[item description]]];
	else
		[item setTitle:[NSString stringByRemovingHTML:[item title]]];
}

/* dealloc
 * Clean up afterwards.
 */
-(void)dealloc
{
	[title release];
	[description release];
	[lastModified release];
	[link release];
	[items release];
	[super dealloc];
}
@end
