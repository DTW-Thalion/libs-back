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
#include <Foundation/NSDebug.h>
#include <Foundation/NSValue.h>

#include "android/AndroidServer.h"

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

@end
