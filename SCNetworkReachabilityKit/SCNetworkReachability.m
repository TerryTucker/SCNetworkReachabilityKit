// SCNetworkReachabilityKit SCNetworkReachability.m
//
// Copyright © 2011, Roy Ratcliffe, Pioneering Software, United Kingdom
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the “Software”), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
//	The above copyright notice and this permission notice shall be included in
//	all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED “AS IS,” WITHOUT WARRANTY OF ANY KIND, EITHER
// EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NON-INFRINGEMENT. IN NO
// EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES
// OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
// ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
// DEALINGS IN THE SOFTWARE.
//
//------------------------------------------------------------------------------

#import "SCNetworkReachability.h"

#import <netinet/in.h>

NSString *kSCNetworkReachabilityDidChangeNotification = @"SCNetworkReachabilityDidChange";
NSString *kSCNetworkReachabilityFlagsKey = @"SCNetworkReachabilityFlags";

static void SCNetworkReachabilityCallback(SCNetworkReachabilityRef networkReachability, SCNetworkReachabilityFlags flags, void *info)
{
	[[NSNotificationCenter defaultCenter] postNotificationName:kSCNetworkReachabilityDidChangeNotification object:info userInfo:[NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedInt:flags] forKey:kSCNetworkReachabilityFlagsKey]];
}

@implementation SCNetworkReachability

@synthesize isLinkLocalInternetAddress;

- (id)initWithAddress:(const struct sockaddr *)address
{
	self = [super init];
	if (self)
	{
		networkReachability = SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, address);
		if (networkReachability == NULL)
		{
			[self release];
			self = nil;
		}
		else
		{
			// http://www.opensource.apple.com/source/bootp/bootp-89/IPConfiguration.bproj/linklocal.c
			isLinkLocalInternetAddress = address->sa_len == sizeof(struct sockaddr_in) && address->sa_family == AF_INET && IN_LINKLOCAL(ntohl(((const struct sockaddr_in *)address)->sin_addr.s_addr));
		}
	}
	return self;
}

- (id)initWithLocalAddress:(const struct sockaddr *)localAddress remoteAddress:(const struct sockaddr *)remoteAddress
{
	self = [super init];
	if (self)
	{
		networkReachability = SCNetworkReachabilityCreateWithAddressPair(kCFAllocatorDefault, localAddress, remoteAddress);
		if (networkReachability == NULL)
		{
			[self release];
			self = nil;
		}
	}
	return self;
}

- (id)initWithName:(NSString *)name
{
	self = [super init];
	if (self)
	{
		networkReachability = SCNetworkReachabilityCreateWithName(kCFAllocatorDefault, [name UTF8String]);
		if (networkReachability == NULL)
		{
			[self release];
			self = nil;
		}
	}
	return self;
}

+ (SCNetworkReachability *)networkReachabilityForAddress:(const struct sockaddr *)address
{
	return [[[SCNetworkReachability alloc] initWithAddress:address] autorelease];
}

+ (SCNetworkReachability *)networkReachabilityForInternetAddress:(in_addr_t)internetAddress
{
	struct sockaddr_in address;
	bzero(&address, sizeof(address));
	address.sin_len = sizeof(address);
	address.sin_family = AF_INET;
	address.sin_addr.s_addr = htonl(internetAddress);
	return [self networkReachabilityForAddress:(struct sockaddr *)&address];
}

+ (SCNetworkReachability *)networkReachabilityForInternet
{
	return [self networkReachabilityForInternetAddress:INADDR_ANY];
}

+ (SCNetworkReachability *)networkReachabilityForLinkLocal
{
	return [self networkReachabilityForInternetAddress:IN_LINKLOCALNETNUM];
}

- (BOOL)getFlags:(SCNetworkReachabilityFlags *)outFlags
{
	return SCNetworkReachabilityGetFlags(networkReachability, outFlags) != FALSE;
}

- (BOOL)connectionRequired
{
	SCNetworkReachabilityFlags flags;
	return [self getFlags:&flags] && (flags & kSCNetworkReachabilityFlagsConnectionRequired) != 0;
}

- (BOOL)startNotifier
{
	SCNetworkReachabilityContext context =
	{
		.info = self
	};
	return SCNetworkReachabilitySetCallback(networkReachability, SCNetworkReachabilityCallback, &context) && SCNetworkReachabilityScheduleWithRunLoop(networkReachability, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
}

- (BOOL)stopNotifier
{
	return SCNetworkReachabilityUnscheduleFromRunLoop(networkReachability, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
}

- (void)dealloc
{
	if (networkReachability)
	{
		CFRelease(networkReachability);
		networkReachability = NULL;
	}
	[super dealloc];
}

@end