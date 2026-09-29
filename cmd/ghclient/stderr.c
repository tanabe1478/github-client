#include <moonbit.h>
#include <stdint.h>
#include <stdio.h>

// Writes one line to stderr, converting the MoonBit UTF-16 string to UTF-8.
void ghclient_eprintln(moonbit_string_t text) {
  int32_t length = Moonbit_array_length(text);
  for (int32_t i = 0; i < length; ++i) {
    uint32_t c = text[i];
    if (c >= 0xD800 && c <= 0xDBFF && i + 1 < length) {
      uint32_t low = text[i + 1];
      if (low >= 0xDC00 && low <= 0xDFFF) {
        c = 0x10000 + ((c - 0xD800) << 10) + (low - 0xDC00);
        ++i;
      }
    }
    if (c < 0x80) {
      fputc((int)c, stderr);
    } else if (c < 0x800) {
      fputc(0xC0 | (c >> 6), stderr);
      fputc(0x80 | (c & 0x3F), stderr);
    } else if (c < 0x10000) {
      fputc(0xE0 | (c >> 12), stderr);
      fputc(0x80 | ((c >> 6) & 0x3F), stderr);
      fputc(0x80 | (c & 0x3F), stderr);
    } else {
      fputc(0xF0 | (c >> 18), stderr);
      fputc(0x80 | ((c >> 12) & 0x3F), stderr);
      fputc(0x80 | ((c >> 6) & 0x3F), stderr);
      fputc(0x80 | (c & 0x3F), stderr);
    }
  }
  fputc('\n', stderr);
}
