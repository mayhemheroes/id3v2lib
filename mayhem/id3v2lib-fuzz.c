/*
 * libFuzzer harness for id3v2lib.
 *
 * Ports the original app-style harness (a main() calling load_tag(argv[1]) on a file) to an
 * instrumented in-memory entry point: ID3v2_read_tag_from_buffer() runs the same ID3v2 tag-parsing
 * path on the fuzz input, as a sanitized libFuzzer target (so Mayhem gets edge coverage instead of a
 * black-box file runner). Preserves the old `id3v2lib-fuzz` target's surface.
 */
#include <limits.h>
#include <stddef.h>
#include <stdint.h>

#include "id3v2lib.h"

int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size)
{
    /*
     * Enforce the library's own precondition. ID3v2_read_tag_from_buffer() parses the 10-byte ID3v2
     * header with no length check (TagHeader_parse memcmp's the "ID3" magic immediately), so a buffer
     * shorter than the header reads out of bounds. The file-based ID3v2_read_tag() avoids this by
     * requiring a full ID3v2_TAG_HEADER_LENGTH read before parsing; mirror that here so the fuzzer
     * explores real tag parsing rather than getting stuck on the trivial sub-header overflow.
     */
    if (size < ID3v2_TAG_HEADER_LENGTH || size > (size_t)INT_MAX) return 0;
    ID3v2_Tag* tag = ID3v2_read_tag_from_buffer((const char*)data, (int)size);
    if (tag != NULL) ID3v2_Tag_free(tag);
    return 0;
}
