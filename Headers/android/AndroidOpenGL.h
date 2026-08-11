/* 	-*-ObjC-*- */
/* AndroidOpenGL - NSOpenGL management for the android backend

   Copyright (C) 2026 Free Software Foundation, Inc.

   Author: Todd White <todd.white@thalion.global>
   Date: August 2026

   This file is part of the GNUstep Backend.

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

#ifndef _GNUstep_H_AndroidOpenGL_
#define _GNUstep_H_AndroidOpenGL_

#include <AppKit/NSOpenGL.h>
#include <EGL/egl.h>
#include <stddef.h>

@class NSView;

/* An NSOpenGLPixelFormat that answers an EGLConfig.
 *
 * The config asks for a pbuffer.  An activity is given one surface and it has
 * one producer: while an EGL window surface holds it, ANativeWindow_lock fails
 * with -22, and the server composites every window through that lock, so a GL
 * drawable here is offscreen.
 *
 * The OpenGL ES version is no part of the config, since every config the
 * platform reports is renderable by ES 1, 2 and 3 alike.  It is a context
 * attribute, and -clientVersion answers it.
 */
@interface AndroidGLPixelFormat : NSOpenGLPixelFormat
{
  NSOpenGLPixelFormatAttribute *_attributes;
  NSUInteger			_attributeCount;
  EGLint			_clientVersion;
}

/* The config matching the attributes, or NULL when nothing matches. */
- (EGLConfig) eglConfigForDisplay: (EGLDisplay)eglDisplay;

/* The OpenGL ES version a context made from this format asks for: 2 unless the
 * GSAndroidGLESVersion default names another. */
- (EGLint) clientVersion;

@end

/* An NSOpenGLContext that renders into an EGL pbuffer.
 *
 * -flushBuffer reads the pbuffer back and writes it into the cairo surface of
 * the window the view is in, at the view's frame, so GL content reaches the
 * screen by the path every other window takes: the server composites that
 * surface into the activity's own.
 */
@interface AndroidGLContext : NSOpenGLContext
{
  NSOpenGLPixelFormat	*_pixelFormat;
  NSOpenGLContext	*_shareContext;
  NSView		*_view;
  EGLDisplay		 _eglDisplay;
  EGLContext		 _eglContext;
  EGLSurface		 _eglSurface;
  int			 _surfaceWidth;
  int			 _surfaceHeight;
  long			 _swapInterval;
  unsigned char		*_readback;
  size_t		 _readbackSize;
}

@end

#endif /* _GNUstep_H_AndroidOpenGL_ */
