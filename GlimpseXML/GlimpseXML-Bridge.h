//
//  GlimpseXML-Bridge.h
//  GlimpseXML
//
//  Created by Marc Prud'hommeaux on 10/13/14.
//  Copyright (c) 2014 glimpse.io. All rights reserved.
//

/*
    We need to import libxml headers for the GlimpseXML module itself, but we don't want to expose them to external modules because then they would need to all add the libxml2 include directory to their header search paths, so only inlude the headers when we are building the framework itself with:

    GCC_PREPROCESSOR_DEFINITIONS = GLIMPSEXML_FRAMEWORK
 */
#if GLIMPSEXML_FRAMEWORK

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
