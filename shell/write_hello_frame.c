/* write_hello_frame — CAD-protocol hello blit for the GTK shell.
 * Writes meta.bin + frame.raw + gen.txt under HALCODE_APP_STATE.
 *
 * Copyright (c) 2026 Sean Collins, 2 Paws Machine and Engineering. MIT.
 */
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define W 960
#define H 600
#define PITCH (W * 4)

static void put_px(uint8_t *pix, int x, int y, uint8_t r, uint8_t g, uint8_t b) {
    if (x < 0 || y < 0 || x >= W || y >= H) return;
    uint8_t *p = pix + (size_t)y * PITCH + (size_t)x * 4;
    p[0] = b;
    p[1] = g;
    p[2] = r;
    p[3] = 255;
}

static void fill_rect(uint8_t *pix, int x, int y, int w, int h,
                      uint8_t r, uint8_t g, uint8_t b) {
    int yy, xx;
    for (yy = y; yy < y + h; yy++)
        for (xx = x; xx < x + w; xx++)
            put_px(pix, xx, yy, r, g, b);
}

/* 5x7 block glyphs for a few letters. */
static const char *glyph(int ch) {
    switch (ch) {
    case 'H': return "10101""10101""11111""10101""10101""10101""10101";
    case 'A': return "01110""10001""10001""11111""10001""10001""10001";
    case 'L': return "10000""10000""10000""10000""10000""10000""11111";
    case 'C': return "01110""10001""10000""10000""10000""10001""01110";
    case 'O': return "01110""10001""10001""10001""10001""10001""01110";
    case 'D': return "11110""10001""10001""10001""10001""10001""11110";
    case 'E': return "11111""10000""10000""11110""10000""10000""11111";
    case '9': return "01110""10001""10001""01111""00001""10001""01110";
    case '0': return "01110""10001""10011""10101""11001""10001""01110";
    case ' ': return "00000""00000""00000""00000""00000""00000""00000";
    default:  return "11111""10001""00100""00100""00000""00100""00100";
    }
}

static void draw_text(uint8_t *pix, int x, int y, const char *s, int scale,
                      uint8_t r, uint8_t g, uint8_t b) {
    int i;
    for (i = 0; s[i]; i++) {
        const char *bits = glyph(s[i]);
        int row, col;
        for (row = 0; row < 7; row++)
            for (col = 0; col < 5; col++)
                if (bits[row * 5 + col] == '1')
                    fill_rect(pix, x + i * (5 + 1) * scale + col * scale,
                              y + row * scale, scale, scale, r, g, b);
    }
}

static int write_all(const char *path, const void *buf, size_t n) {
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return -1;
    size_t got = 0;
    while (got < n) {
        ssize_t w = write(fd, (const uint8_t *)buf + got, n - got);
        if (w <= 0) {
            close(fd);
            return -1;
        }
        got += (size_t)w;
    }
    close(fd);
    return 0;
}

int main(int argc, char **argv) {
    const char *dir = (argc > 1) ? argv[1] : getenv("HALCODE_APP_STATE");
    if (!dir || !dir[0]) dir = "/tmp/halcode_app";
    mkdir(dir, 0755);

    uint8_t *pix = (uint8_t *)malloc((size_t)PITCH * H);
    if (!pix) return 1;
    fill_rect(pix, 0, 0, W, H, 14, 18, 24);
    fill_rect(pix, 0, 0, W, 36, 14, 56, 58);
    fill_rect(pix, 48, 80, 864, 480, 22, 28, 38);
    fill_rect(pix, 48, 80, 864, 28, 26, 49, 51);
    draw_text(pix, 24, 10, "HALCODE 9000", 3, 0, 196, 198);
    draw_text(pix, 64, 88, "CHAT", 2, 232, 238, 248);
    draw_text(pix, 72, 160, "HELLO DESK", 4, 197, 203, 216);
    draw_text(pix, 72, 220, "APPDESK MDI", 3, 143, 223, 224);

    int32_t hdr[3] = {W, H, PITCH};
    char meta[600], frame[600], gen[600];
    snprintf(meta, sizeof meta, "%s/meta.bin", dir);
    snprintf(frame, sizeof frame, "%s/frame.raw", dir);
    snprintf(gen, sizeof gen, "%s/gen.txt", dir);
    if (write_all(meta, hdr, 12) != 0) return 1;
    if (write_all(frame, pix, (size_t)PITCH * H) != 0) return 1;
    if (write_all(gen, "1\n", 2) != 0) return 1;
    free(pix);
    fprintf(stderr, "hello frame %dx%d -> %s\n", W, H, dir);
    return 0;
}
