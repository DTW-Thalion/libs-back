/* An NSOpenGLContext on the android backend becomes current and reports an
 * OpenGL ES version.
 *
 * The drawable is an EGL pbuffer, so a context is current with no activity and
 * without the surface the compositor draws into: an activity is given one
 * surface and it has one producer, and ANativeWindow_lock fails with -22 while
 * an EGL window surface holds it.
 *
 * The class is looked up by name rather than included from Headers/android, so
 * that this file compiles and runs against a backend that has no GL support.
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
#include <string.h>

int
main(void)
{
  START_SET("android GL context")
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
	NSOpenGLPFADepthSize, 16,
	0
      };
      Class		   expected = NSClassFromString(@"AndroidGLContext");
      NSOpenGLPixelFormat *pf;
      NSOpenGLContext	  *ctx;
      NSView		  *view;
      NSWindow		  *window;
      const char	  *version = NULL;

      PASS(expected != Nil, "the backend defines AndroidGLContext")
      PASS(expected != Nil && [server glContextClass] == expected,
	"the server answers AndroidGLContext for its context class")

      pf = [[[NSOpenGLPixelFormat alloc]
	      initWithAttributes: attrs] autorelease];
      ctx = [[[NSOpenGLContext alloc] initWithFormat: pf
					shareContext: nil] autorelease];
      PASS(ctx != nil, "an NSOpenGLContext is created from the pixel format")
      PASS(ctx != nil && [ctx isKindOfClass: expected],
	"the context is the backend's own class")

      window = [[NSWindow alloc]
		 initWithContentRect: NSMakeRect(0, 0, 64, 48)
			   styleMask: NSBorderlessWindowMask
			     backing: NSBackingStoreBuffered
			       defer: NO];
      view = [[[NSView alloc]
		initWithFrame: NSMakeRect(0, 0, 64, 48)] autorelease];
      [[window contentView] addSubview: view];
      [window orderFront: nil];

      [ctx setView: view];
      PASS([ctx view] == view, "the context holds the view it was given")

      [ctx makeCurrentContext];
      PASS(ctx != nil && [NSOpenGLContext currentContext] == ctx,
	"the context that was made current is the current context")

      PASS(eglGetCurrentSurface(EGL_DRAW) != EGL_NO_SURFACE,
	"a drawable is current for the context")

      {
	EGLint pbWidth = 0;
	EGLint pbHeight = 0;

	eglQuerySurface(eglGetCurrentDisplay(), eglGetCurrentSurface(EGL_DRAW),
	  EGL_WIDTH, &pbWidth);
	eglQuerySurface(eglGetCurrentDisplay(), eglGetCurrentSurface(EGL_DRAW),
	  EGL_HEIGHT, &pbHeight);
	PASS(pbWidth == 64 && pbHeight == 48,
	  "the drawable is the size of the view it was made for")
      }

      version = (const char *)glGetString(GL_VERSION);
      PASS(version != NULL && strlen(version) > 0,
	"a current context reports a GL version string")
      PASS(version != NULL && strstr(version, "OpenGL ES") != NULL,
	"the version it reports is an OpenGL ES version")
      if (version != NULL)
	{
	  NSLog(@"GL_VERSION = %s", version);
	  NSLog(@"GL_RENDERER = %s", (const char *)glGetString(GL_RENDERER));
	}

      [NSOpenGLContext clearCurrentContext];
      PASS([NSOpenGLContext currentContext] == nil,
	"clearing the current context leaves none current")

      [window close];
      [window release];
    }

  [arp release];
  END_SET("android GL context")
  return 0;
}

#else

int
main(void)
{
  START_SET("android GL context")
    SKIP("back is not built with the android+cairo backend and EGL")
  END_SET("android GL context")
  return 0;
}

#endif
