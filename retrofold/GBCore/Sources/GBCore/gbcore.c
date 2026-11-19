// RetroFold : l'interface de gbcore.h, au-dessus de SameBoy.
#include "gbcore.h"
#include "gb.h"
#include "bootroms.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

#define RING (1 << 15)  // échantillons stéréo (environ 0,7 s à 48 kHz)

struct gbk {
    GB_gameboy_t *gb;
    uint32_t pixels[256 * 224];
    uint8_t *rom;
    int16_t ring[RING * 2];
    _Atomic size_t write_pos;
    _Atomic size_t read_pos;
};

static uint32_t encode(GB_gameboy_t *gb, uint8_t r, uint8_t g, uint8_t b) {
    (void)gb;
    // En mémoire : R, G, B, X.
    return (uint32_t)r | ((uint32_t)g << 8) | ((uint32_t)b << 16) | 0xFF000000u;
}

static void sample(GB_gameboy_t *gb, GB_sample_t *s) {
    gbk_t *k = GB_get_user_data(gb);
    size_t w = atomic_load_explicit(&k->write_pos, memory_order_relaxed);
    size_t r = atomic_load_explicit(&k->read_pos, memory_order_acquire);
    if (w - r >= RING) return;  // plein : on perd l'échantillon plutôt que de bloquer
    size_t i = (w % RING) * 2;
    k->ring[i] = s->left;
    k->ring[i + 1] = s->right;
    atomic_store_explicit(&k->write_pos, w + 1, memory_order_release);
}

static void boot(GB_gameboy_t *gb, GB_boot_rom_t type) {
    switch (type) {
        case GB_BOOT_ROM_CGB_0:
        case GB_BOOT_ROM_CGB:
        case GB_BOOT_ROM_CGB_E:
        case GB_BOOT_ROM_AGB_0:
        case GB_BOOT_ROM_AGB:
            GB_load_boot_rom_from_buffer(gb, cgb_boot_bin, sizeof(cgb_boot_bin));
            break;
        default:
            GB_load_boot_rom_from_buffer(gb, dmg_boot_bin, sizeof(dmg_boot_bin));
            break;
    }
}

gbk_t *gbk_create(int color, unsigned sample_rate) {
    gbk_t *k = calloc(1, sizeof(gbk_t));
    if (!k) return NULL;
    k->gb = GB_init(GB_alloc(), color ? GB_MODEL_CGB_E : GB_MODEL_DMG_B);
    GB_set_user_data(k->gb, k);
    GB_set_boot_rom_load_callback(k->gb, boot);
    GB_set_pixels_output(k->gb, k->pixels);
    GB_set_rgb_encode_callback(k->gb, encode);
    GB_set_color_correction_mode(k->gb, GB_COLOR_CORRECTION_MODERN_BALANCED);
    GB_set_sample_rate(k->gb, sample_rate);
    GB_apu_set_sample_callback(k->gb, sample);
    GB_set_highpass_filter_mode(k->gb, GB_HIGHPASS_ACCURATE);
    boot(k->gb, color ? GB_BOOT_ROM_CGB : GB_BOOT_ROM_DMG);
    return k;
}

void gbk_destroy(gbk_t *k) {
    if (!k) return;
    GB_free(k->gb);
    GB_dealloc(k->gb);
    free(k->rom);
    free(k);
}

void gbk_load_rom(gbk_t *k, const uint8_t *data, size_t size) {
    GB_load_rom_from_buffer(k->gb, data, size);
    GB_reset(k->gb);
}

void gbk_title(gbk_t *k, char out[17]) {
    memset(out, 0, 17);
    GB_get_rom_title(k->gb, out);
}

size_t gbk_battery_size(gbk_t *k) {
    int n = GB_save_battery_size(k->gb);
    return n > 0 ? (size_t)n : 0;
}

size_t gbk_battery_save(gbk_t *k, uint8_t *out, size_t size) {
    int n = GB_save_battery_to_buffer(k->gb, out, size);
    return n > 0 ? (size_t)n : 0;
}

void gbk_battery_load(gbk_t *k, const uint8_t *data, size_t size) {
    GB_load_battery_from_buffer(k->gb, data, size);
}

size_t gbk_state_size(gbk_t *k) { return GB_get_save_state_size(k->gb); }
void gbk_state_save(gbk_t *k, uint8_t *out) { GB_save_state_to_buffer(k->gb, out); }
int gbk_state_load(gbk_t *k, const uint8_t *data, size_t size) { return GB_load_state_from_buffer(k->gb, data, size); }

void gbk_set_key(gbk_t *k, int key, int pressed) {
    if (key < 0 || key >= GB_KEY_MAX) return;
    GB_set_key_state(k->gb, (GB_key_t)key, pressed != 0);
}

void gbk_run_frame(gbk_t *k) { GB_run_frame(k->gb); }

const uint32_t *gbk_pixels(gbk_t *k) { return k->pixels; }

size_t gbk_audio_pending(gbk_t *k) {
    return atomic_load_explicit(&k->write_pos, memory_order_acquire) - atomic_load_explicit(&k->read_pos, memory_order_relaxed);
}

size_t gbk_read_audio(gbk_t *k, int16_t *out, size_t max_frames) {
    size_t r = atomic_load_explicit(&k->read_pos, memory_order_relaxed);
    size_t w = atomic_load_explicit(&k->write_pos, memory_order_acquire);
    size_t n = w - r;
    if (n > max_frames) n = max_frames;
    for (size_t j = 0; j < n; j++) {
        size_t i = ((r + j) % RING) * 2;
        out[j * 2] = k->ring[i];
        out[j * 2 + 1] = k->ring[i + 1];
    }
    atomic_store_explicit(&k->read_pos, r + n, memory_order_release);
    return n;
}
