/* AndroidGLContext - backend implementation of NSOpenGLContext

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
#include <Foundation/NSException.h>
#include <AppKit/NSView.h>
#include <AppKit/NSWindow.h>
#include <stdlib.h>

#include "android/AndroidOpenGL.h"

static AndroidGLContext *currentGLContext = nil;

@implementation AndroidGLContext

+ (void) clearCurrentContext
{
  if (currentGLContext != nil
    && currentGLContext->_eglDisplay != EGL_NO_DISPLAY)
    {
      eglMakeCurrent(currentGLContext->_eglDisplay, EGL_NO_SURFACE,
	EGL_NO_SURFACE, EGL_NO_CONTEXT);
    }
  currentGLContext = nil;
}

+ (NSOpenGLContext *) currentContext
{
  return currentGLContext;
}

- (id) initWithFormat: (NSOpenGLPixelFormat *)format
	 shareContext: (NSOpenGLContext *)share
{
  self = [super init];
  if (self == nil)
    {
      return nil;
    }

  if (format == nil
    || [format isKindOfClass: [AndroidGLPixelFormat class]] == NO)
    {
      NSDebugMLLog(@"OpenGL", @"pixel format %@ is not this backend's", format);
      [self release];
      return nil;
    }

  _eglDisplay = EGL_NO_DISPLAY;
  _eglContext = EGL_NO_CONTEXT;
  _eglSurface = EGL_NO_SURFACE;
  _surfaceWidth = 0;
  _surfaceHeight = 0;
  _swapInterval = 0;
  _readback = NULL;
  _readbackSize = 0;
  _pixelFormat = RETAIN(format);
  _shareContext = RETAIN(share);

  return self;
}

- (id) initWithCGLContextObj: (void *)context
{
  NSDebugMLLog(@"OpenGL",
    @"initWithCGLContextObj is not supported on android (%p)", context);
  [self release];
  return nil;
}

- (NSOpenGLPixelFormat *) pixelFormat
{
  return _pixelFormat;
}

- (void *) CGLContextObj
{
  return (void *)_eglContext;
}

- (void) copyAttributesFromContext: (NSOpenGLContext *)context
			  withMask: (unsigned long)mask
{
  (void)context;
  (void)mask;
}

/* The EGL display and context, made once and kept.
 *
 * There is no native display to derive one from, as there is under GLX and
 * wayland: EGL_DEFAULT_DISPLAY is the platform's own and is available with no
 * activity and no window.  OpenGL ES is the only API that binds here;
 * eglBindAPI(EGL_OPENGL_API) answers EGL_BAD_PARAMETER. */
- (BOOL) _ensureContext
{
  EGLint     major = 0;
  EGLint     minor = 0;
  EGLConfig  config;
  EGLContext shared = EGL_NO_CONTEXT;
  EGLint     version;
  EGLint     contextAttrs[3];

  if (_eglDisplay != EGL_NO_DISPLAY && _eglContext != EGL_NO_CONTEXT)
    {
      return YES;
    }

  _eglDisplay = eglGetDisplay(EGL_DEFAULT_DISPLAY);
  if (_eglDisplay == EGL_NO_DISPLAY)
    {
      NSLog(@"AndroidGLContext: EGL has no default display");
      return NO;
    }
  if (eglInitialize(_eglDisplay, &major, &minor) == EGL_FALSE)
    {
      NSLog(@"AndroidGLContext: eglInitialize failed, 0x%x", eglGetError());
      _eglDisplay = EGL_NO_DISPLAY;
      return NO;
    }
  if (eglBindAPI(EGL_OPENGL_ES_API) == EGL_FALSE)
    {
      NSLog(@"AndroidGLContext: eglBindAPI(EGL_OPENGL_ES_API) failed, 0x%x",
	eglGetError());
      return NO;
    }

  config = [(AndroidGLPixelFormat *)_pixelFormat
	     eglConfigForDisplay: _eglDisplay];
  if (config == NULL)
    {
      return NO;
    }

  if (_shareContext != nil
    && [_shareContext isKindOfClass: [AndroidGLContext class]])
    {
      shared = ((AndroidGLContext *)_shareContext)->_eglContext;
    }

  version = [(AndroidGLPixelFormat *)_pixelFormat clientVersion];
  contextAttrs[0] = EGL_CONTEXT_CLIENT_VERSION;
  contextAttrs[1] = version;
  contextAttrs[2] = EGL_NONE;

  _eglContext = eglCreateContext(_eglDisplay, config, shared, contextAttrs);
  if (_eglContext == EGL_NO_CONTEXT)
    {
      NSLog(@"AndroidGLContext: no OpenGL ES %d context, 0x%x",
	(int)version, eglGetError());
      return NO;
    }

  return YES;
}

/* The view's size in its window, which is the size of the pbuffer.  A view
 * with no window, or with no area, has none. */
- (BOOL) _viewSize: (int *)outWidth : (int *)outHeight
{
  NSRect bounds;

  if (_view == nil || [_view window] == nil)
    {
      return NO;
    }
  bounds = [_view convertRect: [_view bounds] toView: nil];
  *outWidth = (int)NSWidth(bounds);
  *outHeight = (int)NSHeight(bounds);

  return (*outWidth > 0 && *outHeight > 0);
}

/* The pbuffer, at the view's current size.  A pbuffer cannot be resized, so a
 * view that changed shape gets a new one. */
- (BOOL) _ensureSurface
{
  EGLConfig  config;
  EGLSurface replacement;
  EGLint     surfaceAttrs[5];
  int	     w = 0;
  int	     h = 0;

  if ([self _ensureContext] == NO)
    {
      return NO;
    }
  if ([self _viewSize: &w : &h] == NO)
    {
      return NO;
    }
  if (_eglSurface != EGL_NO_SURFACE
    && w == _surfaceWidth && h == _surfaceHeight)
    {
      return YES;
    }

  config = [(AndroidGLPixelFormat *)_pixelFormat
	     eglConfigForDisplay: _eglDisplay];
  if (config == NULL)
    {
      return NO;
    }

  surfaceAttrs[0] = EGL_WIDTH;
  surfaceAttrs[1] = w;
  surfaceAttrs[2] = EGL_HEIGHT;
  surfaceAttrs[3] = h;
  surfaceAttrs[4] = EGL_NONE;

  replacement = eglCreatePbufferSurface(_eglDisplay, config, surfaceAttrs);
  if (replacement == EGL_NO_SURFACE)
    {
      NSLog(@"AndroidGLContext: no %dx%d pbuffer, 0x%x", w, h, eglGetError());
      return NO;
    }

  if (_eglSurface != EGL_NO_SURFACE)
    {
      if (currentGLContext == self)
	{
	  eglMakeCurrent(_eglDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE,
	    EGL_NO_CONTEXT);
	}
      eglDestroySurface(_eglDisplay, _eglSurface);
    }
  _eglSurface = replacement;
  _surfaceWidth = w;
  _surfaceHeight = h;

  return YES;
}

- (void) setView: (NSView *)view
{
  if (view == nil)
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"setView: called with nil"];
    }
  ASSIGN(_view, view);
  [self _ensureSurface];
}

- (NSView *) view
{
  return _view;
}

- (void) clearDrawable
{
  if (_eglSurface != EGL_NO_SURFACE)
    {
      if (currentGLContext == self)
	{
	  eglMakeCurrent(_eglDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE,
	    EGL_NO_CONTEXT);
	  currentGLContext = nil;
	}
      eglDestroySurface(_eglDisplay, _eglSurface);
      _eglSurface = EGL_NO_SURFACE;
      _surfaceWidth = 0;
      _surfaceHeight = 0;
    }
  DESTROY(_view);
}

- (void) makeCurrentContext
{
  if (_view == nil)
    {
      [NSException raise: NSGenericException
		  format: @"the GL context has no view and cannot be current"];
    }
  if ([self _ensureSurface] == NO)
    {
      return;
    }
  if (eglMakeCurrent(_eglDisplay, _eglSurface, _eglSurface, _eglContext)
    == EGL_FALSE)
    {
      NSLog(@"AndroidGLContext: eglMakeCurrent failed, 0x%x", eglGetError());
      return;
    }
  currentGLContext = self;
}

- (void) getValues: (long *)vals forParameter: (NSOpenGLContextParameter)param
{
  if (vals == NULL)
    {
      return;
    }
  switch (param)
    {
      case NSOpenGLCPSwapInterval:
	*vals = _swapInterval;
	break;
      case NSOpenGLCPSurfaceOpacity:
	*vals = 1;
	break;
      default:
	*vals = 0;
	break;
    }
}

/* A pbuffer is never presented, so a swap interval throttles nothing.  It is
 * kept and reported back rather than refused: an application that sets it is
 * asking for vsync and gets the rate its own drawing runs at. */
- (void) setValues: (const long *)vals
      forParameter: (NSOpenGLContextParameter)param
{
  if (vals == NULL)
    {
      return;
    }
  if (param == NSOpenGLCPSwapInterval)
    {
      _swapInterval = *vals;
    }
}

- (void) dealloc
{
  if (currentGLContext == self)
    {
      [AndroidGLContext clearCurrentContext];
    }
  if (_eglDisplay != EGL_NO_DISPLAY)
    {
      if (_eglSurface != EGL_NO_SURFACE)
	{
	  eglDestroySurface(_eglDisplay, _eglSurface);
	}
      if (_eglContext != EGL_NO_CONTEXT)
	{
	  eglDestroyContext(_eglDisplay, _eglContext);
	}
    }
  if (_readback != NULL)
    {
      free(_readback);
    }
  DESTROY(_view);
  DESTROY(_pixelFormat);
  DESTROY(_shareContext);
  [super dealloc];
}

@end

#endif /* HAVE_EGL */
