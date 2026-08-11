/* AndroidGLPixelFormat - backend implementation of NSOpenGLPixelFormat

   Copyright (C) 2026 Free Software Foundation, Inc.

   Author: Todd White <todd.white@thalion.global>
   Date: August 2026

   This file is part of the GNU Objective C Backend Library.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; see the file COPYING.LIB.
   If not, see <http://www.gnu.org/licenses/> or write to the
   Free Software Foundation, 51 Franklin Street, Fifth Floor,
   Boston, MA 02110-1301, USA.
*/

#include "config.h"

#ifdef HAVE_EGL

#include <Foundation/NSDebug.h>
#include <Foundation/NSUserDefaults.h>
#include <Foundation/NSZone.h>
#include <string.h>

#include "android/AndroidOpenGL.h"

@implementation AndroidGLPixelFormat

/* The attributes that are followed by a value in the array. */
static BOOL
_isAttributeWithValue(NSOpenGLPixelFormatAttribute attr)
{
  switch (attr)
    {
      case NSOpenGLPFAAuxBuffers:
      case NSOpenGLPFAColorSize:
      case NSOpenGLPFAAlphaSize:
      case NSOpenGLPFADepthSize:
      case NSOpenGLPFAStencilSize:
      case NSOpenGLPFAAccumSize:
      case NSOpenGLPFARendererID:
      case NSOpenGLPFAScreenMask:
      case NSOpenGLPFASamples:
      case NSOpenGLPFAAuxDepthStencil:
      case NSOpenGLPFASampleBuffers:
	return YES;
      default:
	return NO;
    }
}

/* GNUstep declares no NSOpenGLPFAOpenGLProfile, so an application has no
 * attribute with which to ask for one OpenGL ES version over another.  The
 * backend takes it as a default, the way it takes its screen size.  A version
 * the platform will not give is its own to refuse, so the value is passed on
 * and eglCreateContext reports what happened. */
static EGLint
_requestedClientVersion(void)
{
  NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];

  if ([defs objectForKey: @"GSAndroidGLESVersion"] == nil)
    {
      return 2;
    }
  return (EGLint)[defs integerForKey: @"GSAndroidGLESVersion"];
}

- (id) initWithAttributes: (NSOpenGLPixelFormatAttribute *)attribs
{
  NSOpenGLPixelFormatAttribute *ptr;

  self = [super init];
  if (self == nil)
    {
      return nil;
    }

  _clientVersion = _requestedClientVersion();

  if (attribs == NULL)
    {
      _attributeCount = 1;
      _attributes = NSZoneMalloc(NSDefaultMallocZone(),
	sizeof(NSOpenGLPixelFormatAttribute));
      _attributes[0] = (NSOpenGLPixelFormatAttribute)0;
      return self;
    }

  _attributeCount = 1;
  for (ptr = attribs; *ptr != 0; ptr++)
    {
      _attributeCount++;
      if (_isAttributeWithValue(*ptr) && *(ptr + 1) != 0)
	{
	  ptr++;
	  _attributeCount++;
	}
    }

  _attributes = NSZoneMalloc(NSDefaultMallocZone(),
    _attributeCount * sizeof(NSOpenGLPixelFormatAttribute));
  memcpy(_attributes, attribs,
    _attributeCount * sizeof(NSOpenGLPixelFormatAttribute));

  return self;
}

- (EGLint) clientVersion
{
  return _clientVersion;
}

- (EGLConfig) eglConfigForDisplay: (EGLDisplay)eglDisplay
{
  EGLint     redSize = 8, greenSize = 8, blueSize = 8, alphaSize = 8;
  EGLint     depthSize = 24, stencilSize = 8;
  EGLint     sampleBuffers = 0, samples = 0;
  EGLint     renderableType;
  EGLConfig  config = NULL;
  EGLint     configCount = 0;
  NSUInteger i;

  switch (_clientVersion)
    {
      case 1:  renderableType = EGL_OPENGL_ES_BIT;  break;
      case 3:  renderableType = EGL_OPENGL_ES3_BIT; break;
      default: renderableType = EGL_OPENGL_ES2_BIT; break;
    }

  for (i = 0; _attributes != NULL && i + 1 < _attributeCount; i++)
    {
      NSOpenGLPixelFormatAttribute attr = _attributes[i];

      if (_isAttributeWithValue(attr) == NO)
	{
	  continue;
	}

      switch (attr)
	{
	  case NSOpenGLPFAColorSize:
	    redSize = greenSize = blueSize = ((EGLint)_attributes[i + 1] / 3);
	    if (redSize < 1)
	      {
		redSize = greenSize = blueSize = 1;
	      }
	    break;
	  case NSOpenGLPFAAlphaSize:
	    alphaSize = _attributes[i + 1];
	    break;
	  case NSOpenGLPFADepthSize:
	    depthSize = _attributes[i + 1];
	    break;
	  case NSOpenGLPFAStencilSize:
	    stencilSize = _attributes[i + 1];
	    break;
	  case NSOpenGLPFASampleBuffers:
	    sampleBuffers = _attributes[i + 1];
	    break;
	  case NSOpenGLPFASamples:
	    samples = _attributes[i + 1];
	    break;
	  default:
	    break;
	}

      i++;
    }

  {
    EGLint attrs[] = {
      EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
      EGL_RENDERABLE_TYPE, renderableType,
      EGL_RED_SIZE, redSize,
      EGL_GREEN_SIZE, greenSize,
      EGL_BLUE_SIZE, blueSize,
      EGL_ALPHA_SIZE, alphaSize,
      EGL_DEPTH_SIZE, depthSize,
      EGL_STENCIL_SIZE, stencilSize,
      EGL_SAMPLE_BUFFERS, sampleBuffers,
      EGL_SAMPLES, samples,
      EGL_NONE
    };

    if (eglChooseConfig(eglDisplay, attrs, &config, 1, &configCount) == EGL_FALSE
      || configCount == 0)
      {
	NSDebugMLLog(@"OpenGL",
	  @"no EGL config matched the requested NSOpenGL attributes");
	return NULL;
      }
  }

  return config;
}

- (void) getValues: (int *)vals
      forAttribute: (NSOpenGLPixelFormatAttribute)attrib
  forVirtualScreen: (int)screen
{
  NSUInteger i;

  (void)screen;

  if (vals == NULL)
    {
      return;
    }

  *vals = 0;
  if (_attributes == NULL)
    {
      return;
    }

  for (i = 0; i + 1 < _attributeCount; i++)
    {
      if (_attributes[i] == attrib)
	{
	  *vals = _isAttributeWithValue(attrib) ? _attributes[i + 1] : 1;
	  return;
	}
    }
}

- (void) dealloc
{
  if (_attributes != NULL)
    {
      NSZoneFree(NSDefaultMallocZone(), _attributes);
      _attributes = NULL;
    }
  [super dealloc];
}

@end

#endif /* HAVE_EGL */
