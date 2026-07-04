/* Tests for the Adobe AFM font-metrics parser in Source/xdps/parseAFM.c.
 *
 * parseAFM.c is plain C (stdio only) with no X11, Display PostScript or
 * Foundation dependency, so this test compiles the source in directly and runs
 * on every backend with no per-backend guard.
 */
#import <Foundation/Foundation.h>
#import "Testing.h"

/* parseAFM.c re-#defines BOOL/TRUE/FALSE as macros; include it after Foundation
 * and undo them so they cannot leak into the test body. */
#include "xdps/parseAFM.c"
#undef BOOL
#undef TRUE
#undef FALSE

static const char *afm =
"StartFontMetrics 2.0\n"
"Comment Generated test fixture\n"
"FontName Test-Roman\n"
"FullName Test Roman Font\n"
"FamilyName Test\n"
"Weight Medium\n"
"ItalicAngle -12.5\n"
"IsFixedPitch false\n"
"FontBBox -100 -200 1000 900\n"
"UnderlinePosition -75\n"
"UnderlineThickness 50\n"
"EncodingScheme AdobeStandardEncoding\n"
"CapHeight 700\n"
"XHeight 500\n"
"Ascender 750\n"
"Descender -250\n"
"StartCharMetrics 2\n"
"C 32 ; WX 250 ; N space ; B 0 0 0 0 ;\n"
"C 65 ; WX 722 ; N A ; B 15 0 706 674 ;\n"
"EndCharMetrics\n"
"EndFontMetrics\n";

int
main(void)
{
  START_SET("recognize keyword table")
    int	i;
    int	n = (int)NOPE;
    int	sorted = 1;
    int	roundtrip = 1;

    /* The binary search in recognize() requires the keyword table to be in
     * strict lexicographic order. */
    for (i = 0; i < n - 1; i++)
      {
	if (strcmp(keyStrings[i], keyStrings[i + 1]) >= 0)
	  {
	    sorted = 0;
	  }
      }
    PASS(sorted == 1, "keyStrings is in strict lexicographic order");

    /* Every keyword must map back to its own enum position. */
    for (i = 0; i < n; i++)
      {
	if ((int)recognize(keyStrings[i]) != i)
	  {
	    roundtrip = 0;
	  }
      }
    PASS(roundtrip == 1,
      "recognize() maps each keyword to its parseKey position");

    PASS((int)recognize("NotAnAFMKeyword") == (int)NOPE,
      "recognize() returns NOPE for an unknown keyword");
    PASS((int)recognize("") == (int)NOPE,
      "recognize() returns NOPE for the empty string");
  END_SET("recognize keyword table")

  START_SET("AFMParseFile fixture")
    FILE		*fp = tmpfile();
    AFMFontInfo		*fi = NULL;
    int			rc;

    if (fp == NULL)
      {
	SKIP("could not create a temporary file")
      }
    else
      {
	fwrite(afm, 1, strlen(afm), fp);
	rewind(fp);
	rc = AFMParseFile(fp, &fi, AFM_GM);
	fclose(fp);

	PASS(rc == afm_ok, "a well-formed AFM parses without error");
	PASS(fi != NULL, "a font-info record is returned");

	if (fi != NULL && fi->gfi != NULL)
	  {
	    AFMGlobalFontInfo *g = fi->gfi;

	    PASS(g->afmVersion && 0 == strcmp(g->afmVersion, "2.0"),
	      "StartFontMetrics version is parsed");
	    PASS(g->fontName && 0 == strcmp(g->fontName, "Test-Roman"),
	      "FontName is parsed with token()");
	    PASS(g->fullName && 0 == strcmp(g->fullName, "Test Roman Font"),
	      "FullName is parsed to end of line with linetoken()");
	    PASS(g->familyName && 0 == strcmp(g->familyName, "Test"),
	      "FamilyName is parsed");
	    PASS(g->weight && 0 == strcmp(g->weight, "Medium"),
	      "Weight is parsed");
	    PASS(g->italicAngle > -12.51 && g->italicAngle < -12.49,
	      "ItalicAngle is parsed as a float");
	    PASS(g->isFixedPitch == 0, "IsFixedPitch false becomes 0");
	    PASS(g->fontBBox.llx == -100 && g->fontBBox.lly == -200
	      && g->fontBBox.urx == 1000 && g->fontBBox.ury == 900,
	      "FontBBox parses four signed integers");
	    PASS(g->underlinePosition == -75 && g->underlineThickness == 50,
	      "underline position and thickness are parsed");
	    PASS(g->encodingScheme
	      && 0 == strcmp(g->encodingScheme, "AdobeStandardEncoding"),
	      "EncodingScheme is parsed");
	    PASS(g->capHeight == 700 && g->xHeight == 500
	      && g->ascender == 750 && g->descender == -250,
	      "cap height, x height, ascender and descender are parsed");
	  }
	else
	  {
	    PASS(0, "global font info was allocated");
	  }

	if (fi != NULL)
	  {
	    PASS(fi->numOfChars == 2,
	      "the StartCharMetrics count is honoured");
	  }
	if (fi != NULL && fi->cmi != NULL && fi->numOfChars == 2)
	  {
	    AFMCharMetricInfo *m = fi->cmi;

	    PASS(m[0].code == 32 && m[0].wx == 250
	      && m[0].name && 0 == strcmp(m[0].name, "space"),
	      "first char metric: code, width and name");
	    PASS(m[0].charBBox.llx == 0 && m[0].charBBox.urx == 0,
	      "first char metric: bounding box");
	    PASS(m[1].code == 65 && m[1].wx == 722
	      && m[1].name && 0 == strcmp(m[1].name, "A"),
	      "second char metric: code, width and name");
	    PASS(m[1].charBBox.llx == 15 && m[1].charBBox.lly == 0
	      && m[1].charBBox.urx == 706 && m[1].charBBox.ury == 674,
	      "second char metric: bounding box");
	  }
	else
	  {
	    PASS(0, "character metrics were parsed");
	  }
      }
  END_SET("AFMParseFile fixture")

  return 0;
}
