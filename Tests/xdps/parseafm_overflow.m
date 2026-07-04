/* Regression test for the tokenizers in Source/xdps/parseAFM.c.
 *
 * token() and linetoken() copied characters into the fixed MAX_NAME (4096)
 * byte "ident" buffer with no bound, so a single token or line longer than
 * MAX_NAME overran the heap allocation (confirmed with AddressSanitizer,
 * writing at parseAFM.c token()).  A token longer than the buffer must instead
 * be truncated to MAX_NAME-1 characters.
 *
 * parseAFM.c is plain C, so this compiles the source in directly and runs on
 * every backend.
 */
#import <Foundation/Foundation.h>
#import "Testing.h"

#include "xdps/parseAFM.c"
#undef BOOL
#undef TRUE
#undef FALSE

#define OVERLONG 5000	/* > MAX_NAME (4096) */

int
main(void)
{
  /* token(): an over-long FontName value. */
  START_SET("token truncates an over-long token")
    FILE	*fp = tmpfile();
    AFMFontInfo	*fi = NULL;
    int		i;

    if (fp == NULL)
      {
	SKIP("could not create a temporary file")
      }
    else
      {
	fputs("StartFontMetrics 2.0\nFontName ", fp);
	for (i = 0; i < OVERLONG; i++)
	  {
	    fputc('A', fp);
	  }
	fputs("\nStartCharMetrics 0\nEndCharMetrics\nEndFontMetrics\n", fp);
	rewind(fp);
	AFMParseFile(fp, &fi, AFM_GM);
	fclose(fp);

	PASS(fi != NULL && fi->gfi != NULL && fi->gfi->fontName != NULL
	  && strlen(fi->gfi->fontName) == MAX_NAME - 1,
	  "an over-long token is truncated to MAX_NAME-1, not overflowed");
      }
  END_SET("token truncates an over-long token")

  /* linetoken(): an over-long FullName line. */
  START_SET("linetoken truncates an over-long line")
    FILE	*fp = tmpfile();
    AFMFontInfo	*fi = NULL;
    int		i;

    if (fp == NULL)
      {
	SKIP("could not create a temporary file")
      }
    else
      {
	fputs("StartFontMetrics 2.0\nFullName ", fp);
	for (i = 0; i < OVERLONG; i++)
	  {
	    fputc('B', fp);
	  }
	fputs("\nStartCharMetrics 0\nEndCharMetrics\nEndFontMetrics\n", fp);
	rewind(fp);
	AFMParseFile(fp, &fi, AFM_GM);
	fclose(fp);

	PASS(fi != NULL && fi->gfi != NULL && fi->gfi->fullName != NULL
	  && strlen(fi->gfi->fullName) == MAX_NAME - 1,
	  "an over-long line is truncated to MAX_NAME-1, not overflowed");
      }
  END_SET("linetoken truncates an over-long line")

  return 0;
}
