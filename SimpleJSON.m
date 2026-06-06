// SimpleJSON.m
// Recursive-descent JSON parser. Handles objects, arrays, strings (with
// full escape processing), numbers (int + float), booleans, and null.

#import "SimpleJSON.h"
#include <stdlib.h>
#include <string.h>

// ─── Parser state ─────────────────────────────────────────────────────────────

typedef struct {
    const unsigned char *bytes;
    NSUInteger           pos;
    NSUInteger           len;
} FNParser;

static void     fn_skip_ws(FNParser *p);
static id       fn_value(FNParser *p);
static NSString *fn_string(FNParser *p);
static NSNumber *fn_number(FNParser *p);
static NSDictionary *fn_object(FNParser *p);
static NSArray  *fn_array(FNParser *p);
static id       fn_literal(FNParser *p, const char *lit, id val);

// ─── Whitespace ───────────────────────────────────────────────────────────────

static void fn_skip_ws(FNParser *p) {
    while (p->pos < p->len) {
        unsigned char c = p->bytes[p->pos];
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r')
            p->pos++;
        else
            break;
    }
}

// ─── Top-level value dispatcher ───────────────────────────────────────────────

static id fn_value(FNParser *p) {
    fn_skip_ws(p);
    if (p->pos >= p->len) return nil;

    unsigned char c = p->bytes[p->pos];
    if (c == '{') return fn_object(p);
    if (c == '[') return fn_array(p);
    if (c == '"') return fn_string(p);
    if (c == 't') return fn_literal(p, "true",  [NSNumber numberWithBool:YES]);
    if (c == 'f') return fn_literal(p, "false", [NSNumber numberWithBool:NO]);
    if (c == 'n') return fn_literal(p, "null",  [NSNull null]);
    if (c == '-' || (c >= '0' && c <= '9')) return fn_number(p);
    return nil;
}

// ─── Literal (true / false / null) ───────────────────────────────────────────

static id fn_literal(FNParser *p, const char *lit, id val) {
    NSUInteger litLen = strlen(lit);
    if (p->pos + litLen > p->len) return nil;
    for (NSUInteger i = 0; i < litLen; i++) {
        if (p->bytes[p->pos + i] != (unsigned char)lit[i]) return nil;
    }
    p->pos += litLen;
    return val;
}

// ─── String ───────────────────────────────────────────────────────────────────

static NSString *fn_string(FNParser *p) {
    if (p->pos >= p->len || p->bytes[p->pos] != '"') return nil;
    p->pos++; // skip opening "

    // Collect raw UTF-8 bytes into a buffer
    NSMutableData *buf = [NSMutableData dataWithCapacity:64];

    while (p->pos < p->len) {
        unsigned char c = p->bytes[p->pos];

        if (c == '"') {
            p->pos++;
            break;
        }

        if (c == '\\') {
            p->pos++;
            if (p->pos >= p->len) return nil;
            unsigned char esc = p->bytes[p->pos];
            p->pos++;

            switch (esc) {
                case '"': case '\\': case '/': {
                    [buf appendBytes:&esc length:1];
                    break;
                }
                case 'n': { unsigned char ch = '\n'; [buf appendBytes:&ch length:1]; break; }
                case 'r': { unsigned char ch = '\r'; [buf appendBytes:&ch length:1]; break; }
                case 't': { unsigned char ch = '\t'; [buf appendBytes:&ch length:1]; break; }
                case 'b': { unsigned char ch = '\b'; [buf appendBytes:&ch length:1]; break; }
                case 'f': { unsigned char ch = '\f'; [buf appendBytes:&ch length:1]; break; }
                case 'u': {
                    // \uXXXX — encode codepoint as UTF-8
                    if (p->pos + 4 > p->len) return nil;
                    char hex[5];
                    memcpy(hex, p->bytes + p->pos, 4);
                    hex[4] = '\0';
                    unsigned int cp = (unsigned int)strtoul(hex, NULL, 16);
                    p->pos += 4;
                    if (cp < 0x80) {
                        unsigned char b = (unsigned char)cp;
                        [buf appendBytes:&b length:1];
                    } else if (cp < 0x800) {
                        unsigned char b[2] = {
                            (unsigned char)(0xC0 | (cp >> 6)),
                            (unsigned char)(0x80 | (cp & 0x3F))
                        };
                        [buf appendBytes:b length:2];
                    } else {
                        unsigned char b[3] = {
                            (unsigned char)(0xE0 | (cp >> 12)),
                            (unsigned char)(0x80 | ((cp >> 6) & 0x3F)),
                            (unsigned char)(0x80 | (cp & 0x3F))
                        };
                        [buf appendBytes:b length:3];
                    }
                    break;
                }
                default: {
                    // Unknown escape — pass through as-is
                    [buf appendBytes:&esc length:1];
                    break;
                }
            }
        } else {
            // Raw byte — multi-byte UTF-8 sequences pass through unchanged
            [buf appendBytes:&c length:1];
            p->pos++;
        }
    }

    return [[[NSString alloc] initWithData:buf
                                  encoding:NSUTF8StringEncoding] autorelease];
}

// ─── Number ───────────────────────────────────────────────────────────────────

static NSNumber *fn_number(FNParser *p) {
    NSUInteger start = p->pos;
    BOOL isFloat = NO;

    if (p->pos < p->len && p->bytes[p->pos] == '-') p->pos++;

    while (p->pos < p->len && p->bytes[p->pos] >= '0' && p->bytes[p->pos] <= '9')
        p->pos++;

    if (p->pos < p->len && p->bytes[p->pos] == '.') {
        isFloat = YES;
        p->pos++;
        while (p->pos < p->len && p->bytes[p->pos] >= '0' && p->bytes[p->pos] <= '9')
            p->pos++;
    }

    if (p->pos < p->len && (p->bytes[p->pos] == 'e' || p->bytes[p->pos] == 'E')) {
        isFloat = YES;
        p->pos++;
        if (p->pos < p->len && (p->bytes[p->pos] == '+' || p->bytes[p->pos] == '-'))
            p->pos++;
        while (p->pos < p->len && p->bytes[p->pos] >= '0' && p->bytes[p->pos] <= '9')
            p->pos++;
    }

    NSString *s = [[[NSString alloc] initWithBytes:p->bytes + start
                                            length:p->pos - start
                                          encoding:NSUTF8StringEncoding] autorelease];
    if (isFloat)
        return [NSNumber numberWithDouble:[s doubleValue]];
    else
        return [NSNumber numberWithLongLong:[s longLongValue]];
}

// ─── Object ───────────────────────────────────────────────────────────────────

static NSDictionary *fn_object(FNParser *p) {
    if (p->pos >= p->len || p->bytes[p->pos] != '{') return nil;
    p->pos++;

    NSMutableDictionary *dict = [NSMutableDictionary dictionary];

    fn_skip_ws(p);
    if (p->pos < p->len && p->bytes[p->pos] == '}') { p->pos++; return dict; }

    while (p->pos < p->len) {
        fn_skip_ws(p);
        NSString *key = fn_string(p);
        if (!key) return nil;

        fn_skip_ws(p);
        if (p->pos >= p->len || p->bytes[p->pos] != ':') return nil;
        p->pos++;

        id val = fn_value(p);
        if (val == nil) return nil;

        [dict setObject:val forKey:key];

        fn_skip_ws(p);
        if (p->pos >= p->len) break;
        if (p->bytes[p->pos] == '}') { p->pos++; return dict; }
        if (p->bytes[p->pos] == ',') { p->pos++; continue; }
        return nil;
    }
    return dict;
}

// ─── Array ────────────────────────────────────────────────────────────────────

static NSArray *fn_array(FNParser *p) {
    if (p->pos >= p->len || p->bytes[p->pos] != '[') return nil;
    p->pos++;

    NSMutableArray *arr = [NSMutableArray array];

    fn_skip_ws(p);
    if (p->pos < p->len && p->bytes[p->pos] == ']') { p->pos++; return arr; }

    while (p->pos < p->len) {
        id val = fn_value(p);
        if (val == nil) return nil;
        [arr addObject:val];

        fn_skip_ws(p);
        if (p->pos >= p->len) break;
        if (p->bytes[p->pos] == ']') { p->pos++; return arr; }
        if (p->bytes[p->pos] == ',') { p->pos++; continue; }
        return nil;
    }
    return arr;
}

// ─── Public entry point ───────────────────────────────────────────────────────

id FNParseJSON(NSData *data, NSError **outError) {
    if (!data || [data length] == 0) return nil;
    FNParser p;
    p.bytes = (const unsigned char *)[data bytes];
    p.pos   = 0;
    p.len   = [data length];
    return fn_value(&p);
}
