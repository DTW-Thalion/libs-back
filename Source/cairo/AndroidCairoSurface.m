/* AndroidCairoSurface

   A cairo surface for the Android backend.  It is an offscreen image surface:
   the window has real geometry, nothing is on screen, and -flushwindowrect::
   has nothing to post because the image surface is already the destination.
   A surface backed by the buffer ANativeWindow_lock hands out replaces the
   allocation here, behind this same class.

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

#include "android/AndroidServer.h"
#include "cairo/AndroidCairoSurface.h"

#include <Foundation/NSDebug.h>

@implementation AndroidCairoSurface

- (id) initWithDevice: (void *)device
{
  gsDevice = device;
  return self;
}

- (NSSize) size
{
  return NSZeroSize;
}

- (void) setSize: (NSSize)newSize
{
}

- (BOOL) isDrawingToScreen
{
  return NO;
}

@end
