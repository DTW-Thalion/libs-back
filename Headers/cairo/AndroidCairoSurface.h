/*
   AndroidCairoSurface.h

   Copyright (C) 2026 Free Software Foundation, Inc.

   This file is part of GNUstep.

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

#ifndef AndroidCairoSurface_h
#define AndroidCairoSurface_h

#include "cairo/CairoSurface.h"

#include <android/native_window.h>

@interface AndroidCairoSurface : CairoSurface
{
  /* The window this surface posts to, or NULL while it is offscreen.  It is
   * not retained: the server owns it and outlives the surface. */
  ANativeWindow *_window;
}

- (void) setNativeWindow: (ANativeWindow *)window;
- (ANativeWindow *) nativeWindow;

@end

#endif /* AndroidCairoSurface_h */
