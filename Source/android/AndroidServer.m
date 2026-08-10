/*
   AndroidServer.m

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

#include "config.h"

#include <signal.h>
#include <stdint.h>
#include <stdlib.h>

#include <AppKit/NSApplication.h>
#include <AppKit/NSEvent.h>
#include <AppKit/NSGraphics.h>
#include <AppKit/NSGraphicsContext.h>
#include <AppKit/NSWindow.h>
#include <AppKit/DPSOperators.h>
#include <Foundation/NSArray.h>
#include <Foundation/NSDebug.h>
#include <Foundation/NSString.h>
#include <Foundation/NSUserDefaults.h>
#include <Foundation/NSValue.h>

#include "android/AndroidServer.h"
#include "cairo/CairoSurface.h"
#include "cairo/AndroidCairoSurface.h"

/* Terminate cleanly if we get a signal to do so. */
static void
terminate(int sig)
{
  if (nil != NSApp)
    {
      [NSApp terminate: NSApp];
    }
  else
    {
      exit(1);
    }
}

/* Parse "320x640" into a size, or NSZeroSize. */
static NSSize
sizeFromString(NSString *s)
{
  NSArray *parts;

  if (s == nil)
    {
      return NSZeroSize;
    }
  parts = [s componentsSeparatedByString: @"x"];
  if ([parts count] != 2)
    {
      return NSZeroSize;
    }
  return NSMakeSize([[parts objectAtIndex: 0] doubleValue],
		    [[parts objectAtIndex: 1] doubleValue]);
}

@implementation AndroidServer

+ (void) initializeBackend
{
  NSDebugLog(@"Initializing GNUstep android backend.");
  [GSDisplayServer setDefaultServerClass: [AndroidServer class]];
  signal(SIGTERM, terminate);
  signal(SIGINT, terminate);
}

- (id) initWithAttributes: (NSDictionary *)info
{
  self = [super initWithAttributes: info];
  if (self != nil)
    {
      _windows = NSCreateMapTable(NSIntegerMapKeyCallBacks,
				  NSNonOwnedPointerMapValueCallBacks, 8);
      _lastWindowId = 0;
      _screenBounds = NSZeroRect;
      _screenBoundsKnown = NO;
      _screenWarningIssued = NO;
      _mouseLocation = NSZeroPoint;
    }
  return self;
}

- (void) dealloc
{
  if (_windows != NULL)
    {
      NSFreeMapTable(_windows);
      _windows = NULL;
    }
  [super dealloc];
}

- (struct AndroidWindow *) _windowWithId: (int)win
{
  if (_windows == NULL || win <= 0)
    {
      return NULL;
    }
  return (struct AndroidWindow *) NSMapGet(_windows, (void *)(intptr_t)win);
}

/* The server draws no title bar, resize corner or border, so the gui library
 * has to draw them.  GSDisplayServer answers YES by default. */
- (BOOL) handlesWindowDecorations
{
  return NO;
}

/*
 * Screens
 */

- (NSArray *) screenList
{
  return [NSArray arrayWithObject: [NSNumber numberWithInt: 0]];
}

/* The screen size comes from the GSAndroidScreenSize default rather than from
 * a constant, because a process with no Activity cannot ask Android for it:
 * AConfiguration_getScreenWidthDp needs an AConfiguration, whose only source
 * other than AConfiguration_new is AConfiguration_fromAssetManager, and the
 * only documented way to obtain an AAssetManager is AAssetManager_fromJava,
 * which needs a JNIEnv and a Java AssetManager.  ANativeWindow_getWidth has
 * the same problem: the only documented producer of an ANativeWindow is
 * ANativeWindow_fromSurface, which needs a Java Surface.
 *
 * When the default is not set this says so, once, and reports an empty screen.
 * A fabricated size would be believed, and every geometry answer computed from
 * it would be wrong in a way that looks like an AppKit fault.
 */
- (NSRect) boundsForScreen: (int)screen
{
  NSSize size;

  if (screen != 0)
    {
      return NSZeroRect;
    }
  if (_screenBoundsKnown)
    {
      return _screenBounds;
    }

  /* A bound window knows the real size, so the default below is the answer
   * only for a process that has no window at all -- which is every test but
   * the ones that make one, and no application. */
  {
    NSMapEnumerator  e = NSEnumerateMapTable(_windows);
    void	    *key, *value;

    while (NSNextMapEnumeratorPair(&e, &key, &value))
      {
	struct AndroidWindow *w = (struct AndroidWindow *)value;

	if (w != NULL && w->native != NULL)
	  {
	    _screenBounds = NSMakeRect(0, 0,
				       ANativeWindow_getWidth(w->native),
				       ANativeWindow_getHeight(w->native));
	    _screenBoundsKnown = YES;
	    NSEndMapTableEnumeration(&e);
	    return _screenBounds;
	  }
      }
    NSEndMapTableEnumeration(&e);
  }

  size = sizeFromString([[NSUserDefaults standardUserDefaults]
			  stringForKey: @"GSAndroidScreenSize"]);
  if (NSEqualSizes(size, NSZeroSize))
    {
      if (NO == _screenWarningIssued)
	{
	  NSLog(@"AndroidServer: no screen size available. Set the "
		@"GSAndroidScreenSize default (for example 320x640); the "
		@"screen is reported as empty until then.");
	  _screenWarningIssued = YES;
	}
      return NSZeroRect;
    }

  _screenBounds = NSMakeRect(0, 0, size.width, size.height);
  _screenBoundsKnown = YES;
  return _screenBounds;
}

/* The image surface is 32 bits per pixel with 8 bits per component in three
 * components, which is what NSBestDepth is asked for here. */
- (NSWindowDepth) windowDepthForScreen: (int)screen
{
  if (screen != 0)
    {
      return 0;
    }
  return NSBestDepth(NSCalibratedRGBColorSpace, 8, 24, NO, NULL);
}

/* The caller owns the returned list and frees it with NSZoneFree, which is what
 * the x11 server does, so this must be allocated and not static: freeing a
 * static array aborts the process with "Scudo ERROR: misaligned pointer when
 * deallocating" on Android. */
- (const NSWindowDepth *) availableDepthsForScreen: (int)screen
{
  NSWindowDepth *depths;

  if (screen != 0)
    {
      return NULL;
    }
  depths = NSZoneMalloc(NSDefaultMallocZone(), sizeof(NSWindowDepth) * 2);
  depths[0] = NSBestDepth(NSCalibratedRGBColorSpace, 8, 24, NO, NULL);
  depths[1] = 0;   /* zero-terminated */
  return depths;
}

/* Reported as 72dpi deliberately.  The gui library trusts this value and scales
 * the whole interface by it, so reporting the device's real density here would
 * rescale every window; the x11 server reports 72 for the same reason. */
- (NSSize) resolutionForScreen: (int)screen
{
  return NSMakeSize(72, 72);
}

- (NSImage *) contentsOfScreen: (int)screen inRect: (NSRect)rect
{
  return nil;
}

/*
 * Windows
 */

- (int) window: (NSRect)frame
	      : (NSBackingStoreType)type
	      : (unsigned int)style
	      : (int)screen
{
  struct AndroidWindow *window;

  /* A window always has an extent.  X refuses a zero-area window and clamps,
   * and the rest of the gui library assumes a window it created can be drawn
   * into; a 0x0 frame would also leave the cairo surface unmade. */
  if (frame.size.width < 1.0)
    {
      frame.size.width = 1.0;
    }
  if (frame.size.height < 1.0)
    {
      frame.size.height = 1.0;
    }

  window = (struct AndroidWindow *)
    NSZoneCalloc(NSDefaultMallocZone(), 1, sizeof(struct AndroidWindow));
  window->window_id = ++_lastWindowId;
  window->frame = frame;
  window->backing = type;
  window->style = style;
  window->screen = screen;
  window->level = NSNormalWindowLevel;
  window->mapped = NO;
  window->surface = nil;

  NSMapInsert(_windows, (void *)(intptr_t)window->window_id, window);
  [self _setWindowOwnedByServer: window->window_id];
  return window->window_id;
}

- (void) termwindow: (int)win
{
  struct AndroidWindow *window = [self _windowWithId: win];

  if (window == NULL)
    {
      return;
    }
  window->surface = nil;
  NSMapRemove(_windows, (void *)(intptr_t)win);
  NSZoneFree(NSDefaultMallocZone(), window);
}

- (void *) windowDevice: (int)win
{
  return (void *)[self _windowWithId: win];
}

- (void *) serverDevice
{
  return NULL;
}

- (NSRect) windowbounds: (int)win
{
  struct AndroidWindow *window = [self _windowWithId: win];

  return (window == NULL) ? NSZeroRect : window->frame;
}

/* The window is told about its own move or resize by an AppKit-defined event,
 * the same way the x11 server does it.  There is no server round trip here, so
 * the new frame is final and the event can be sent immediately. */
- (void) placewindow: (NSRect)frame : (int)win
{
  struct AndroidWindow *window = [self _windowWithId: win];
  NSWindow		*nswin;
  NSEvent		*e;
  BOOL			 resized, moved;

  if (window == NULL)
    {
      NSLog(@"AndroidServer: placing invalid window %d", win);
      return;
    }
  if (NSEqualRects(frame, window->frame))
    {
      return;
    }

  resized = !NSEqualSizes(frame.size, window->frame.size);
  moved = !NSEqualPoints(frame.origin, window->frame.origin);
  window->frame = frame;

  if (window->surface != nil && resized)
    {
      [window->surface setSize: frame.size];
    }

  nswin = GSWindowWithNumber(win);
  if (resized)
    {
      e = [NSEvent otherEventWithType: NSAppKitDefined
			     location: frame.origin
			modifierFlags: 0
			    timestamp: 0
			 windowNumber: win
			      context: GSCurrentContext()
			      subtype: GSAppKitWindowResized
				data1: frame.size.width
				data2: frame.size.height];
      [nswin sendEvent: e];
    }
  else if (moved)
    {
      e = [NSEvent otherEventWithType: NSAppKitDefined
			     location: NSZeroPoint
			modifierFlags: 0
			    timestamp: 0
			 windowNumber: win
			      context: GSCurrentContext()
			      subtype: GSAppKitWindowMoved
				data1: frame.origin.x
				data2: frame.origin.y];
      [nswin sendEvent: e];
    }
}

- (void) movewindow: (NSPoint)loc : (int)win
{
  struct AndroidWindow *window = [self _windowWithId: win];

  if (window == NULL)
    {
      return;
    }
  window->frame.origin = loc;
}

- (void) orderwindow: (int)op : (int)otherWin : (int)win
{
  struct AndroidWindow *window = [self _windowWithId: win];

  if (window == NULL)
    {
      return;
    }
  window->mapped = (op != NSWindowOut);
}

- (void) setwindowlevel: (int)level : (int)win
{
  struct AndroidWindow *window = [self _windowWithId: win];

  if (window != NULL)
    {
      window->level = level;
    }
}

- (int) windowlevel: (int)win
{
  struct AndroidWindow *window = [self _windowWithId: win];

  return (window == NULL) ? 0 : window->level;
}

- (int) windowdepth: (int)win
{
  return NSBestDepth(NSCalibratedRGBColorSpace, 8, 24, NO, NULL);
}

/* No decorations are drawn, so there are no insets.  -handlesWindowDecorations
 * answers NO, so the gui library draws its own and knows not to expect any. */
- (void) styleoffsets: (float *)l : (float *)r : (float *)t : (float *)b
		     : (unsigned int)style
{
  *l = *r = *t = *b = 0.0;
}

- (void) stylewindow: (unsigned int)style : (int)win
{
  struct AndroidWindow *window = [self _windowWithId: win];

  if (window != NULL)
    {
      window->style = style;
    }
}

- (void) windowbacking: (NSBackingStoreType)type : (int)win
{
  struct AndroidWindow *window = [self _windowWithId: win];

  if (window != NULL)
    {
      window->backing = type;
    }
}

/* Give the context a surface for this window.  GSSetDevice hands the window
 * record to the cairo context, which allocates the surface class the backend
 * was built with; the y offset is the window height because cairo's y axis
 * points down and AppKit's points up. */
- (void) setWindowdevice: (int)win forContext: (NSGraphicsContext *)ctxt
{
  struct AndroidWindow *window = [self _windowWithId: win];

  if (window == NULL)
    {
      NSLog(@"AndroidServer: setWindowdevice for unknown window %d", win);
      return;
    }

  GSSetDevice(ctxt, window, 0.0, NSHeight(window->frame));
  DPSinitmatrix(ctxt);
  DPSinitclip(ctxt);
}

/* With no window bound there is nothing to post: the image surface the context
 * drew into is already the destination.  With one, the named rectangle is
 * posted and only that: -flush posts the whole surface, so calling both would
 * post the window twice for one drawing operation. */
- (void) flushwindowrect: (NSRect)rect : (int)win
{
  struct AndroidWindow *window = [self _windowWithId: win];

  if (window == NULL || window->surface == nil)
    {
      return;
    }

  if (window->native == NULL)
    {
      [window->surface flush];
      return;
    }

  /* The rect arrives in the window's own coordinates, y up from the bottom;
   * the image surface indexes its rows from the top. */
  [window->surface
    handleExposeRect: NSMakeRect(NSMinX(rect),
				 NSHeight(window->frame) - NSMaxY(rect),
				 NSWidth(rect),
				 NSHeight(rect))];
}

- (void) setNativeWindow: (ANativeWindow *)native forWindow: (int)win
{
  struct AndroidWindow *window = [self _windowWithId: win];

  if (window == NULL)
    {
      return;
    }

  window->native = native;
  if (window->surface != nil)
    {
      [(AndroidCairoSurface *)window->surface setNativeWindow: native];
    }

  /* The screen is whatever the window says it is once there is one, so the
   * cached answer has to be given up. */
  _screenBoundsKnown = NO;
}

- (ANativeWindow *) nativeWindowForWindow: (int)win
{
  struct AndroidWindow *window = [self _windowWithId: win];

  return (window == NULL) ? NULL : window->native;
}

/* Nothing shows a title, a document-edited mark, an input state, an alpha or a
 * shadow while the surface is offscreen.  These are present because the other
 * servers have them and the gui library calls them on every window. */
- (void) titlewindow: (NSString *)title : (int)win { }
- (void) docedited: (int)edited : (int)win { }
- (void) setinputstate: (int)state : (int)win { }
- (void) setinputfocus: (int)win { }
- (void) setalpha: (float)alpha : (int)win { }
- (void) setShadow: (BOOL)hasShadow : (int)win { }
- (void) setmaxsize: (NSSize)size : (int)win { }
- (void) setminsize: (NSSize)size : (int)win { }
- (void) setresizeincrements: (NSSize)size : (int)win { }
- (void) miniwindow: (int)win { }
- (void) setParentWindow: (int)parentWin forChildWindow: (int)childWin { }
- (void) restrictWindow: (int)win toImage: (NSImage *)image { }
- (void) beep { }

/* Android has no window this process did not make, so there is no foreign
 * window to adopt. */
- (int) nativeWindow: (void *)winref
		    : (NSRect *)frame
		    : (NSBackingStoreType *)type
		    : (unsigned int *)style
		    : (int *)screen
{
  return 0;
}

/*
 * Pointer and cursor
 *
 * No pointer device exists while the surface is offscreen, so the server owns
 * the location: -setMouseLocation:onScreen: sets it and -mouselocation reports
 * it back.  x11, win32 and wayland all answer these, and answering keeps the
 * interface the same across the backends rather than raising where they do not.
 */

- (NSPoint) mouselocation
{
  return _mouseLocation;
}

- (NSPoint) mouseLocationOnScreen: (int)aScreen window: (int *)win
{
  if (win != NULL)
    {
      *win = 0;
    }
  return (aScreen == 0) ? _mouseLocation : NSZeroPoint;
}

- (void) setMouseLocation: (NSPoint)mouseLocation onScreen: (int)aScreen
{
  if (aScreen == 0)
    {
      _mouseLocation = mouseLocation;
    }
}

- (BOOL) capturemouse: (int)win { return NO; }
- (void) releasemouse { }
- (void) hidecursor { }
- (void) showcursor { }
- (void) standardcursor: (int)style : (void **)cid { *cid = NULL; }
- (void) imagecursor: (NSPoint)hotp : (NSImage *)image : (void **)cid { *cid = NULL; }
- (void) recolorcursor: (NSColor *)fg : (NSColor *)bg : (void *)cid { }
- (void) setcursor: (void *)cid { }
- (void) freecursor: (void *)cid { }

@end
