#import <CoreText/CoreText.h>
#import <Foundation/Foundation.h>
#include "../../bridge.h"

static int s_index;

static int faceIndex(NSURL *url, NSString *postScriptName) {
    NSArray *faces = CFBridgingRelease(CTFontManagerCreateFontDescriptorsFromURL((__bridge CFURLRef)url));
    for (NSUInteger i = 0; i < faces.count; i++) {
        NSString *name = CFBridgingRelease(CTFontDescriptorCopyAttribute((__bridge CTFontDescriptorRef)faces[i], kCTFontNameAttribute));
        if ([name isEqualToString:postScriptName]) return (int)i;
    }
    return 0;
}

static CTFontRef baseFont(const char *family, int weight, int italic) {
    CTFontRef base = family && *family
        ? CTFontCreateWithName((__bridge CFStringRef)@(family), 12, NULL)
        : CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, 12, NULL);
    CTFontSymbolicTraits traits = (weight >= 600 ? kCTFontTraitBold : 0) | (italic ? kCTFontTraitItalic : 0);
    if (traits == 0) return base;
    CTFontRef styled = CTFontCreateCopyWithSymbolicTraits(base, 0, NULL, traits, traits);
    if (styled == NULL) return base;
    CFRelease(base);
    return styled;
}

static bool draws(CTFontRef font, NSString *character) {
    UniChar units[2];
    CGGlyph glyphs[2];
    [character getCharacters:units range:NSMakeRange(0, character.length)];
    return CTFontGetGlyphsForCharacters(font, units, glyphs, (CFIndex)character.length);
}

static bool hasOutlines(CTFontRef font) {
    CFArrayRef tags = CTFontCopyAvailableTables(font, kCTFontTableOptionNoOptions);
    if (tags == NULL) return false;
    bool found = false;
    for (CFIndex i = 0; i < CFArrayGetCount(tags) && !found; i++) {
        CTFontTableTag tag = (CTFontTableTag)(uintptr_t)CFArrayGetValueAtIndex(tags, i);
        found = tag == kCTFontTableGlyf || tag == kCTFontTableCFF || tag == 'CFF2';
    }
    CFRelease(tags);
    return found;
}

static bool readable(CTFontRef font, NSString *character) {
    if (font == NULL || !draws(font, character) || !hasOutlines(font)) return false;
    NSString *postScriptName = CFBridgingRelease(CTFontCopyPostScriptName(font));
    NSURL *url = CFBridgingRelease(CTFontCopyAttribute(font, kCTFontURLAttribute));
    return url != nil && ![postScriptName isEqualToString:@"LastResort"];
}

// Ranked as Ghostty's FreeType discovery ranks (src/font/discovery.zig Score): italic, then bold, then glyph count.
static CTFontRef readableFontFor(NSString *character, int weight, int italic) {
    NSDictionary *attributes = @{ (id)kCTFontCharacterSetAttribute: [NSCharacterSet characterSetWithCharactersInString:character] };
    CTFontDescriptorRef query = CTFontDescriptorCreateWithAttributes((__bridge CFDictionaryRef)attributes);
    NSArray *matches = CFBridgingRelease(CTFontDescriptorCreateMatchingFontDescriptors(query, NULL));
    CFRelease(query);
    CTFontRef best = NULL;
    long bestScore = -1;
    for (id match in matches) {
        CTFontRef font = CTFontCreateWithFontDescriptor((__bridge CTFontDescriptorRef)match, 12, NULL);
        CTFontSymbolicTraits traits = CTFontGetSymbolicTraits(font);
        long score = (long)(((traits & kCTFontTraitItalic) != 0) == (italic != 0)) << 17
            | (long)(((traits & kCTFontTraitBold) != 0) == (weight >= 600)) << 16
            | MIN(CTFontGetGlyphCount(font), 0xFFFF);
        if (score > bestScore && readable(font, character)) {
            if (best) CFRelease(best);
            best = font;
            bestScore = score;
        } else {
            CFRelease(font);
        }
    }
    return best;
}

static CTFontRef fontFor(NSString *character, int emoji, int weight, int italic, const char *family) {
    if (emoji) {
        CTFontRef color = CTFontCreateWithName(CFSTR("AppleColorEmoji"), 12, NULL);
        if (draws(color, character)) return color;
        CFRelease(color);
    }
    CTFontRef base = baseFont(family, weight, italic);
    CTFontRef found = CTFontCreateForString(base, (__bridge CFStringRef)character, CFRangeMake(0, (CFIndex)character.length));
    CFRelease(base);
    return found;
}

msString ionFindSystemFont(int codepoint, int emoji, int weight, int italic, const char *family) {
    s_index = 0;
    if (codepoint < 0 || codepoint > 0x10FFFF || (codepoint >= 0xD800 && codepoint <= 0xDFFF)) return MS_EMPTY_STRING;
    @autoreleasepool {
        UTF32Char scalar = (UTF32Char)codepoint;
        NSString *character = [[NSString alloc] initWithBytes:&scalar length:sizeof scalar encoding:NSUTF32LittleEndianStringEncoding];
        CTFontRef found = fontFor(character, emoji, weight, italic, family);
        if (!readable(found, character)) {
            if (found) CFRelease(found);
            found = readableFontFor(character, weight, italic);
        }
        if (found == NULL) return MS_EMPTY_STRING;
        NSString *postScriptName = CFBridgingRelease(CTFontCopyPostScriptName(found));
        NSURL *url = CFBridgingRelease(CTFontCopyAttribute(found, kCTFontURLAttribute));
        CFRelease(found);
        s_index = faceIndex(url, postScriptName);
        return msStringFromCStr(url.path.UTF8String);
    }
}

int ionSystemFontIndex(void) {
    return s_index;
}
