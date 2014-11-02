//
//  GlimpseXML-Bridge.h
//  GlimpseXML
//
//  Created by Marc Prud'hommeaux on 10/13/14.
//  Copyright (c) 2014 glimpse.io. All rights reserved.
//

// this is a hack: we set this flag for all frameworks in Glimpse-Common.xcconfig's GCC_PREPROCESSOR_DEFINITIONS setting; this reason is that if this isn't ifdef'd out, for non-Glimpse builds, then importing code from Glimpse.playground tries to import these headers, but without the additional HEADER_SEARCH_PATHS=$(SDKROOT)/usr/include/libxml2, the relative paths can't be resolved (and there doesn't appear to be any way to set header search paths for a playground); note that a module.modulemap doesn't help, because that also cannot be found by the playground
#if LIBXML2_HEADER_SEARCH_PATHS
#import <libxml/tree.h>
#import <libxml/parser.h>
#import <libxml/xmlstring.h>
#import <libxml/xpath.h>
#import <libxml/xpathinternals.h>

typedef void (^GlimpseXMLStructuredErrorCallback)(struct _xmlError error);
void GlimpseXMLStructuredErrorCallbackCreate(GlimpseXMLStructuredErrorCallback callback);
void GlimpseXMLStructuredErrorCallbackDestroy();

typedef void (^GlimpseXMLGenericErrorCallback)(const char *msg);
void GlimpseXMLGenericErrorCallbackCreate(GlimpseXMLGenericErrorCallback callback);
void GlimpseXMLGenericErrorCallbackDestroy();

#endif

