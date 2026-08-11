/*
   AndroidServer.h

   Copyright (C) 2026 Free Software Foundation, Inc.

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

#ifndef AndroidServer_h
#define AndroidServer_h

#include "config.h"

#include <Foundation/NSGeometry.h>
#include <Foundation/NSMapTable.h>
#include <GNUstepGUI/GSDisplayServer.h>

#include <android/input.h>
#include <android/native_window.h>
#include <jni.h>

@class CairoSurface;

/* One window as the server sees it.
 *
 * Everything above the server addresses a window by an integer id; this is
 * what the id names, and a pointer to it is what the cairo surface is handed
 * as its device, the same arrangement the wayland server uses with its own
 * window struct.  Coordinates are OpenStep: origin at the bottom left of the
 * screen, y increasing upwards.
 */
struct AndroidWindow
{
  int                 window_id;
  NSRect              frame;
  NSBackingStoreType  backing;
  unsigned int        style;
  int                 level;
  int                 screen;
  BOOL                mapped;
  CairoSurface       *surface;   /* nil until -setWindowdevice:forContext: */
  ANativeWindow      *native;    /* NULL while the window is offscreen      */
};

@interface AndroidServer : GSDisplayServer
{
  NSMapTable *_windows;          /* window id -> struct AndroidWindow *      */
  int         _lastWindowId;
  NSRect      _screenBounds;
  BOOL        _screenBoundsKnown;
  BOOL        _screenWarningIssued;
  NSPoint     _mouseLocation;
  ANativeWindow *_activityWindow; /* the surface an activity was handed      */
  int         _boundWindow;       /* the window it is bound to, 0 for none   */
  JNIEnv     *_jniEnv;            /* for the platform's key character table  */
}

+ (void) initializeBackend;

/* The record for a window id, or NULL when the id is not one of ours. */
- (struct AndroidWindow *) _windowWithId: (int)win;

/* Bind the window an activity was given to one of ours, so that drawing
 * reaches the screen instead of stopping at the image surface.  Passing NULL
 * unbinds, which is what the activity losing its window means. */
- (void) setNativeWindow: (ANativeWindow *)native forWindow: (int)win;
- (ANativeWindow *) nativeWindowForWindow: (int)win;

/* The surface an activity owns.  An application creates its windows when it
 * pleases and nothing outside knows their numbers, so the server binds this to
 * the first window ordered front that a person would call the application's,
 * and rebinds when that window goes away.  Passing NULL unbinds. */
- (void) setActivityWindow: (ANativeWindow *)native;
- (ANativeWindow *) activityWindow;

/* The window the activity's surface is currently bound to, or 0. */
- (int) windowBoundToActivity;

/* The environment the key character table is read through.  The NDK reports a
 * key by code and meta state and offers no character for it. */
- (void) setJavaEnvironment: (JNIEnv *)env;

/* Translate one event from the activity's input queue and post it.  Answers
 * YES when the event became an NSEvent. */
- (BOOL) handleInputEvent: (const AInputEvent *)event;

@end

#endif /* AndroidServer_h */
