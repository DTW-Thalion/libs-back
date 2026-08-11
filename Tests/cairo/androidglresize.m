/* A GL view that changes size gets a pbuffer of the new size, and the pixels it
 * composites cover the frame it has now rather than the one it had.
 *
 * A pbuffer cannot be resized, so -update replaces it.  A stale one leaves the
 * window showing GL content at the size the view used to be.
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

/* The size of the drawable the context has current. */
static void
currentPbufferSize(EGLint *outWidth, EGLint *outHeight)
{
  EGLDisplay dpy = eglGetCurrentDisplay();
  EGLSurface surf = eglGetCurrentSurface(EGL_DRAW);

  *outWidth = 0;
  *outHeight = 0;
  if (dpy == EGL_NO_DISPLAY || surf == EGL_NO_SURFACE)
    {
      return;
    }
  eglQuerySurface(dpy, surf, EGL_WIDTH, outWidth);
  eglQuerySurface(dpy, surf, EGL_HEIGHT, outHeight);
}

int
main(void)
{
  START_SET("android GL resize")
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
      EGLint		    pbWidth = 0;
      EGLint		    pbHeight = 0;

      window = [[NSWindow alloc]
		 initWithContentRect: NSMakeRect(0, 0, 40, 30)
			   styleMask: NSBorderlessWindowMask
			     backing: NSBackingStoreBuffered
			       defer: NO];
      view = [[[NSView alloc]
		initWithFrame: NSMakeRect(0, 0, 10, 10)] autorelease];
      [[window contentView] addSubview: view];
      [window orderFront: nil];

      [[window contentView] lockFocus];
      [[NSColor blackColor] set];
      NSRectFill(NSMakeRect(0, 0, 40, 30));
      [[window contentView] unlockFocus];
      [window flushWindow];

      record = (struct AndroidWindow *)
	[server windowDevice: [window windowNumber]];
      if (record != NULL && record->surface != nil)
	{
	  cs = [record->surface surface];
	}
      PASS(cs != NULL, "the window has a cairo surface")

      pf = [[[NSOpenGLPixelFormat alloc]
	      initWithAttributes: attrs] autorelease];
      ctx = [[[NSOpenGLContext alloc] initWithFormat: pf
					shareContext: nil] autorelease];
      [ctx setView: view];
      [ctx makeCurrentContext];

      currentPbufferSize(&pbWidth, &pbHeight);
      PASS(pbWidth == 10 && pbHeight == 10,
	"the drawable is the size of the view it was made for")

      [view setFrame: NSMakeRect(0, 0, 30, 20)];
      [ctx update];
      [ctx makeCurrentContext];

      currentPbufferSize(&pbWidth, &pbHeight);
      PASS(pbWidth == 30 && pbHeight == 20,
	"after -update the drawable is the size the view became")

      glViewport(0, 0, 30, 20);
      glClearColor(1.0f, 0.0f, 0.0f, 1.0f);
      glClear(GL_COLOR_BUFFER_BIT);
      glFinish();
      [ctx flushBuffer];

      if (cs != NULL)
	{
	  cairo_surface_flush(cs);

	  /* The view now covers AppKit x 0..29, y 0..19, which is cairo rows
	   * 10..29 of a 30-high surface. */
	  PASS(nearColour(pixelAt(cs, 29, 29), 255, 255, 0, 0),
	    "the bottom right corner of the grown view is red")
	  PASS(nearColour(pixelAt(cs, 29, 10), 255, 255, 0, 0),
	    "the top right corner of the grown view is red")
	  PASS(nearColour(pixelAt(cs, 0, 10), 255, 255, 0, 0),
	    "the top left corner of the grown view is red")
	  PASS(pixelAt(cs, 30, 20) == 0xff000000u,
	    "the pixel one column beyond the grown view is untouched")
	  PASS(pixelAt(cs, 29, 9) == 0xff000000u,
	    "the pixel one row above the grown view is untouched")
	}

      [NSOpenGLContext clearCurrentContext];
      [window close];
      [window release];
    }

  [arp release];
  END_SET("android GL resize")
  return 0;
}

#else

int
main(void)
{
  START_SET("android GL resize")
    SKIP("back is not built with the android+cairo backend and EGL")
  END_SET("android GL resize")
  return 0;
}

#endif
