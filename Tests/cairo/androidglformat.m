/* The android backend answers a pixel format class, and the format it makes
 * carries the attributes it was given and matches an EGL pbuffer config.
 *
 * Every EGL config this platform reports is renderable by OpenGL ES 1, 2 and 3
 * and accepts both a pbuffer and a window, so the config asks for a pbuffer and
 * leaves the ES version to the context.  A pbuffer is what the backend uses
 * because an activity's surface has one producer: the compositor holds it, and
 * ANativeWindow_lock fails with -22 while an EGL window surface exists.
 *
 * The two backend selectors are declared here rather than included from
 * Headers/android, so that this file compiles and runs against a backend that
 * has no GL support at all.
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

@interface NSOpenGLPixelFormat (AndroidGL)
- (EGLConfig) eglConfigForDisplay: (EGLDisplay)eglDisplay;
- (EGLint) clientVersion;
@end

int
main(void)
{
  START_SET("android GL pixel format")
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
	NSOpenGLPFADoubleBuffer,
	NSOpenGLPFAColorSize, 24,
	NSOpenGLPFAAlphaSize, 8,
	NSOpenGLPFADepthSize, 16,
	0
      };
      Class		   expected = NSClassFromString(@"AndroidGLPixelFormat");
      NSOpenGLPixelFormat *pf;
      int		   value = 0;

      PASS(expected != Nil, "the backend defines AndroidGLPixelFormat")
      PASS(expected != Nil && [server glPixelFormatClass] == expected,
	"the server answers AndroidGLPixelFormat for its pixel format class")

      pf = [[[NSOpenGLPixelFormat alloc]
	      initWithAttributes: attrs] autorelease];
      PASS(pf != nil, "an NSOpenGLPixelFormat is created from attributes")
      PASS(pf != nil && [pf isKindOfClass: expected],
	"the pixel format is the backend's own class")

      [pf getValues: &value
	       forAttribute: NSOpenGLPFADepthSize
	   forVirtualScreen: 0];
      PASS(value == 16, "the depth size asked for is reported back")

      value = 0;
      [pf getValues: &value
	       forAttribute: NSOpenGLPFAAlphaSize
	   forVirtualScreen: 0];
      PASS(value == 8, "the alpha size asked for is reported back")

      PASS([pf respondsToSelector: @selector(clientVersion)]
	&& [pf clientVersion] == 2,
	"the default OpenGL ES version is 2")

      {
	EGLDisplay dpy = eglGetDisplay(EGL_DEFAULT_DISPLAY);
	EGLint	   major = 0, minor = 0;
	EGLConfig  config = NULL;
	EGLint	   surfaceType = 0;

	PASS(dpy != EGL_NO_DISPLAY, "EGL has a default display")
	PASS(eglInitialize(dpy, &major, &minor) == EGL_TRUE,
	  "the EGL display initialises")

	if ([pf respondsToSelector: @selector(eglConfigForDisplay:)])
	  {
	    config = [pf eglConfigForDisplay: dpy];
	  }
	PASS(config != NULL, "the pixel format matches an EGL config")

	if (config != NULL)
	  {
	    eglGetConfigAttrib(dpy, config, EGL_SURFACE_TYPE, &surfaceType);
	  }
	PASS((surfaceType & EGL_PBUFFER_BIT) != 0,
	  "the config it matched can make a pbuffer")

	eglTerminate(dpy);
      }
    }

  [arp release];
  END_SET("android GL pixel format")
  return 0;
}

#else

int
main(void)
{
  START_SET("android GL pixel format")
    SKIP("back is not built with the android+cairo backend and EGL")
  END_SET("android GL pixel format")
  return 0;
}

#endif
