// Fichier généré par tools/bascule_gen.py : ne pas modifier à la main.
// Chaque niveau a été vérifié : l'angle « solution » fait tomber la bille dans le panier
// en ramassant les trois étoiles.

import Foundation

extension BasculeLevel {
    static let all: [BasculeLevel] = [
        BasculeLevel(
            number: 1, world: 1, pivotY: 0.3997, drop: 0.2545, wind: 0.0,
            basket: BasculeBasket(0.8746, 0.9746, 0.4347),
            walls: [BasculeWall(0.7158, 0.4098, 0.8202, 0.4098)],
            pads: [],
            stars: [BPt(0.6974, 0.5914), BPt(0.7747, 0.5935), BPt(0.852, 0.54)],
            preview: true, solution: 48.1094
        ),
        BasculeLevel(
            number: 2, world: 1, pivotY: 0.4767, drop: 0.2329, wind: 0.0,
            basket: BasculeBasket(0.7182, 0.8032, 0.6262),
            walls: [BasculeWall(0.6589, 0.7523, 0.6589, 0.9373)],
            pads: [],
            stars: [BPt(0.6435, 0.6654), BPt(0.6844, 0.68), BPt(0.7239, 0.6663)],
            preview: false, solution: 54.7188
        ),
        BasculeLevel(
            number: 3, world: 1, pivotY: 0.443, drop: 0.2797, wind: 0.0,
            basket: BasculeBasket(0.7115, 0.8115, 0.6633),
            walls: [BasculeWall(0.7134, 0.4525, 0.7134, 0.5745)],
            pads: [],
            stars: [BPt(0.6328, 0.6551), BPt(0.6744, 0.6848), BPt(0.7161, 0.6872)],
            preview: true, solution: 59.5938
        ),
        BasculeLevel(
            number: 4, world: 1, pivotY: 0.4128, drop: 0.2693, wind: 0.0,
            basket: BasculeBasket(0.8228, 0.9228, 0.4394),
            walls: [BasculeWall(0.6856, 0.5044, 0.6856, 0.5905)],
            pads: [],
            stars: [BPt(0.6657, 0.6356), BPt(0.7355, 0.6392), BPt(0.8052, 0.5724)],
            preview: true, solution: 57.2031
        ),
        BasculeLevel(
            number: 5, world: 1, pivotY: 0.3605, drop: 0.3537, wind: 0.0,
            basket: BasculeBasket(0.8512, 0.9362, 0.6097),
            walls: [BasculeWall(0.8151, 0.3799, 0.8151, 0.5412)],
            pads: [],
            stars: [BPt(0.6758, 0.5902), BPt(0.7501, 0.6359), BPt(0.8243, 0.6413)],
            preview: false, solution: 54.7969
        ),
        BasculeLevel(
            number: 6, world: 1, pivotY: 0.3365, drop: 0.3014, wind: 0.0,
            basket: BasculeBasket(0.813, 0.898, 0.5042),
            walls: [BasculeWall(0.7255, 0.2528, 0.7255, 0.4254)],
            pads: [],
            stars: [BPt(0.6621, 0.5638), BPt(0.7284, 0.5924), BPt(0.7948, 0.5709)],
            preview: false, solution: 57.2344
        ),
        BasculeLevel(
            number: 7, world: 1, pivotY: 0.3725, drop: 0.3446, wind: 0.0,
            basket: BasculeBasket(0.8464, 0.9464, 0.5243),
            walls: [],
            pads: [],
            stars: [BPt(0.6636, 0.6391), BPt(0.742, 0.6737), BPt(0.8203, 0.6349)],
            preview: false, solution: 61.7188
        ),
        BasculeLevel(
            number: 8, world: 1, pivotY: 0.4715, drop: 0.2417, wind: 0.0,
            basket: BasculeBasket(0.7513, 0.8363, 0.4634),
            walls: [BasculeWall(0.7369, 0.3221, 0.7369, 0.4073)],
            pads: [],
            stars: [BPt(0.6392, 0.6875), BPt(0.691, 0.679), BPt(0.7427, 0.6033)],
            preview: false, solution: 60.9219
        ),
        BasculeLevel(
            number: 9, world: 1, pivotY: 0.4572, drop: 0.3268, wind: 0.0,
            basket: BasculeBasket(0.8369, 0.9219, 0.6135),
            walls: [BasculeWall(0.7474, 0.5454, 0.8607, 0.5454)],
            pads: [],
            stars: [BPt(0.6625, 0.7092), BPt(0.7358, 0.7407), BPt(0.8091, 0.708)],
            preview: false, solution: 60.2969
        ),
        BasculeLevel(
            number: 10, world: 1, pivotY: 0.435, drop: 0.2561, wind: 0.0,
            basket: BasculeBasket(0.7375, 0.8225, 0.4529),
            walls: [BasculeWall(0.7315, 0.1879, 0.7315, 0.3813), BasculeWall(0.7194, 0.2578, 0.7194, 0.394)],
            pads: [],
            stars: [BPt(0.6316, 0.6626), BPt(0.6835, 0.6613), BPt(0.7355, 0.5897)],
            preview: false, solution: 63.3281
        ),
        BasculeLevel(
            number: 11, world: 2, pivotY: 0.4337, drop: 0.3084, wind: 0.368,
            basket: BasculeBasket(0.8065, 0.8865, 0.6664),
            walls: [BasculeWall(0.7151, 0.4811, 0.7151, 0.5955), BasculeWall(0.7426, 0.7362, 0.7426, 0.8535)],
            pads: [],
            stars: [BPt(0.652, 0.6558), BPt(0.7151, 0.6917), BPt(0.7844, 0.6943)],
            preview: false, solution: 58.125
        ),
        BasculeLevel(
            number: 12, world: 2, pivotY: 0.2956, drop: 0.2243, wind: 0.6483,
            basket: BasculeBasket(0.8005, 0.8805, 0.4222),
            walls: [BasculeWall(0.6995, 0.5346, 0.8221, 0.5346), BasculeWall(0.6774, 0.2822, 0.6774, 0.4159)],
            pads: [],
            stars: [BPt(0.6508, 0.4808), BPt(0.7071, 0.4912), BPt(0.7736, 0.4704)],
            preview: false, solution: 53.9375
        ),
        BasculeLevel(
            number: 13, world: 2, pivotY: 0.4585, drop: 0.3581, wind: -0.8683,
            basket: BasculeBasket(0.8865, 0.9665, 0.568),
            walls: [BasculeWall(0.8153, 0.4881, 0.921, 0.4881)],
            pads: [],
            stars: [BPt(0.7424, 0.6556), BPt(0.8287, 0.6808), BPt(0.8909, 0.6504)],
            preview: false, solution: 41.4219
        ),
        BasculeLevel(
            number: 14, world: 2, pivotY: 0.4365, drop: 0.3182, wind: -0.7749,
            basket: BasculeBasket(0.8325, 0.9125, 0.5082),
            walls: [BasculeWall(0.7881, 0.3167, 0.7881, 0.4385)],
            pads: [],
            stars: [BPt(0.7232, 0.6381), BPt(0.797, 0.6546), BPt(0.8471, 0.6098)],
            preview: false, solution: 44.5938
        ),
        BasculeLevel(
            number: 15, world: 2, pivotY: 0.4521, drop: 0.257, wind: -0.5433,
            basket: BasculeBasket(0.7428, 0.8228, 0.4385),
            walls: [BasculeWall(0.6321, 0.3629, 0.8115, 0.3629)],
            pads: [],
            stars: [BPt(0.6832, 0.6549), BPt(0.7357, 0.6499), BPt(0.7685, 0.5771)],
            preview: false, solution: 50.9375
        ),
        BasculeLevel(
            number: 16, world: 2, pivotY: 0.2812, drop: 0.2793, wind: -0.6883,
            basket: BasculeBasket(0.6935, 0.7735, 0.2994),
            walls: [BasculeWall(0.62, 0.2297, 0.7639, 0.2297)],
            pads: [],
            stars: [BPt(0.6743, 0.5017), BPt(0.7192, 0.5056), BPt(0.7388, 0.436)],
            preview: false, solution: 53.9375
        ),
        BasculeLevel(
            number: 17, world: 2, pivotY: 0.4924, drop: 0.324, wind: -0.5468,
            basket: BasculeBasket(0.867, 0.947, 0.4339),
            walls: [BasculeWall(0.8458, 0.2181, 0.8458, 0.3878), BasculeWall(0.828, 0.5381, 0.828, 0.6197)],
            pads: [],
            stars: [BPt(0.729, 0.7218), BPt(0.8153, 0.7208), BPt(0.875, 0.6223)],
            preview: false, solution: 48.875
        ),
        BasculeLevel(
            number: 18, world: 2, pivotY: 0.285, drop: 0.2679, wind: -0.8867,
            basket: BasculeBasket(0.7656, 0.8456, 0.0785),
            walls: [BasculeWall(0.739, 0.5319, 0.8401, 0.5319)],
            pads: [],
            stars: [BPt(0.7412, 0.4653), BPt(0.8058, 0.4321), BPt(0.8272, 0.3013)],
            preview: false, solution: 41.0
        ),
        BasculeLevel(
            number: 19, world: 2, pivotY: 0.4046, drop: 0.3455, wind: -0.476,
            basket: BasculeBasket(0.8738, 0.9538, 0.2838),
            walls: [BasculeWall(0.7418, 0.138, 0.7418, 0.2921), BasculeWall(0.7125, 0.427, 0.8493, 0.427)],
            pads: [],
            stars: [BPt(0.7285, 0.6622), BPt(0.8192, 0.6557), BPt(0.8811, 0.5284)],
            preview: false, solution: 52.6875
        ),
        BasculeLevel(
            number: 20, world: 2, pivotY: 0.2823, drop: 0.2352, wind: -0.3954,
            basket: BasculeBasket(0.7523, 0.8323, 0.4041),
            walls: [BasculeWall(0.7191, 0.4824, 0.7191, 0.6514)],
            pads: [],
            stars: [BPt(0.6812, 0.4479), BPt(0.7298, 0.4605), BPt(0.7713, 0.4449)],
            preview: false, solution: 44.3281
        ),
        BasculeLevel(
            number: 21, world: 3, pivotY: 0.3198, drop: 0.2667, wind: -0.3888,
            basket: BasculeBasket(0.7398, 0.8198, 0.3344),
            walls: [BasculeWall(0.8598, 0.1848, 0.8598, 0.2718), BasculeWall(0.882, 0.5373, 0.882, 0.6226)],
            pads: [BasculePad(0.7989, 0.9189, 0.3417)],
            stars: [BPt(0.668, 0.5386), BPt(0.7203, 0.5387), BPt(0.759, 0.4684)],
            preview: false, solution: 55.5156
        ),
        BasculeLevel(
            number: 22, world: 3, pivotY: 0.2828, drop: 0.2215, wind: 0.0,
            basket: BasculeBasket(0.8894, 0.9694, 0.4154),
            walls: [BasculeWall(0.7222, 0.2588, 0.7222, 0.375), BasculeWall(0.6246, 0.5271, 0.7727, 0.5271)],
            pads: [BasculePad(0.7147, 0.8347, 0.3755)],
            stars: [BPt(0.6875, 0.4755), BPt(0.769, 0.4047), BPt(0.8491, 0.4573)],
            preview: false, solution: 53.3594
        ),
        BasculeLevel(
            number: 23, world: 3, pivotY: 0.2809, drop: 0.2498, wind: -0.2943,
            basket: BasculeBasket(0.8993, 0.9793, 0.4099),
            walls: [BasculeWall(0.8276, 0.23, 0.8276, 0.3292)],
            pads: [BasculePad(0.7996, 0.9196, 0.3791)],
            stars: [BPt(0.731, 0.4754), BPt(0.8208, 0.4085), BPt(0.8916, 0.4598)],
            preview: false, solution: 47.2188
        ),
        BasculeLevel(
            number: 24, world: 3, pivotY: 0.293, drop: 0.2393, wind: -0.3739,
            basket: BasculeBasket(0.8976, 0.9776, 0.4084),
            walls: [BasculeWall(0.8661, 0.4694, 0.8661, 0.5785)],
            pads: [BasculePad(0.7943, 0.9143, 0.3772)],
            stars: [BPt(0.7411, 0.4679), BPt(0.8289, 0.4079), BPt(0.8955, 0.4516)],
            preview: false, solution: 42.6875
        ),
        BasculeLevel(
            number: 25, world: 3, pivotY: 0.2906, drop: 0.2296, wind: 0.0,
            basket: BasculeBasket(0.8842, 0.9642, 0.3828),
            walls: [BasculeWall(0.8106, 0.2035, 0.8106, 0.3284)],
            pads: [BasculePad(0.7273, 0.8473, 0.3771)],
            stars: [BPt(0.676, 0.4958), BPt(0.7596, 0.4067), BPt(0.8432, 0.4779)],
            preview: false, solution: 58.6562
        ),
        BasculeLevel(
            number: 26, world: 3, pivotY: 0.313, drop: 0.2249, wind: 0.0,
            basket: BasculeBasket(0.8775, 0.9575, 0.4574),
            walls: [BasculeWall(0.8568, 0.567, 0.8568, 0.7618), BasculeWall(0.7864, 0.1976, 0.7864, 0.3409)],
            pads: [BasculePad(0.7094, 0.8294, 0.3619)],
            stars: [BPt(0.678, 0.513), BPt(0.7587, 0.4104), BPt(0.8393, 0.4781)],
            preview: false, solution: 57.25
        ),
        BasculeLevel(
            number: 27, world: 3, pivotY: 0.2939, drop: 0.2297, wind: 0.0,
            basket: BasculeBasket(0.8786, 0.9586, 0.386),
            walls: [BasculeWall(0.8592, 0.1515, 0.8592, 0.3105), BasculeWall(0.6516, 0.3189, 0.8473, 0.3189)],
            pads: [BasculePad(0.7369, 0.8569, 0.3754)],
            stars: [BPt(0.6733, 0.4997), BPt(0.756, 0.4053), BPt(0.8386, 0.4807)],
            preview: false, solution: 59.3125
        ),
        BasculeLevel(
            number: 28, world: 3, pivotY: 0.2935, drop: 0.2299, wind: -0.2498,
            basket: BasculeBasket(0.8779, 0.9579, 0.4089),
            walls: [BasculeWall(0.8574, 0.5193, 0.8574, 0.7084), BasculeWall(0.7284, 0.559, 0.7284, 0.7586)],
            pads: [BasculePad(0.7537, 0.8737, 0.3354)],
            stars: [BPt(0.723, 0.4783), BPt(0.8086, 0.3696), BPt(0.8742, 0.4514)],
            preview: false, solution: 48.5781
        ),
        BasculeLevel(
            number: 29, world: 3, pivotY: 0.285, drop: 0.2546, wind: -0.4427,
            basket: BasculeBasket(0.8705, 0.9505, 0.3908),
            walls: [BasculeWall(0.7697, 0.162, 0.7697, 0.3398), BasculeWall(0.8494, 0.4761, 0.8494, 0.6179)],
            pads: [BasculePad(0.7599, 0.8799, 0.375)],
            stars: [BPt(0.7438, 0.475), BPt(0.8311, 0.3974), BPt(0.8863, 0.4577)],
            preview: false, solution: 45.0781
        ),
        BasculeLevel(
            number: 30, world: 3, pivotY: 0.3413, drop: 0.2264, wind: 0.0,
            basket: BasculeBasket(0.8889, 0.9689, 0.4899),
            walls: [BasculeWall(0.8466, 0.5707, 0.8466, 0.6652), BasculeWall(0.7683, 0.5724, 0.9055, 0.5724)],
            pads: [BasculePad(0.7188, 0.8388, 0.3649)],
            stars: [BPt(0.6798, 0.5421), BPt(0.7635, 0.4254), BPt(0.8472, 0.4957)],
            preview: false, solution: 57.7188
        )
    ]
}
