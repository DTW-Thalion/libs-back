#!/usr/bin/env python3
"""Generate a fonts.conf for Android from /system/etc/fonts.xml.

Android ships the font files but not fontconfig, so nothing on the device maps
a family name to a file.  fonts.xml carries exactly the two things fontconfig
needs and cannot discover: which family is the default for a generic name
(sans-serif, serif, monospace), and the alias set that maps the names
applications actually ask for -- Helvetica, Arial, Times -- onto them.

The font files themselves are left to fontconfig's own scan of /system/fonts.
Writing them out here would freeze a list that changes with the platform.

Usage: mkfontsconf.py <fonts.xml> <output fonts.conf> [font dir] [cache dir]
"""
import sys
import xml.etree.ElementTree as ET

HEADER = """<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<!-- Generated from Android's /system/etc/fonts.xml.  Do not edit by hand. -->
<fontconfig>
  <dir>{fontdir}</dir>
  <cachedir>{cachedir}</cachedir>
"""

FOOTER = """  <config>
    <rescan><int>30</int></rescan>
  </config>
</fontconfig>
"""


def escape(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def alias_element(name, target, indent="  "):
    """A fontconfig alias: asking for `name` prefers `target`."""
    return (
        '{i}<alias binding="same">\n'
        '{i}  <family>{n}</family>\n'
        '{i}  <prefer><family>{t}</family></prefer>\n'
        '{i}</alias>\n'.format(i=indent, n=escape(name), t=escape(target))
    )


def postscript_name(psname, filename, indent="  "):
    """Give a file the PostScript name AppKit will ask for.

    FCFontEnumerator names a FACE from FC_POSTSCRIPT_NAME when the font has one
    (FCFontEnumerator.m:320), falling back to family plus style.  -availableFonts
    is built from those face names, and NSFont looks its default up there by
    name, so prepending a family is not enough: without this the family shows in
    -availableFontFamilies, NSFont still finds no font, and the typesetter
    raises "Glyph generation with no font".
    """
    return (
        '{i}<match target="scan">\n'
        '{i}  <test name="file" compare="eq"><string>{f}</string></test>\n'
        '{i}  <edit name="postscriptname" mode="assign"><string>{n}</string></edit>\n'
        '{i}</match>\n'.format(i=indent, f=escape(filename), n=escape(psname))
    )


def family_default(family, filename, indent="  "):
    """Bind a family name to the file fonts.xml names first for it.

    Without this the family name reaches fontconfig only through the file's own
    internal name, so a request for "sans-serif" matches nothing and fontconfig
    falls back to whatever sorts first -- which on this device is a bold face.
    """
    return (
        '{i}<match target="scan">\n'
        '{i}  <test name="file" compare="eq"><string>{f}</string></test>\n'
        '{i}  <edit name="family" mode="prepend"><string>{n}</string></edit>\n'
        '{i}</match>\n'.format(i=indent, f=escape(filename), n=escape(family))
    )


# The PostScript names AppKit asks for by default, and the Android family and
# face each should resolve to.  GNUstep's font roles default to Helvetica,
# Helvetica-Bold and Courier (libs-gui Source/NSFont.m), and NSFont looks a
# family up BY NAME in the enumerator's list -- an alias is not enough, because
# no font file on the device carries any of these names.
#
# (postscript name, android family, weight, style)
APPKIT_NAMES = [
    ("Helvetica",          "sans-serif", "400", "normal"),
    ("Helvetica-Bold",     "sans-serif", "700", "normal"),
    ("Helvetica-Oblique",  "sans-serif", "400", "italic"),
    ("Times-Roman",        "serif",      "400", "normal"),
    ("Times-Bold",         "serif",      "700", "normal"),
    ("Times-Italic",       "serif",      "400", "italic"),
    ("Courier",            "monospace",  "400", "normal"),
    ("Courier-Bold",       "monospace",  "700", "normal"),
]


def font_for(family, weight, style):
    """The file for a family's (weight, style) face, falling back to 400 normal.

    Returns (filename, exact) where exact says whether the requested face was
    found or the regular one was substituted.
    """
    fallback = None
    for f in family.findall("font"):
        name = (f.text or "").strip()
        if not name:
            continue
        if f.get("weight") == weight and f.get("style", "normal") == style:
            return name, True
        if f.get("weight") == "400" and f.get("style", "normal") == "normal" \
                and fallback is None:
            fallback = name
    return fallback, False


def first_regular_font(family):
    """The file for the family's regular, upright face, or None.

    fonts.xml lists a <font> per weight and style; weight 400 style normal is
    the regular face.  Falls back to the first font element when the family
    declares no 400/normal.
    """
    first = None
    for f in family.findall("font"):
        name = (f.text or "").strip()
        if not name:
            continue
        if first is None:
            first = name
        if f.get("weight") == "400" and f.get("style", "normal") == "normal":
            return name
    return first


def main():
    if len(sys.argv) < 3:
        sys.stderr.write(__doc__)
        return 2
    src, dst = sys.argv[1], sys.argv[2]
    fontdir = sys.argv[3] if len(sys.argv) > 3 else "/system/fonts"
    cachedir = sys.argv[4] if len(sys.argv) > 4 else "/data/local/tests/fontconfig/cache"

    root = ET.parse(src).getroot()

    named = [f for f in root.findall("family") if f.get("name")]
    if not named:
        sys.stderr.write("%s declares no named family; refusing to write a "
                         "configuration that would match nothing\n" % src)
        return 1

    aliases = []
    for a in root.findall("alias"):
        name, to = a.get("name"), a.get("to")
        if name and to:
            aliases.append((name, to))

    default = named[0].get("name")

    out = [HEADER.format(fontdir=escape(fontdir), cachedir=escape(cachedir))]

    out.append("  <!-- %d named families from fonts.xml, bound to their "
               "regular face -->\n" % len(named))
    bound = 0
    for fam in named:
        regular = first_regular_font(fam)
        if regular:
            out.append(family_default(fam.get("name"), "%s/%s" % (fontdir, regular)))
            bound += 1

    # The names AppKit asks for by default, bound onto real faces.
    byname = dict((f.get("name"), f) for f in named)
    out.append("  <!-- the PostScript names AppKit asks for -->\n")
    appkit = 0
    inexact = []
    unnamed = []
    claimed = {}          # file -> the PostScript name already assigned to it
    for ps, fam, weight, style in APPKIT_NAMES:
        family = byname.get(fam)
        if family is None:
            continue
        file, exact = font_for(family, weight, style)
        if file is None:
            continue
        path = "%s/%s" % (fontdir, file)

        # The family list is multi-valued, so every name can be prepended.
        out.append(family_default(ps, path))
        appkit += 1

        # A file has exactly ONE PostScript name, so the first claimant keeps
        # it.  Letting a later one overwrite would silently take the name away
        # from the earlier, more important role.
        if path in claimed:
            unnamed.append("%s (%s already carries the name %s)"
                           % (ps, file, claimed[path]))
        else:
            claimed[path] = ps
            out.append(postscript_name(ps, path))

        if not exact:
            inexact.append("%s (no %s/%s face in %s)" % (ps, weight, style, fam))

    out.append("  <!-- %d aliases from fonts.xml -->\n" % len(aliases))
    for name, to in aliases:
        out.append(alias_element(name, to))

    generics = ("sans-serif", "sans", "serif", "monospace", "system-ui")
    names = [f.get("name") for f in named]
    missing = [g for g in generics if g not in names]
    out.append("  <!-- generic families not named in fonts.xml, defaulting to "
               "%s -->\n" % default)
    for g in missing:
        out.append(alias_element(g, default))

    out.append(FOOTER)

    with open(dst, "w") as fh:
        fh.write("".join(out))

    sys.stderr.write("%s: %d named families (%d bound to a regular face), "
                     "%d AppKit names, %d aliases, %d generic fallbacks -> %s\n"
                     % (src, len(named), bound, appkit, len(aliases),
                        len(missing), dst))
    # Substitutions are reported rather than hidden: a name bound to the
    # regular face when a bold one was asked for will render at the wrong
    # weight, and that is a real limitation of the device's font set.
    for line in inexact:
        sys.stderr.write("  substituted the regular face for %s\n" % line)
    for line in unnamed:
        sys.stderr.write("  no PostScript name for %s\n" % line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
