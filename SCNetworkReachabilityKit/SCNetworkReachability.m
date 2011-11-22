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

NSString *const kSCNetworkReachabilityDidChangeNotification = @"SCNetworkReachabilityDidChange";
NSString *const kSCNetworkReachabilityFlagsKey = @"SCNetworkReachabilityFlags";

static void SCNetworkReachabilityCallback(SCNetworkReachabilityRef networkReachability, SCNetworkReachabilityFlags flags, void *info)
{
	[[NSNotificationCenter defaultCenter] postNotificationName:kSCNetworkReachabilityDidChangeNotification object:(__bridge_transfer SCNetworkReachability *)info userInfo:[NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedInt:flags] forKey:kSCNetworkReachabilityFlagsKey]];
}

@implementation SCNetworkReachability

@synthesize networkReachability        = _networkReachability;
@synthesize isLinkLocalInternetAddress = _isLinkLocalInternetAddress;

- (id)initWithAddress:(const struct sockaddr *)address
{
	self = [super init];
	if (self)
	{
		_networkReachability = SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, address);
		if (_networkReachability == NULL)
		{
			self = nil;
		}
		else
		{
			// For technical details regarding link-local connections, please
			// see the following source file at Apple's open-source site.
			//
			//	http://www.opensource.apple.com/source/bootp/bootp-89/IPConfiguration.bproj/linklocal.c
			//
			_isLinkLocalInternetAddress = address->sa_len == sizeof(struct sockaddr_in) && address->sa_family == AF_INET && IN_LINKLOCAL(ntohl(((const struct sockaddr_in *)address)->sin_addr.s_addr));
		}
	}
	return self;
}

- (id)initWithLocalAddress:(const struct sockaddr *)localAddress remoteAddress:(const struct sockaddr *)remoteAddress
{
	self = [super init];
	if (self)
	{
		_networkReachability = SCNetworkReachabilityCreateWithAddressPair(kCFAllocatorDefault, localAddress, remoteAddress);
		if (_networkReachability == NULL)
		{
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
		_networkReachability = SCNetworkReachabilityCreateWithName(kCFAllocatorDefault, [name UTF8String]);
		if (_networkReachability == NULL)
		{
			self = nil;
		}
	}
	return self;
}

+ (SCNetworkReachability *)networkReachabilityForAddress:(const struct sockaddr *)address
{
	return [[self alloc] initWithAddress:address];
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

+ (SCNetworkReachability *)networkReachabilityForName:(NSString *)name
{
	return [[self alloc] initWithName:name];
}

//------------------------------------------------------------------------------
#pragma mark                                      Synchronous Reachability Flags
//------------------------------------------------------------------------------

- (BOOL)getFlags:(SCNetworkReachabilityFlags *)outFlags
{
	return SCNetworkReachabilityGetFlags(_networkReachability, outFlags) != FALSE;
}

//------------------------------------------------------------------------------
#pragma mark                                                       Notifications
//------------------------------------------------------------------------------

- (BOOL)startNotifier
{
	SCNetworkReachabilityContext context =
	{
		.info = (__bridge_retained void *)self
	};
	return SCNetworkReachabilitySetCallback(_networkReachability, SCNetworkReachabilityCallback, &context) && SCNetworkReachabilityScheduleWithRunLoop(_networkReachability, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
}

- (BOOL)stopNotifier
{
	return SCNetworkReachabilityUnscheduleFromRunLoop(_networkReachability, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
}

//------------------------------------------------------------------------------
#pragma mark                                       Asynchronous Reachable Status
//------------------------------------------------------------------------------

- (SCNetworkReachable)networkReachableForFlags:(SCNetworkReachabilityFlags)flags
{
	SCNetworkReachable networkReachable;
	if (_isLinkLocalInternetAddress)
	{
		if ((flags & kSCNetworkReachabilityFlagsReachable) && (flags & kSCNetworkReachabilityFlagsIsDirect))
		{
			// <-- reachable AND direct
			networkReachable = kSCNetworkReachableViaWiFi;
		}
		else
		{
			// <-- NOT reachable OR NOT direct
			networkReachable = kSCNetworkNotReachable;
		}
	}
	else
	{
		if ((flags & kSCNetworkReachabilityFlagsReachable))
		{
			// <-- reachable
#if TARGET_OS_IPHONE
			if ((flags & kSCNetworkReachabilityFlagsIsWWAN))
			{
				// <-- reachable AND is wireless wide-area network (iOS only)
				networkReachable = kSCNetworkReachableViaWWAN;
			}
			else
			{
#endif
				// <-- reachable AND is NOT wireless wide-area network (iOS only)
				if ((flags & kSCNetworkReachabilityFlagsConnectionOnTraffic) || (flags & kSCNetworkReachabilityFlagsConnectionOnDemand))
				{
					// <-- reachable, on-traffic OR on-demand connection
					if ((flags & kSCNetworkReachabilityFlagsInterventionRequired))
					{
						// <-- reachable, on-traffic OR on-demand connection, intervention required
						networkReachable = (flags & kSCNetworkReachabilityFlagsConnectionRequired) ? kSCNetworkNotReachable : kSCNetworkReachableViaWiFi;
					}
					else
					{
						// <-- reachable, on-traffic OR on-demand connection, intervention NOT required
						networkReachable = kSCNetworkReachableViaWiFi;
					}
				}
				else
				{
					// <-- reachable, NOT on-traffic OR on-demand connection
					networkReachable = (flags & kSCNetworkReachabilityFlagsConnectionRequired) ? kSCNetworkNotReachable : kSCNetworkReachableViaWiFi;
				}
#if TARGET_OS_IPHONE
			}
#endif
		}
		else
		{
			// <-- NOT reachable
			networkReachable = kSCNetworkNotReachable;
		}
	}
	return networkReachable;
}

- (void)dealloc
{
	if (_networkReachability)
	{
		CFRelease(_networkReachability);
		_networkReachability = NULL;
	}
}

@end
