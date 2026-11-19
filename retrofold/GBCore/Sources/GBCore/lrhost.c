// RetroFold : un hôte libretro minimal pour la Game Pak. Le cœur (un framework de l'app) est ouvert avec dlopen ;
// ses fonctions retro_* sont prises avec dlsym, donc deux cœurs ne se gênent pas. Un seul cœur tourne à la fois.
#include "gbcore.h"
#include "libretro.h"
#include <dlfcn.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#define LR_RING (1 << 15)

static struct {
    void *lib;
    void (*init)(void);
    void (*deinit)(void);
    void (*set_environment)(retro_environment_t);
    void (*set_video_refresh)(retro_video_refresh_t);
    void (*set_audio_sample)(retro_audio_sample_t);
    void (*set_audio_sample_batch)(retro_audio_sample_batch_t);
    void (*set_input_poll)(retro_input_poll_t);
    void (*set_input_state)(retro_input_state_t);
    void (*get_system_info)(struct retro_system_info *);
    void (*get_system_av_info)(struct retro_system_av_info *);
    void (*set_controller_port_device)(unsigned, unsigned);
    void (*run)(void);
    bool (*load_game)(const struct retro_game_info *);
    void (*unload_game)(void);
    size_t (*serialize_size)(void);
    bool (*serialize)(void *, size_t);
    bool (*unserialize)(const void *, size_t);
    void *(*get_memory_data)(unsigned);
    size_t (*get_memory_size)(unsigned);
    bool loaded;
    int format;  // RETRO_PIXEL_FORMAT_*
    double fps, rate;
    uint32_t *pixels;
    int width, height, capacity;
    int16_t ring[LR_RING * 2];
    _Atomic size_t wpos, rpos;
    uint32_t buttons;
    int px, py, pressed;
    char system_dir[1024], save_dir[1024];
    char error[256];
    void *rom_map;
    size_t rom_size;
} lr;

const char *lr_error(void) { return lr.error; }

static void lr_log(enum retro_log_level level, const char *fmt, ...) {
    if (level < RETRO_LOG_WARN) return;
    va_list ap;
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
}

static bool environment(unsigned cmd, void *data) {
    switch (cmd) {
        case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT: {
            int f = *(const enum retro_pixel_format *)data;
            if (f == RETRO_PIXEL_FORMAT_XRGB8888 || f == RETRO_PIXEL_FORMAT_RGB565 || f == RETRO_PIXEL_FORMAT_0RGB1555) {
                lr.format = f;
                return true;
            }
            return false;
        }
        case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
            *(const char **)data = lr.system_dir;
            return true;
        case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY:
            *(const char **)data = lr.save_dir;
            return true;
        case RETRO_ENVIRONMENT_GET_CORE_ASSETS_DIRECTORY:
            *(const char **)data = lr.system_dir;
            return true;
        case RETRO_ENVIRONMENT_GET_LOG_INTERFACE:
            ((struct retro_log_callback *)data)->log = lr_log;
            return true;
        case RETRO_ENVIRONMENT_GET_CAN_DUPE:
            *(bool *)data = true;
            return true;
        case RETRO_ENVIRONMENT_GET_LANGUAGE:
            *(unsigned *)data = RETRO_LANGUAGE_ENGLISH;
            return true;
        case RETRO_ENVIRONMENT_GET_INPUT_BITMASKS:
            return true;
        case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE:
            *(bool *)data = false;
            return true;
        case RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION:
            *(unsigned *)data = 0;
            return true;
        case RETRO_ENVIRONMENT_SET_GEOMETRY:
        case RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO:
        case RETRO_ENVIRONMENT_SET_PERFORMANCE_LEVEL:
        case RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS:
        case RETRO_ENVIRONMENT_SET_CONTROLLER_INFO:
        case RETRO_ENVIRONMENT_SET_SUPPORT_ACHIEVEMENTS:
        case RETRO_ENVIRONMENT_SET_SERIALIZATION_QUIRKS:
        case RETRO_ENVIRONMENT_SET_MEMORY_MAPS:
        case RETRO_ENVIRONMENT_SET_SUBSYSTEM_INFO:
        case RETRO_ENVIRONMENT_SET_CONTENT_INFO_OVERRIDE:
            return true;
        default:
            return false;
    }
}

static void ensure_capacity(int w, int h) {
    if (w * h > lr.capacity) {
        free(lr.pixels);
        lr.capacity = w * h;
        lr.pixels = calloc((size_t)lr.capacity, 4);
    }
}

static void video(const void *data, unsigned w, unsigned h, size_t pitch) {
    if (!data || data == RETRO_HW_FRAME_BUFFER_VALID || w == 0 || h == 0) return;
    ensure_capacity((int)w, (int)h);
    if (!lr.pixels) return;
    for (unsigned y = 0; y < h; y++) {
        uint32_t *dst = lr.pixels + (size_t)y * w;
        const uint8_t *row = (const uint8_t *)data + y * pitch;
        if (lr.format == RETRO_PIXEL_FORMAT_XRGB8888) {
            const uint32_t *src = (const uint32_t *)row;
            for (unsigned x = 0; x < w; x++) {
                uint32_t c = src[x];
                dst[x] = ((c >> 16) & 0xFF) | (c & 0xFF00) | ((c & 0xFF) << 16) | 0xFF000000u;
            }
        } else {
            const uint16_t *src = (const uint16_t *)row;
            for (unsigned x = 0; x < w; x++) {
                uint16_t c = src[x];
                uint32_t r, g, b;
                if (lr.format == RETRO_PIXEL_FORMAT_RGB565) {
                    r = (c >> 11) & 0x1F; g = (c >> 5) & 0x3F; b = c & 0x1F;
                    r = (r << 3) | (r >> 2); g = (g << 2) | (g >> 4); b = (b << 3) | (b >> 2);
                } else {
                    r = (c >> 10) & 0x1F; g = (c >> 5) & 0x1F; b = c & 0x1F;
                    r = (r << 3) | (r >> 2); g = (g << 3) | (g >> 2); b = (b << 3) | (b >> 2);
                }
                dst[x] = r | (g << 8) | (b << 16) | 0xFF000000u;
            }
        }
    }
    lr.width = (int)w;
    lr.height = (int)h;
}

static size_t audio_batch(const int16_t *data, size_t frames) {
    size_t w = atomic_load_explicit(&lr.wpos, memory_order_relaxed);
    size_t r = atomic_load_explicit(&lr.rpos, memory_order_acquire);
    for (size_t i = 0; i < frames; i++) {
        if (w - r >= LR_RING) break;
        size_t j = (w % LR_RING) * 2;
        lr.ring[j] = data[i * 2];
        lr.ring[j + 1] = data[i * 2 + 1];
        w++;
    }
    atomic_store_explicit(&lr.wpos, w, memory_order_release);
    return frames;
}

static void audio_sample(int16_t l, int16_t r) {
    int16_t s[2] = { l, r };
    audio_batch(s, 1);
}

static void input_poll(void) {}

static int16_t input_state(unsigned port, unsigned device, unsigned index, unsigned id) {
    (void)index;
    if (port != 0) return 0;
    if (device == RETRO_DEVICE_JOYPAD) {
        if (id == RETRO_DEVICE_ID_JOYPAD_MASK) return (int16_t)lr.buttons;
        return (lr.buttons >> id) & 1;
    }
    if (device == RETRO_DEVICE_POINTER) {
        if (lr.width == 0 || lr.height == 0) return 0;
        switch (id) {
            case RETRO_DEVICE_ID_POINTER_X: return (int16_t)((lr.px * 0xFFFF) / lr.width - 0x7FFF);
            case RETRO_DEVICE_ID_POINTER_Y: return (int16_t)((lr.py * 0xFFFF) / lr.height - 0x7FFF);
            case RETRO_DEVICE_ID_POINTER_PRESSED: return (int16_t)lr.pressed;
            default: return 0;
        }
    }
    return 0;
}

#define SYM(field, name) do { *(void **)&lr.field = dlsym(lr.lib, name); if (!lr.field) { snprintf(lr.error, sizeof lr.error, "missing %s", name); dlclose(lr.lib); lr.lib = NULL; return -2; } } while (0)

int lr_open(const char *core_path, const char *system_dir, const char *save_dir) {
    lr_close();
    lr.error[0] = 0;
    lr.lib = dlopen(core_path, RTLD_NOW | RTLD_LOCAL);
    if (!lr.lib) {
        snprintf(lr.error, sizeof lr.error, "%s", dlerror() ?: "dlopen failed");
        return -1;
    }
    SYM(init, "retro_init"); SYM(deinit, "retro_deinit");
    SYM(set_environment, "retro_set_environment"); SYM(set_video_refresh, "retro_set_video_refresh");
    SYM(set_audio_sample, "retro_set_audio_sample"); SYM(set_audio_sample_batch, "retro_set_audio_sample_batch");
    SYM(set_input_poll, "retro_set_input_poll"); SYM(set_input_state, "retro_set_input_state");
    SYM(get_system_info, "retro_get_system_info"); SYM(get_system_av_info, "retro_get_system_av_info");
    SYM(set_controller_port_device, "retro_set_controller_port_device");
    SYM(run, "retro_run"); SYM(load_game, "retro_load_game"); SYM(unload_game, "retro_unload_game");
    SYM(serialize_size, "retro_serialize_size"); SYM(serialize, "retro_serialize"); SYM(unserialize, "retro_unserialize");
    SYM(get_memory_data, "retro_get_memory_data"); SYM(get_memory_size, "retro_get_memory_size");
    snprintf(lr.system_dir, sizeof lr.system_dir, "%s", system_dir);
    snprintf(lr.save_dir, sizeof lr.save_dir, "%s", save_dir);
    lr.format = RETRO_PIXEL_FORMAT_0RGB1555;
    lr.set_environment(environment);
    lr.init();
    lr.set_video_refresh(video);
    lr.set_audio_sample(audio_sample);
    lr.set_audio_sample_batch(audio_batch);
    lr.set_input_poll(input_poll);
    lr.set_input_state(input_state);
    return 0;
}

int lr_load(const char *rom_path) {
    if (!lr.lib) return -1;
    struct retro_system_info sys = {0};
    lr.get_system_info(&sys);
    struct retro_game_info game = { .path = rom_path };
    if (!sys.need_fullpath) {
        int fd = open(rom_path, O_RDONLY);
        if (fd < 0) { snprintf(lr.error, sizeof lr.error, "can't open the game"); return -1; }
        struct stat st;
        fstat(fd, &st);
        lr.rom_size = (size_t)st.st_size;
        lr.rom_map = mmap(NULL, lr.rom_size, PROT_READ, MAP_PRIVATE, fd, 0);
        close(fd);
        if (lr.rom_map == MAP_FAILED) { lr.rom_map = NULL; snprintf(lr.error, sizeof lr.error, "can't read the game"); return -1; }
        game.data = lr.rom_map;
        game.size = lr.rom_size;
    }
    if (!lr.load_game(&game)) { snprintf(lr.error, sizeof lr.error, "the core refused the game"); return -3; }
    lr.loaded = true;
    lr.set_controller_port_device(0, RETRO_DEVICE_JOYPAD);
    struct retro_system_av_info av = {0};
    lr.get_system_av_info(&av);
    lr.fps = av.timing.fps > 1 ? av.timing.fps : 60;
    lr.rate = av.timing.sample_rate > 1000 ? av.timing.sample_rate : 32768;
    return 0;
}

void lr_close(void) {
    if (!lr.lib) return;
    if (lr.loaded) lr.unload_game();
    lr.deinit();
    dlclose(lr.lib);
    lr.lib = NULL;
    lr.loaded = false;
    if (lr.rom_map) { munmap(lr.rom_map, lr.rom_size); lr.rom_map = NULL; }
    free(lr.pixels);
    lr.pixels = NULL;
    lr.capacity = lr.width = lr.height = 0;
    lr.buttons = 0;
    lr.pressed = 0;
    atomic_store(&lr.wpos, 0);
    atomic_store(&lr.rpos, 0);
}

double lr_fps(void) { return lr.fps; }
double lr_sample_rate(void) { return lr.rate; }
void lr_run_frame(void) { if (lr.loaded) lr.run(); }

const uint32_t *lr_pixels(int *width, int *height) {
    *width = lr.width;
    *height = lr.height;
    return lr.pixels;
}

size_t lr_read_audio(int16_t *out, size_t max_frames) {
    size_t r = atomic_load_explicit(&lr.rpos, memory_order_relaxed);
    size_t w = atomic_load_explicit(&lr.wpos, memory_order_acquire);
    size_t n = w - r;
    if (n > max_frames) n = max_frames;
    for (size_t j = 0; j < n; j++) {
        size_t i = ((r + j) % LR_RING) * 2;
        out[j * 2] = lr.ring[i];
        out[j * 2 + 1] = lr.ring[i + 1];
    }
    atomic_store_explicit(&lr.rpos, r + n, memory_order_release);
    return n;
}

void lr_set_button(int id, int pressed) {
    if (id < 0 || id > 15) return;
    if (pressed) lr.buttons |= (1u << id); else lr.buttons &= ~(1u << id);
}

void lr_set_pointer(int x, int y, int pressed) { lr.px = x; lr.py = y; lr.pressed = pressed; }

size_t lr_sram_size(void) { return lr.loaded ? lr.get_memory_size(RETRO_MEMORY_SAVE_RAM) : 0; }
uint8_t *lr_sram(void) { return lr.loaded ? lr.get_memory_data(RETRO_MEMORY_SAVE_RAM) : NULL; }
size_t lr_state_size(void) { return lr.loaded ? lr.serialize_size() : 0; }
int lr_state_save(uint8_t *out, size_t size) { return lr.loaded && lr.serialize(out, size) ? 0 : -1; }
int lr_state_load(const uint8_t *data, size_t size) { return lr.loaded && lr.unserialize(data, size) ? 0 : -1; }
