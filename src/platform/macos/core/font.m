#import <CoreText/CoreText.h>
#import <Foundation/Foundation.h>
#include "../../bridge.h"

static NSMutableDictionary<NSString *, NSArray<NSString *> *> *s_faceNames;

static int faceIndex(NSURL *url, NSString *postScriptName) {
    if (s_faceNames == nil) s_faceNames = [NSMutableDictionary dictionary];
    NSArray<NSString *> *names = s_faceNames[url.path];
    if (names == nil) {
        NSArray *faces = CFBridgingRelease(CTFontManagerCreateFontDescriptorsFromURL((__bridge CFURLRef)url));
        NSMutableArray<NSString *> *found = [NSMutableArray array];
        for (id face in faces) {
            NSString *name = CFBridgingRelease(CTFontDescriptorCopyAttribute((__bridge CTFontDescriptorRef)face, kCTFontNameAttribute));
            [found addObject:name ?: @""];
        }
        names = found;
        s_faceNames[url.path] = names;
    }
    NSUInteger index = [names indexOfObject:postScriptName];
    return index == NSNotFound ? 0 : (int)index;
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

static bool usable(CTFontRef font, NSString *character) {
    if (font == NULL || !draws(font, character)) return false;
    NSString *postScriptName = CFBridgingRelease(CTFontCopyPostScriptName(font));
    NSURL *url = CFBridgingRelease(CTFontCopyAttribute(font, kCTFontURLAttribute));
    return url != nil && ![postScriptName isEqualToString:@"LastResort"];
}

// Ranked as Ghostty's discovery ranks (src/font/discovery.zig Score): italic, then bold, then glyph count.
static long rank(CTFontRef font, int weight, int italic) {
    CTFontSymbolicTraits traits = CTFontGetSymbolicTraits(font);
    return (long)(((traits & kCTFontTraitItalic) != 0) == (italic != 0)) << 17
        | (long)(((traits & kCTFontTraitBold) != 0) == (weight >= 600)) << 16
        | MIN(CTFontGetGlyphCount(font), 0xFFFF);
}

static NSArray *rankedMatches(NSString *character, int weight, int italic) {
    NSDictionary *attributes = @{ (id)kCTFontCharacterSetAttribute: [NSCharacterSet characterSetWithCharactersInString:character] };
    CTFontDescriptorRef query = CTFontDescriptorCreateWithAttributes((__bridge CFDictionaryRef)attributes);
    NSArray *matches = CFBridgingRelease(CTFontDescriptorCreateMatchingFontDescriptors(query, NULL));
    CFRelease(query);
    NSMutableArray *ranked = [NSMutableArray array];
    for (id match in matches) {
        CTFontRef font = CTFontCreateWithFontDescriptor((__bridge CTFontDescriptorRef)match, 12, NULL);
        if (usable(font, character)) [ranked addObject:@[ @(rank(font, weight, italic)), (__bridge id)font ]];
        CFRelease(font);
    }
    [ranked sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {
        return [b[0] compare:a[0]];
    }];
    return ranked;
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

static NSMutableArray<NSString *> *s_paths;
static NSMutableArray<NSNumber *> *s_indices;

static void add(CTFontRef font) {
    NSString *postScriptName = CFBridgingRelease(CTFontCopyPostScriptName(font));
    NSURL *url = CFBridgingRelease(CTFontCopyAttribute(font, kCTFontURLAttribute));
    NSNumber *index = @(faceIndex(url, postScriptName));
    for (NSUInteger i = 0; i < s_paths.count; i++) {
        if ([s_paths[i] isEqualToString:url.path] && [s_indices[i] isEqualToNumber:index]) return;
    }
    [s_paths addObject:url.path];
    [s_indices addObject:index];
}

int ionFindSystemFonts(int codepoint, int emoji, int weight, int italic, const char *family) {
    s_paths = [NSMutableArray array];
    s_indices = [NSMutableArray array];
    if (codepoint < 0 || codepoint > 0x10FFFF || (codepoint >= 0xD800 && codepoint <= 0xDFFF)) return 0;
    @autoreleasepool {
        UTF32Char scalar = (UTF32Char)codepoint;
        NSString *character = [[NSString alloc] initWithBytes:&scalar length:sizeof scalar encoding:NSUTF32LittleEndianStringEncoding];
        CTFontRef first = fontFor(character, emoji, weight, italic, family);
        if (usable(first, character)) add(first);
        if (first) CFRelease(first);
        for (NSArray *entry in rankedMatches(character, weight, italic)) add((__bridge CTFontRef)entry[1]);
    }
    return (int)s_paths.count;
}

msString ionSystemFontPath(int i) {
    return msStringFromCStr(s_paths[(NSUInteger)i].UTF8String);
}

int ionSystemFontIndex(int i) {
    return s_indices[(NSUInteger)i].intValue;
}
