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

#endif
