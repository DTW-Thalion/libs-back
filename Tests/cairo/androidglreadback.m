/* GL drawing reaches the cairo surface the server composites the window from.
 *
 * The context clears its pbuffer to a known colour and flushes; the pixels are
 * read out of the window's cairo image surface at the rect the view occupies.
 * That is the whole design: an activity is given one surface with one producer,
 * so GL renders offscreen and is composited as pixels rather than being handed
 * the surface.
 *
 * The comparison carries a tolerance of one per channel.  The same clear reads
 * back 40 80 bf ff on SwiftShader and 40 7f bf ff on a GPU, because 0.5f rounds
 * differently in the two rasterizers.
 */
#import <Foundation/Foundation.h>
#import "Testing.h"
#include "config.h"

#if defined(HAVE_EGL) && defined(BUILD_SERVER) && defined(SERVER_android) \
  && defined(BUILD_GRAPHICS) && defined(GRAPHICS_cairo) \
  && BUILD_SERVER == SERVER_android && BUILD_GRAPHICS == GRAPHICS_cairo

#import <AppKit/AppKit.h>
#import <AppKit/NSOpenGL.h>
#import <GNUstepGUI/GSDisplayServer.h>
#include <EGL/egl.h>
#include <GLES2/gl2.h>
#include <cairo.h>
#include <stdint.h>
#include <stdlib.h>

#include "android/AndroidServer.h"
#include "cairo/CairoSurface.h"

static uint32_t
pixelAt(cairo_surface_t *s, int x, int y)
{
  unsigned char *data = cairo_image_surface_get_data(s);
  int		 stride = cairo_image_surface_get_stride(s);

  return *(uint32_t *)(data + y * stride + x * 4);
}

/* ARGB32 is a native-endian word, so the channels come out by shifting. */
static BOOL
nearColour(uint32_t pixel, int a, int r, int g, int b)
{
  int pa = (pixel >> 24) & 0xff;
  int pr = (pixel >> 16) & 0xff;
  int pg = (pixel >> 8) & 0xff;
  int pb = pixel & 0xff;

  return (abs(pa - a) <= 1 && abs(pr - r) <= 1
    && abs(pg - g) <= 1 && abs(pb - b) <= 1);
}

int
main(void)
{
  START_SET("android GL readback")
  NSAutoreleasePool	*arp = [NSAutoreleasePool new];
  GSDisplayServer	*server = nil;

  NS_DURING
    {
      [NSApplication sharedApplication];
      server = GSCurrentServer();
    }
  NS_HANDLER
    {
      server = nil;
    }
  NS_ENDHANDLER

  if (nil == server)
    {
      SKIP("no display server available")
    }
  else
    {
      NSOpenGLPixelFormatAttribute attrs[] = {
	NSOpenGLPFAColorSize, 24,
	NSOpenGLPFAAlphaSize, 8,
	0
      };
      NSOpenGLPixelFormat  *pf;
      NSOpenGLContext	   *ctx;
      NSView		   *view;
      NSWindow		   *window;
      struct AndroidWindow *record;
      cairo_surface_t	   *cs = NULL;

      /* A 40x30 window with a 20x10 GL view at AppKit (5, 5).  The view's top
       * row is AppKit y 14, which is cairo row 30 - 15 = 15. */
      window = [[NSWindow alloc]
		 initWithContentRect: NSMakeRect(0, 0, 40, 30)
			   styleMask: NSBorderlessWindowMask
			     backing: NSBackingStoreBuffered
			       defer: NO];
      view = [[[NSView alloc]
		initWithFrame: NSMakeRect(5, 5, 20, 10)] autorelease];
      [[window contentView] addSubview: view];
      [window orderFront: nil];

      /* The whole window is painted opaque black first, so a pixel the
       * readback did not write is distinguishable from one it did. */
      [[window contentView] lockFocus];
      [[NSColor blackColor] set];
      NSRectFill(NSMakeRect(0, 0, 40, 30));
      [[window contentView] unlockFocus];
      [window flushWindow];

      record = (struct AndroidWindow *)
	[server windowDevice: [window windowNumber]];
      PASS(record != NULL && record->surface != nil,
	"the window has a cairo surface to composite from")
      if (record != NULL && record->surface != nil)
	{
	  cs = [record->surface surface];
	}
      PASS(cs != NULL, "the surface hands out its cairo surface")

      if (cs != NULL)
	{
	  cairo_surface_flush(cs);
	  PASS(pixelAt(cs, 10, 20) == 0xff000000u,
	    "the view's area is opaque black before any GL drawing")
	}

      pf = [[[NSOpenGLPixelFormat alloc]
	      initWithAttributes: attrs] autorelease];
      ctx = [[[NSOpenGLContext alloc] initWithFormat: pf
					shareContext: nil] autorelease];
      [ctx setView: view];
      [ctx makeCurrentContext];
      glViewport(0, 0, 20, 10);
      glClearColor(0.25f, 0.5f, 0.75f, 1.0f);
      glClear(GL_COLOR_BUFFER_BIT);
      glFinish();
      [ctx flushBuffer];

      if (cs != NULL)
	{
	  cairo_surface_flush(cs);

	  /* The view covers AppKit x 5..24, y 5..14, which is cairo rows
	   * 15..24 of a 30-high surface. */
	  PASS(nearColour(pixelAt(cs, 5, 15), 255, 64, 128, 191),
	    "the top left pixel of the view is the colour GL cleared to")
	  PASS(nearColour(pixelAt(cs, 24, 24), 255, 64, 128, 191),
	    "the bottom right pixel of the view is the colour GL cleared to")
	  PASS(nearColour(pixelAt(cs, 14, 20), 255, 64, 128, 191),
	    "a pixel in the middle of the view is the colour GL cleared to")

	  PASS(pixelAt(cs, 4, 20) == 0xff000000u,
	    "the pixel one column left of the view is untouched")
	  PASS(pixelAt(cs, 25, 20) == 0xff000000u,
	    "the pixel one column right of the view is untouched")
	  PASS(pixelAt(cs, 14, 14) == 0xff000000u,
	    "the pixel one row above the view is untouched")
	  PASS(pixelAt(cs, 14, 25) == 0xff000000u,
	    "the pixel one row below the view is untouched")

	  NSLog(@"view pixel = %08x", pixelAt(cs, 14, 20));
	}

      [NSOpenGLContext clearCurrentContext];
      [window close];
      [window release];
    }

  [arp release];
  END_SET("android GL readback")
  return 0;
}

#else

int
main(void)
{
  START_SET("android GL readback")
    SKIP("back is not built with the android+cairo backend and EGL")
  END_SET("android GL readback")
  return 0;
}

#endif
