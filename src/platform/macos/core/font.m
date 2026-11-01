#import <CoreText/CoreText.h>
#import <Foundation/Foundation.h>
#include "../../bridge.h"

static uint32_t bigEndian(const uint8_t *bytes, NSUInteger at, NSUInteger width) {
    uint32_t value = 0;
    for (NSUInteger i = 0; i < width; i++) value = value << 8 | bytes[at + i];
    return value;
}

static NSString *postScriptName(NSData *name) {
    const uint8_t *bytes = name.bytes;
    if (name.length < 6) return nil;
    NSUInteger count = bigEndian(bytes, 2, 2), strings = bigEndian(bytes, 4, 2);
    for (NSUInteger i = 0; i < count && 6 + 12 * (i + 1) <= name.length; i++) {
        NSUInteger record = 6 + 12 * i;
        uint32_t platform = bigEndian(bytes, record, 2), nameId = bigEndian(bytes, record + 6, 2);
        NSUInteger length = bigEndian(bytes, record + 8, 2), at = strings + bigEndian(bytes, record + 10, 2);
        if (nameId != 6 || (platform != 1 && platform != 3) || at + length > name.length) continue;
        NSData *text = [name subdataWithRange:NSMakeRange(at, length)];
        return [[NSString alloc] initWithData:text encoding:platform == 3 ? NSUTF16BigEndianStringEncoding : NSMacOSRomanStringEncoding];
    }
    return nil;
}

static NSString *facePostScriptName(NSData *file, NSUInteger face) {
    const uint8_t *bytes = file.bytes;
    if (face + 12 > file.length) return nil;
    NSUInteger tables = bigEndian(bytes, face + 4, 2);
    for (NSUInteger i = 0; i < tables && face + 12 + 16 * (i + 1) <= file.length; i++) {
        NSUInteger record = face + 12 + 16 * i;
        if (bigEndian(bytes, record, 4) != kCTFontTableName) continue;
        NSUInteger at = bigEndian(bytes, record + 8, 4), length = bigEndian(bytes, record + 12, 4);
        return at + length <= file.length ? postScriptName([file subdataWithRange:NSMakeRange(at, length)]) : nil;
    }
    return nil;
}

static NSMutableDictionary<NSString *, NSArray *> *s_faceNames;

static NSArray *faceNames(NSURL *url) {
    if (s_faceNames == nil) s_faceNames = [NSMutableDictionary dictionary];
    NSArray *names = s_faceNames[url.path];
    if (names != nil) return names;
    NSData *file = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:NULL];
    const uint8_t *bytes = file.bytes;
    NSMutableArray *found = [NSMutableArray array];
    if (file.length >= 12 && bigEndian(bytes, 0, 4) == 'ttcf') {
        NSUInteger faces = bigEndian(bytes, 8, 4);
        for (NSUInteger i = 0; i < faces && 12 + 4 * (i + 1) <= file.length; i++) {
            [found addObject:facePostScriptName(file, bigEndian(bytes, 12 + 4 * i, 4)) ?: [NSNull null]];
        }
    } else if (file != nil) {
        [found addObject:facePostScriptName(file, 0) ?: [NSNull null]];
    }
    s_faceNames[url.path] = found;
    return found;
}

static int faceIndex(NSURL *url, CTFontRef font) {
    NSArray *names = faceNames(url);
    if (names.count == 1) return 0;
    NSData *table = CFBridgingRelease(CTFontCopyTable(font, kCTFontTableName, kCTFontTableOptionNoOptions));
    NSString *name = table ? postScriptName(table) : nil;
    NSUInteger index = name ? [names indexOfObject:name] : NSNotFound;
    return index == NSNotFound ? -1 : (int)index;
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
    NSURL *url = CFBridgingRelease(CTFontCopyAttribute(font, kCTFontURLAttribute));
    int face = faceIndex(url, font);
    if (face < 0) return;
    NSNumber *index = @(face);
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

int ionRegisterFont(const char *path) {
    NSURL *url = [NSURL fileURLWithPath:@(path)];
    CFErrorRef error = NULL;
    if (CTFontManagerRegisterFontsForURL((__bridge CFURLRef)url, kCTFontManagerScopeProcess, &error)) return 1;
    BOOL already = CFErrorGetCode(error) == kCTFontManagerErrorAlreadyRegistered;
    CFRelease(error);
    return already ? 1 : 0;
}
