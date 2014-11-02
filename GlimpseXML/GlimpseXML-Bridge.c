//
//  GlimpseXML-Bridge.c
//  GlimpseXML
//
//  Created by Marc Prud'hommeaux on 10/13/14.
//  Copyright (c) 2014 glimpse.io. All rights reserved.
//

#include "GlimpseXML-Bridge.h"
#include <Block.h>


void _GlimpseXMLStructuredErrorHappened(void *userData, xmlErrorPtr error) {
    if (userData != NULL) {
        ((GlimpseXMLStructuredErrorCallback)userData)(*error);
    }
}

void GlimpseXMLStructuredErrorCallbackCreate(GlimpseXMLStructuredErrorCallback callback) {
    xmlSetStructuredErrorFunc(callback == NULL ? NULL : Block_copy(callback), _GlimpseXMLStructuredErrorHappened);
}

void GlimpseXMLStructuredErrorCallbackDestroy() {
    if (xmlStructuredErrorContext != NULL) {
        Block_release((GlimpseXMLStructuredErrorCallback)xmlStructuredErrorContext);
    }
    xmlSetStructuredErrorFunc(NULL, NULL); // reset the error handler
}


void _GlimpseXMLGenericErrorHappened(void *userData, const char *msg, ...) {
    if (userData != NULL) {
        ((GlimpseXMLGenericErrorCallback)userData)(msg);
    }
}

void GlimpseXMLGenericErrorCallbackCreate(GlimpseXMLGenericErrorCallback callback) {
    xmlSetGenericErrorFunc(callback == NULL ? NULL : Block_copy(callback), _GlimpseXMLGenericErrorHappened);
}

void GlimpseXMLGenericErrorCallbackDestroy() {
    if (xmlGenericErrorContext != NULL) {
        Block_release((GlimpseXMLGenericErrorCallback)xmlGenericErrorContext);
    }
    xmlSetGenericErrorFunc(NULL, NULL); // reset the error handler
}
