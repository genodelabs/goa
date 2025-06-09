#include <string.h>
#include <stdio.h>

extern unsigned int decode_base_64(
    char *dest_ptr,
    unsigned int dest_len,
    const char *source_ptr,
    unsigned int source_len
);

int main(int argc, char **argv) {
    const char *encoded = "YWxsIHlvdXIgYmFzZSBhcmUgYmVsb25nIHRvIHVz";
    char buf[200];

    size_t len = decode_base_64(buf, sizeof(buf), encoded, strlen(encoded));
    buf[len] = 0;
    puts(buf);

    return 0;
}
