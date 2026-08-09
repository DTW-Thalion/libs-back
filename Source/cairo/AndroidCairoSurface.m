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

/* device is the struct AndroidWindow the server keeps for this window id. */
- (id) initWithDevice: (void *)device
{
  struct AndroidWindow *window = (struct AndroidWindow *)device;
  int			w, h;

  if (window == NULL)
    {
      NSDebugLLog(@"AndroidCairoSurface", @"no device for the surface");
      DESTROY(self);
      return nil;
    }

  gsDevice = device;

  w = (int)NSWidth(window->frame);
  h = (int)NSHeight(window->frame);
  if (w <= 0 || h <= 0)
    {
      NSDebugLLog(@"AndroidCairoSurface",
		  @"window %d has a %dx%d frame, no surface made",
		  window->window_id, w, h);
      DESTROY(self);
      return nil;
    }

  _surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, w, h);

  /* Checked here rather than at first use: a surface in an error state accepts
   * every drawing call and discards it, which shows up much later as an empty
   * window rather than as a failure to create one. */
  if (cairo_surface_status(_surface) != CAIRO_STATUS_SUCCESS)
    {
      NSLog(@"AndroidCairoSurface: %dx%d surface: %s", w, h,
	    cairo_status_to_string(cairo_surface_status(_surface)));
      cairo_surface_destroy(_surface);
      _surface = NULL;
      DESTROY(self);
      return nil;
    }

  window->surface = self;
  return self;
}

- (void) dealloc
{
  struct AndroidWindow *window = (struct AndroidWindow *)gsDevice;

  if (window != NULL && window->surface == self)
    {
      window->surface = nil;
    }
  /* _surface is destroyed by CairoSurface -dealloc. */
  [super dealloc];
}

- (NSSize) size
{
  if (_surface == NULL)
    {
      return NSZeroSize;
    }
  return NSMakeSize(cairo_image_surface_get_width(_surface),
		    cairo_image_surface_get_height(_surface));
}

- (void) setSize: (NSSize)newSize
{
  cairo_surface_t *replacement;
  int		   w = (int)newSize.width;
  int		   h = (int)newSize.height;

  if (w <= 0 || h <= 0)
    {
      NSDebugLLog(@"AndroidCairoSurface",
		  @"ignoring a resize to %dx%d", w, h);
      return;
    }
  if (_surface != NULL
      && cairo_image_surface_get_width(_surface) == w
      && cairo_image_surface_get_height(_surface) == h)
    {
      return;
    }

  replacement = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, w, h);
  if (cairo_surface_status(replacement) != CAIRO_STATUS_SUCCESS)
    {
      NSLog(@"AndroidCairoSurface: resize to %dx%d: %s", w, h,
	    cairo_status_to_string(cairo_surface_status(replacement)));
      cairo_surface_destroy(replacement);
      return;
    }
  if (_surface != NULL)
    {
      cairo_surface_destroy(_surface);
    }
  _surface = replacement;
}

/* Nothing is on screen, so an expose has nothing to post: the image surface is
 * already the destination. */
- (void) handleExposeRect: (NSRect)rect
{
}

- (BOOL) isDrawingToScreen
{
  return NO;
}

@end
