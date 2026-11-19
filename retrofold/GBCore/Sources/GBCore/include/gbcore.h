// RetroFold : une petite interface au-dessus de SameBoy, pour Swift.
#ifndef GBCORE_H
#define GBCORE_H

#include <stddef.h>
#include <stdint.h>

typedef struct gbk gbk_t;

enum { GBK_RIGHT = 0, GBK_LEFT, GBK_UP, GBK_DOWN, GBK_A, GBK_B, GBK_SELECT, GBK_START };

/// Une console : couleur (Game Boy Color, lit aussi les jeux Game Boy) ou non.
gbk_t *gbk_create(int color, unsigned sample_rate);
void gbk_destroy(gbk_t *k);
/// Charge le jeu (une copie est gardée) et redémarre la console.
void gbk_load_rom(gbk_t *k, const uint8_t *data, size_t size);
/// Le titre écrit dans l'en-tête du jeu (16 caractères au plus).
void gbk_title(gbk_t *k, char out[17]);

/// La sauvegarde de la cartouche (pile) : taille, lecture, écriture.
size_t gbk_battery_size(gbk_t *k);
size_t gbk_battery_save(gbk_t *k, uint8_t *out, size_t size);
void gbk_battery_load(gbk_t *k, const uint8_t *data, size_t size);

/// L'état complet de la console (reprendre exactement où on en était).
size_t gbk_state_size(gbk_t *k);
void gbk_state_save(gbk_t *k, uint8_t *out);
int gbk_state_load(gbk_t *k, const uint8_t *data, size_t size);

void gbk_set_key(gbk_t *k, int key, int pressed);
/// Fait tourner la console jusqu'à l'image suivante (environ 1/60 s de jeu).
void gbk_run_frame(gbk_t *k);
/// L'image : 160 × 144 pixels, 4 octets par pixel (R, G, B, X).
const uint32_t *gbk_pixels(gbk_t *k);
/// Le son produit, entrelacé gauche/droite en 16 bits ; rend le nombre d'échantillons stéréo lus.
size_t gbk_read_audio(gbk_t *k, int16_t *out, size_t max_frames);
/// Échantillons stéréo en attente.
size_t gbk_audio_pending(gbk_t *k);


// ---- Cœurs libretro chargés depuis un framework de l'app (GBA : mGBA, DS : melonDS DS). Un seul à la fois. ----

enum { LR_B = 0, LR_Y, LR_SELECT, LR_START, LR_UP, LR_DOWN, LR_LEFT, LR_RIGHT, LR_A, LR_X, LR_L, LR_R };

/// Ouvre le cœur (chemin du binaire du framework). 0 si tout va bien, sinon un message dans lr_error().
int lr_open(const char *core_path, const char *system_dir, const char *save_dir);
const char *lr_error(void);
/// Charge le jeu (chemin du fichier). 0 si tout va bien.
int lr_load(const char *rom_path);
void lr_close(void);
double lr_fps(void);
double lr_sample_rate(void);
void lr_run_frame(void);
/// L'image courante en R, G, B, X ; largeur et hauteur en sortie (0 si pas encore d'image).
const uint32_t *lr_pixels(int *width, int *height);
size_t lr_read_audio(int16_t *out, size_t max_frames);
void lr_set_button(int id, int pressed);
/// Le toucher (écran tactile de la DS), en coordonnées de l'image : x, y en pixels.
void lr_set_pointer(int x, int y, int pressed);
size_t lr_sram_size(void);
uint8_t *lr_sram(void);
size_t lr_state_size(void);
int lr_state_save(uint8_t *out, size_t size);
int lr_state_load(const uint8_t *data, size_t size);

#endif
