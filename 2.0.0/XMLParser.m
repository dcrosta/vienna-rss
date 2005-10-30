//
//  XMLParser.m
//  Vienna
//
//  Created by Steve on 5/27/05.
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
// 

#import "XMLParser.h"
#import "StringExtensions.h"
#import <curl/curl.h>

@interface XMLParser (Private)
	-(void)setTreeRef:(CFXMLTreeRef)treeRef;
	+(NSString *)mapEntityToString:(NSString *)entityString;
	+(XMLParser *)treeWithCFXMLTreeRef:(CFXMLTreeRef)ref;
	-(XMLParser *)addTree:(NSString *)name withAttributes:(NSDictionary *)attributesDict closed:(BOOL)flag;
@end

// Used for mapping entities to their representations
static NSMutableDictionary * entityMap = nil;

@implementation XMLParser

/* setData
 * Initialises the XMLParser with a data block which contains the XML data.
 */
-(BOOL)setData:(NSData *)data
{
	CFXMLTreeRef newTree;
	CFDictionaryRef error = nil;

	NS_DURING
		newTree = CFXMLTreeCreateFromDataWithError(kCFAllocatorDefault, (CFDataRef)data, NULL, kCFXMLParserSkipWhitespace, kCFXMLNodeCurrentVersion, &error);
	NS_HANDLER
		newTree = nil;
	NS_ENDHANDLER
	if (newTree != nil)
	{
		[self setTreeRef:newTree];
		CFRelease(newTree);
		return YES;
	}
	return NO;
}

/* hasValidTree
 * Return TRUE if we have a valid tree.
 */
-(BOOL)hasValidTree
{
	return tree != nil;
}

/* treeWithCFXMLTreeRef
 * Allocates a new instance of an XMLParser with the specified tree.
 */
+(XMLParser *)treeWithCFXMLTreeRef:(CFXMLTreeRef)ref
{
	XMLParser * parser = [[XMLParser alloc] init];
	[parser setTreeRef:ref];
	return [parser autorelease];
}

/* setTreeRef
 * Initialises the XMLParser with a data block which contains the XML data.
 */
-(void)setTreeRef:(CFXMLTreeRef)treeRef
{
	if (tree != nil)
		CFRelease(tree);
	if (node != nil)
		CFRelease(node);
	tree = treeRef;
	node = CFXMLTreeGetNode(tree);
	CFRetain(tree);
	CFRetain(node);
}

/* initWithEmptyTree
 * Creates an empty XML tree to which we can add nodes.
 */
-(id)initWithEmptyTree
{
	if ((self = [self init]) != nil)
	{
		// Create the document node
		CFXMLDocumentInfo documentInfo;
		documentInfo.sourceURL = NULL;
		documentInfo.encoding = kCFStringEncodingUTF8;
		CFXMLNodeRef docNode = CFXMLNodeCreate(kCFAllocatorDefault, kCFXMLNodeTypeDocument, CFSTR(""), &documentInfo, kCFXMLNodeCurrentVersion);
		CFXMLTreeRef xmlDocument = CFXMLTreeCreateWithNode(kCFAllocatorDefault, docNode);
		CFRelease(docNode);
		
		// Add the XML header to the document
		CFXMLProcessingInstructionInfo instructionInfo;
		instructionInfo.dataString = CFSTR("version=\"1.0\" encoding=\"utf-8\"");
		CFXMLNodeRef instructionNode = CFXMLNodeCreate(kCFAllocatorDefault, kCFXMLNodeTypeProcessingInstruction, CFSTR("xml"), &instructionInfo, kCFXMLNodeCurrentVersion);
		CFXMLTreeRef instructionTree = CFXMLTreeCreateWithNode(kCFAllocatorDefault, instructionNode);
		CFTreeAppendChild(xmlDocument, instructionTree);
		
		// Create the parser object from this
		[self setTreeRef:instructionTree];
		CFRelease(instructionTree);
		CFRelease(instructionNode);
	}
	return self;
}

/* init
 * Designated initialiser.
 */
-(id)init
{
	if ((self = [super init]) != nil)
	{
		tree = nil;
		node = nil;
	}
	return self;
}

/* addTree
 * Adds a sub-tree to the current tree and returns its XMLParser object.
 */
-(XMLParser *)addTree:(NSString *)name
{
	CFXMLElementInfo info;
	info.attributes = NULL;
	info.attributeOrder = NULL;
	info.isEmpty = NO;

	CFXMLNodeRef newTreeNode = CFXMLNodeCreate(kCFAllocatorDefault, kCFXMLNodeTypeElement, (CFStringRef)name, &info, kCFXMLNodeCurrentVersion);
	CFXMLTreeRef newTree = CFXMLTreeCreateWithNode(kCFAllocatorDefault, newTreeNode);
	CFTreeAppendChild(tree, newTree);

	// Create the parser object from this
	XMLParser * newParser = [XMLParser treeWithCFXMLTreeRef:newTree];
	CFRelease(newTreeNode);
	return newParser;
}

/* addTree:withElement
 * Add a new tree and give it the specified element.
 */
-(XMLParser *)addTree:(NSString *)name withElement:(NSString *)value
{
	XMLParser * newTree = [self addTree:name];
	[newTree addElement:value];
	return newTree;
}

/* addElement
 * Add an element to the tree.
 */
-(void)addElement:(NSString *)value
{
	CFXMLNodeRef newNode = CFXMLNodeCreate(kCFAllocatorDefault, kCFXMLNodeTypeText, (CFStringRef)value, NULL, kCFXMLNodeCurrentVersion);   
	CFXMLTreeRef newTree = CFXMLTreeCreateWithNode(kCFAllocatorDefault, newNode);
	CFTreeAppendChild(tree, newTree);
	CFRelease(newTree);
	CFRelease(newNode);
}

/* addClosedTree:withAttributes
 * Add a new tree with attributes to the tree.
 */
-(XMLParser *)addClosedTree:(NSString *)name withAttributes:(NSDictionary *)attributesDict
{
	return [self addTree:name withAttributes:attributesDict closed:YES];
}

/* addTree:withAttributes
 * Add a new tree with attributes to the tree.
 */
-(XMLParser *)addTree:(NSString *)name withAttributes:(NSDictionary *)attributesDict
{
	return [self addTree:name withAttributes:attributesDict closed:NO];
}

/* addTree:withAttributes:closed
 * Add a new tree with attributes to the tree.
 */
-(XMLParser *)addTree:(NSString *)name withAttributes:(NSDictionary *)attributesDict closed:(BOOL)flag
{
	CFXMLElementInfo info;
	info.attributes = (CFDictionaryRef)attributesDict;
	info.attributeOrder = (CFArrayRef)[attributesDict allKeys];
	info.isEmpty = flag;

	CFXMLNodeRef newNode = CFXMLNodeCreate (kCFAllocatorDefault, kCFXMLNodeTypeElement, (CFStringRef)name, &info, kCFXMLNodeCurrentVersion);   
	CFXMLTreeRef newTree = CFXMLTreeCreateWithNode(kCFAllocatorDefault, newNode);
	CFTreeAppendChild(tree, newTree);

	// Create the parser object from this
	XMLParser * newParser = [XMLParser treeWithCFXMLTreeRef:newTree];
	CFRelease(newTree);
	CFRelease(newNode);
	return newParser;
}

/* treeByIndex
 * Returns an XMLParser object for the child tree at the specified index.
 */
-(XMLParser *)treeByIndex:(int)index
{
	return [XMLParser treeWithCFXMLTreeRef:CFTreeGetChildAtIndex(tree, index)];
}

/* treeByPath
 * Retrieves a tree located by a specified sub-nesting of XML nodes. For example, given the
 * following XML document:
 *
 *   <root>
 *		<body>
 *			<element></element>
 *		</body>
 *   </root>
 *
 * Then treeByPath:@"root/body/element" will return the tree for the <element> node. If any
 * element does not exist, it returns nil.
 */
-(XMLParser *)treeByPath:(NSString *)path
{
	NSArray * pathElements = [path componentsSeparatedByString:@"/"];
	NSEnumerator * enumerator = [pathElements objectEnumerator];
	XMLParser * treeFound = self;
	NSString * treeName;
	
	while ((treeName = [enumerator nextObject]) != nil)
	{
		treeFound = [treeFound treeByName:treeName];
		if (treeFound == nil)
			return nil;
	}
	return treeFound;
}

/* treeByName
 * Given a node in the XML tree, this returns the sub-tree with the specified name or nil
 * if the tree cannot be found.
 */
-(XMLParser *)treeByName:(NSString *)name
{
	int count = CFTreeGetChildCount(tree);
	int index;
	
	for (index = count - 1; index >= 0; --index)
	{
		CFXMLTreeRef subTree = CFTreeGetChildAtIndex(tree, index);
		CFXMLNodeRef subNode = CFXMLTreeGetNode(subTree);
		if ([name isEqualToString:(NSString *)CFXMLNodeGetString(subNode)])
			return [XMLParser treeWithCFXMLTreeRef:subTree];
	}
	return nil;
}

/* countOfChildren
 * Count of children of this tree
 */
-(int)countOfChildren
{
	return CFTreeGetChildCount(tree);
}

/* xmlForTree
 * Returns the XML text for the specified tree.
 */
-(NSString *)xmlForTree
{
	NSData * data = (NSData *)CFXMLTreeCreateXMLData(kCFAllocatorDefault, tree);
	NSString * xmlString = [NSString stringWithCString:[data bytes] length:[data length]];
	CFRelease(data);
	return xmlString;
}

/* description
 * Make this return the XML string which is pretty useful.
 */
-(NSString *)description
{
	return [self xmlForTree];
}

/* attributesForTree
 * Returns a dictionary of all attributes on the current tree.
 */
-(NSDictionary *)attributesForTree
{
	if (CFXMLNodeGetTypeCode(node) == kCFXMLNodeTypeElement )
	{
		CFXMLElementInfo eInfo = *(CFXMLElementInfo *)CFXMLNodeGetInfoPtr(node);
		return [[(NSDictionary *)eInfo.attributes retain] autorelease];
	}
	return nil;
}

/* valueOfAttribute
 * Returns the value of the named attribute of the specified node. If the node is a processing instruction
 * then what we obtain from CFXMLNodeGetInfoPtr is a pointer to a CFXMLProcessingInstructionInfo structure
 * which encodes the entire processing instructions as a single string. Thus to obtain the 'attribute' that
 * equates to the processing instruction element we're interested in we need to parse that string to extract
 * the value.
 */
-(NSString *)valueOfAttribute:(NSString *)attributeName
{
	if (CFXMLNodeGetTypeCode(node) == kCFXMLNodeTypeElement)
	{
		CFXMLElementInfo eInfo = *(CFXMLElementInfo *)CFXMLNodeGetInfoPtr(node);
		if (eInfo.attributes != nil)
		{
			return (NSString *)CFDictionaryGetValue(eInfo.attributes, attributeName);
		}
	}
	else if (CFXMLNodeGetTypeCode(node) == kCFXMLNodeTypeProcessingInstruction)
	{
		CFXMLProcessingInstructionInfo eInfo = *(CFXMLProcessingInstructionInfo *)CFXMLNodeGetInfoPtr(node);
		NSScanner * scanner = [NSScanner scannerWithString:(NSString *)eInfo.dataString];
		while (![scanner isAtEnd])
		{
			NSString * instructionName = nil;
			NSString * instructionValue = nil;

			[scanner scanUpToString:@"=" intoString:&instructionName];
			[scanner scanString:@"=" intoString:nil];
			[scanner scanUpToString:@" " intoString:&instructionValue];
			
			if (instructionName != nil && instructionValue != nil)
			{
				if ([instructionName isEqualToString:attributeName])
					return [instructionValue stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\""]];
			}
		}
	}
	return nil;
}

/* nodeName
 * Returns the name of the node of this tree.
 */
-(NSString *)nodeName
{
	return (NSString *)CFXMLNodeGetString(node);
}

/* valueOfElement
 * Returns the value of the element of the specified tree. Special case for handling application/xhtml+xml which
 * is a bunch of XML/HTML embedded in the tree without a CDATA. In order to get the raw text, we need to extract
 * the XML data itself and append it as we go along.
 */
-(NSString *)valueOfElement
{
	NSMutableString * valueString = [NSMutableString stringWithCapacity:16];
	NSString * mimeType = [self valueOfAttribute:@"type"];

	BOOL isXMLContent = [mimeType isEqualToString:@"application/xhtml+xml"];
	if ([mimeType isEqualToString:@"xhtml"])
		isXMLContent = YES;
	if ([mimeType isEqualToString:@"text/html"] && [[self valueOfAttribute:@"mode"] isEqualToString:@"xml"])
		isXMLContent = YES;

	if (isXMLContent)
	{
		int count = CFTreeGetChildCount(tree);
		int index;
		
		for (index = 0; index < count; ++index)
		{
			CFXMLTreeRef subTree = CFTreeGetChildAtIndex(tree, index);
			CFDataRef valueData = CFXMLTreeCreateXMLData(NULL, subTree);

			NSString * nString = [[NSString alloc] initWithBytes:CFDataGetBytePtr(valueData) length:CFDataGetLength(valueData) encoding:NSUTF8StringEncoding];
			[valueString appendString:nString];
			[nString release];

			CFRelease(valueData);
		}
	}
	else
	{
		int count = CFTreeGetChildCount(tree);
		int index;
		
		for (index = 0; index < count; ++index)
		{
			CFXMLTreeRef subTree = CFTreeGetChildAtIndex(tree, index);
			CFXMLNodeRef subNode = CFXMLTreeGetNode(subTree);
			NSString * valueName = (NSString *)CFXMLNodeGetString(subNode);
			if (valueName != nil)
			{
				if (CFXMLNodeGetTypeCode(subNode) == kCFXMLNodeTypeEntityReference)
					valueName = [XMLParser mapEntityToString:valueName];
				[valueString appendString:valueName];
			}
		}
	}
	return valueString;
}

/* quoteAttributes
 * Scan the specified string and convert HTML literal characters to their entity equivalents.
 */
+(NSString *)quoteAttributes:(NSString *)stringToProcess
{
	NSMutableString * newString = [NSMutableString stringWithString:stringToProcess];
	[newString replaceString:@"&" withString:@"&amp;"];
	[newString replaceString:@"<" withString:@"&lt;"];
	[newString replaceString:@">" withString:@"&gt;"];
	[newString replaceString:@"\"" withString:@"&quot;"];
	[newString replaceString:@"'" withString:@"&apos;"];
	return newString;
}

/* processAttributes
 * Scan the specified string and convert attribute characters to their literals. Also trim leading and trailing
 * whitespace.
 */
+(NSString *)processAttributes:(NSString *)stringToProcess
{
	if (stringToProcess == nil)
		return nil;

	NSMutableString * processedString = [[NSMutableString alloc] initWithString:stringToProcess];
	int entityStart;
	int entityEnd;
	
	entityStart = [processedString indexOfCharacterInString:'&' afterIndex:0];
	while (entityStart != NSNotFound)
	{
		entityEnd = [processedString indexOfCharacterInString:';' afterIndex:entityStart + 1];
		if (entityEnd != NSNotFound)
		{
			NSRange entityRange = NSMakeRange(entityStart, (entityEnd - entityStart) + 1);
			NSRange innerEntityRange = NSMakeRange(entityRange.location + 1, entityRange.length - 2);
			NSString * entityString = [processedString substringWithRange:innerEntityRange];
			[processedString replaceCharactersInRange:entityRange withString:[XMLParser mapEntityToString:entityString]];
		}
		entityStart = [processedString indexOfCharacterInString:'&' afterIndex:entityStart + 1];
	}
	
	NSString * returnString = [processedString trim];
	[processedString release];
	return returnString;
}

/* mapEntityToString
 * Maps an entity sequence to its character equivalent.
 */
+(NSString *)mapEntityToString:(NSString *)entityString
{
	if (entityMap == nil)
	{
		entityMap = [[NSMutableDictionary dictionaryWithObjectsAndKeys:
									@"<",	@"lt",
									@">",	@"gt",
									@"\"",	@"quot",
									@"&",	@"amp",
									@"'",	@"rsquo",
									@"'",	@"lsquo",
									@"'",	@"apos",
									@"...", @"hellip",
									nil,	nil] retain];

		// Add entities that map to non-ASCII characters
		[entityMap setValue:[NSString stringWithFormat:@"%C", 0xF6] forKey:@"ouml"];
		[entityMap setValue:[NSString stringWithFormat:@"%C", 0xD6] forKey:@"Ouml"];
		[entityMap setValue:[NSString stringWithFormat:@"%C", 0xF4] forKey:@"ocirc"];
		[entityMap setValue:[NSString stringWithFormat:@"%C", 0xD4] forKey:@"Ocirc"];
		[entityMap setValue:[NSString stringWithFormat:@"%C", 0xFC] forKey:@"uuml"];
		[entityMap setValue:[NSString stringWithFormat:@"%C", 0xDC] forKey:@"Uuml"];
        [entityMap setValue:[NSString stringWithFormat:@"%C", 0xF9] forKey:@"ugrave"];
		[entityMap setValue:[NSString stringWithFormat:@"%C", 0xFB] forKey:@"ucirc"];
		[entityMap setValue:[NSString stringWithFormat:@"%C", 0xD9] forKey:@"Ugrave"];
		[entityMap setValue:[NSString stringWithFormat:@"%C", 0xDB] forKey:@"Ucirc"];
		[entityMap setValue:[NSString stringWithFormat:@"%C", 0xEF] forKey:@"iuml"];
		[entityMap setValue:[NSString stringWithFormat:@"%C", 0xCF] forKey:@"Iuml"];
		[entityMap setValue:[NSString stringWithFormat:@"%C", 0xEB] forKey:@"euml"];
		[entityMap setValue:[NSString stringWithFormat:@"%C", 0xCB] forKey:@"Euml"];
		[entityMap setValue:[NSString stringWithFormat:@"%C", 0xE9] forKey:@"eacute"];
		[entityMap setValue:[NSString stringWithFormat:@"%C", 0xC9] forKey:@"Eacute"];
		[entityMap setValue:[NSString stringWithFormat:@"%C", 0xE8] forKey:@"egrave"];
		[entityMap setValue:[NSString stringWithFormat:@"%C", 0xC8] forKey:@"Egrave"];
		[entityMap setValue:[NSString stringWithFormat:@"%C", 0xEA] forKey:@"ecirc"];
		[entityMap setValue:[NSString stringWithFormat:@"%C", 0xCA] forKey:@"Ecirc"];
		[entityMap setValue:[NSString stringWithFormat:@"%C", 0xE4] forKey:@"auml"];
		[entityMap setValue:[NSString stringWithFormat:@"%C", 0xC4] forKey:@"Auml"];
		[entityMap setValue:[NSString stringWithFormat:@"%C", 0xE0] forKey:@"agrave"];
		[entityMap setValue:[NSString stringWithFormat:@"%C", 0xC2] forKey:@"Agrave"];
		[entityMap setValue:[NSString stringWithFormat:@"%C", 0xE7] forKey:@"ccedil"];
		[entityMap setValue:[NSString stringWithFormat:@"%C", 0xC7] forKey:@"Ccedil"];
		[entityMap setValue:[NSString stringWithFormat:@"%C", 0xCE] forKey:@"Icirc"];
		[entityMap setValue:[NSString stringWithFormat:@"%C", 0xEE] forKey:@"icirc"];
		[entityMap setValue:[NSString stringWithFormat:@"%C", 0xA3] forKey:@"pound"];
		[entityMap setValue:[NSString stringWithFormat:@"%C", 0x2022] forKey:@"bull"];
	}

	// Parse off numeric codes of the format #xxx
	if ([entityString length] > 1 && [entityString characterAtIndex:0] == '#')
	{
		int intValue;
		if ([entityString characterAtIndex:1] == 'x')
			intValue = [[entityString substringFromIndex:2] hexValue];
		else
			intValue = [[entityString substringFromIndex:1] intValue];
		return [NSString stringWithFormat:@"%C", MAX(intValue, ' ')];
	}

	NSString * mappedString = [entityMap objectForKey:entityString];
	return mappedString ? mappedString : [NSString stringWithFormat:@"&%@;", entityString];
}

/* parseXMLDate
 * Parse a date in an XML header into an NSCalendarDate. This is horribly expensive and needs
 * to be replaced with a parser that can handle these formats:
 *
 *   2005-10-23T10:12:22-4:00
 *   2005-10-23T10:12:22
 *   2005-10-23T10:12:22Z
 *   Mon, 10 Oct 2005 10:12:22 -4:00
 *   10 Oct 2005 10:12:22 -4:00
 *
 * These are the formats that I've discovered so far.
 */
+(NSCalendarDate *)parseXMLDate:(NSString *)dateString
{
	NSCalendarDate * date;

	// Let CURL have a crack at parsing since it knows all about the
	// RSS/HTTP formats.
	time_t theTime = curl_getdate([dateString cString], NULL);
	if (theTime != -1)
		return [NSDate dateWithTimeIntervalSince1970:theTime];

	// Otherwise it is probably the weird Atom format date
	date = [NSCalendarDate dateWithString:dateString calendarFormat:@"%Y-%m-%dT%H:%M:%S%z"];
	if (date == nil)
		date = [NSCalendarDate dateWithString:dateString calendarFormat:@"%Y-%m-%dT%H:%M%z"];
	if (date == nil)
		date = [NSCalendarDate dateWithString:dateString calendarFormat:@"%Y-%m-%dT%H:%M:%SZ"];
	if (date != nil)
	{
		// Atom times are relative to GMT so mark them as such.
		NSCalendarDate * atomDate = [NSCalendarDate dateWithYear:[date yearOfCommonEra]
														   month:[date monthOfYear]
															 day:[date dayOfMonth]
															hour:[date hourOfDay]
														  minute:[date minuteOfHour]
														  second:[date secondOfMinute]
														timeZone:[NSTimeZone timeZoneWithName:@"GMT"]];
		return atomDate;
	}
	return nil;
}

/* dealloc
 * Clean up when we're done.
 */
-(void)dealloc
{
	if (node != nil)
		CFRelease(node);
	if (tree != nil)
		CFRelease(tree);
	[super dealloc];
}
@end
