// L'iPhone Duo en 3D, pour le site et la vidéo de Foldly.
//
// Repère du modèle (Duo ouvert, tenu droit) : la charnière suit l'axe X, à y = 0.
// La moitié basse va de y = -H à 0, la moitié haute de 0 à H. L'écran intérieur regarde +Z.
// setFold(180) : à plat. 90 : en L. 0 : fermé (la moitié haute repliée sur la basse).
// Fermé, l'écran extérieur (au dos de la moitié haute) regarde +Z ; on tourne le tout de 90° pour le tenir en portrait.

import * as THREE from 'three';

export const DUO = {
  W: 1.0,        // largeur d'une moitié (le long de la charnière)
  H: 0.705,      // hauteur d'une moitié
  T: 0.021,      // épaisseur d'une moitié
  R: 0.085,      // rayon des coins extérieurs
  BEZEL: 0.016,  // bord noir autour de l'écran
};

function halfShape(W, H, r, inset = 0) {
  // Rectangle de (−W/2, 0) à (W/2, H) : coins arrondis côté opposé à la charnière seulement.
  const x0 = -W / 2 + inset, x1 = W / 2 - inset, y0 = inset * 0.35, y1 = H - inset;
  const rr = Math.max(0.001, r - inset * 0.6);
  const s = new THREE.Shape();
  s.moveTo(x0, y0);
  s.lineTo(x1, y0);
  s.lineTo(x1, y1 - rr);
  s.quadraticCurveTo(x1, y1, x1 - rr, y1);
  s.lineTo(x0 + rr, y1);
  s.quadraticCurveTo(x0, y1, x0, y1 - rr);
  s.lineTo(x0, y0);
  return s;
}

function shapeWithCut(W, H, r, inset) {
  return halfShape(W, H, r, inset);
}

/** Géométrie d'un écran : coordonnées UV calées sur la zone [u0,u1]×[v0,v1] de la texture. */
function screenGeometry(shape, box, uv) {
  const g = new THREE.ShapeGeometry(shape, 24);
  const pos = g.attributes.position;
  const uvs = new Float32Array(pos.count * 2);
  for (let i = 0; i < pos.count; i++) {
    const x = pos.getX(i), y = pos.getY(i);
    const fx = (x - box.x0) / (box.x1 - box.x0);
    const fy = (y - box.y0) / (box.y1 - box.y0);
    uvs[i * 2] = uv.u0 + fx * (uv.u1 - uv.u0);
    uvs[i * 2 + 1] = uv.v0 + fy * (uv.v1 - uv.v0);
  }
  g.setAttribute('uv', new THREE.BufferAttribute(uvs, 2));
  return g;
}

export function createDuo(options = {}) {
  const { W, H, T, R, BEZEL } = DUO;
  const color = options.color ?? 0x1c2740;

  const frameMat = new THREE.MeshPhysicalMaterial({
    color, metalness: 0.55, roughness: 0.32, clearcoat: 0.7, clearcoatRoughness: 0.18,
  });
  const edgeMat = new THREE.MeshPhysicalMaterial({
    color: 0x9aa6bd, metalness: 0.9, roughness: 0.22,
  });
  const glassMat = new THREE.MeshPhysicalMaterial({ color: 0x050608, metalness: 0.1, roughness: 0.08, clearcoat: 1 });

  const blank = new THREE.DataTexture(new Uint8Array([10, 12, 16, 255]), 1, 1);
  blank.needsUpdate = true;
  const innerMat = new THREE.MeshBasicMaterial({ map: blank, toneMapped: false });
  const outerMat = new THREE.MeshBasicMaterial({ map: blank, toneMapped: false });
  // Un léger reflet sur le verre, par-dessus l'image.
  const sheenMat = new THREE.MeshPhysicalMaterial({
    color: 0xffffff, transparent: true, opacity: 0.06, roughness: 0.05, metalness: 0, depthWrite: false,
  });

  const extrude = (shape, depth, bevel) => new THREE.ExtrudeGeometry(shape, {
    depth, bevelEnabled: true, bevelThickness: bevel, bevelSize: bevel, bevelSegments: 4, curveSegments: 24,
  });

  // Une moitié : le corps, le verre de l'écran intérieur, l'image.
  function makeHalf(which) {
    const g = new THREE.Group();
    const bevel = 0.006;
    const body = new THREE.Mesh(extrude(halfShape(W - bevel * 2, H - bevel * 2, R - bevel), T - bevel * 2, bevel), frameMat);
    body.position.set(0, bevel, -T + bevel);
    g.add(body);
    // Liseré métallique (fin anneau sur la tranche)
    const rim = new THREE.Mesh(extrude(halfShape(W - 0.002, H - 0.002, R), 0.004, 0.0015), edgeMat);
    rim.position.set(0, 0.001, -T / 2 - 0.002);
    rim.scale.set(1.0, 1.0, 1);
    g.add(rim);

    // Verre noir (bord de l'écran)
    const glassShape = halfShape(W - 0.006, H - 0.004, R - 0.004, 0);
    const glass = new THREE.Mesh(new THREE.ShapeGeometry(glassShape, 24), glassMat);
    glass.position.set(0, 0.002, 0.0012);
    g.add(glass);

    // Image de l'écran intérieur : la moitié haute prend le haut de la texture, la basse le bas.
    const sShape = halfShape(W, H, R, BEZEL);
    const box = { x0: -W / 2 + BEZEL, x1: W / 2 - BEZEL, y0: 0, y1: H - BEZEL };
    const geo = screenGeometry(sShape, box, which === 'top'
      ? { u0: 0, u1: 1, v0: 0.5, v1: 1 }
      : { u0: 0, u1: 1, v0: 0.5, v1: 0 });
    const screen = new THREE.Mesh(geo, innerMat);
    screen.position.z = 0.0022;
    g.add(screen);
    const sheen = new THREE.Mesh(new THREE.ShapeGeometry(sShape, 24), sheenMat);
    sheen.position.z = 0.0026;
    g.add(sheen);
    if (which === 'bottom') {
      // La moitié basse : la même, en miroir de l'autre côté de la charnière.
      g.scale.y = -1;
    }
    return g;
  }

  const root = new THREE.Group();      // à placer / tourner dans la scène
  const device = new THREE.Group();    // le Duo lui-même (centré)
  root.add(device);

  const bottom = makeHalf('bottom');
  device.add(bottom);

  // La moitié haute tourne autour de la charnière (axe X, y = 0).
  // Le pivot est juste au-dessus des écrans : fermées, les deux moitiés se posent l'une sur l'autre.
  const GAP = 0.003;
  const hinge = new THREE.Group();
  hinge.position.z = GAP;
  device.add(hinge);
  const top = makeHalf('top');
  top.position.z = -GAP;
  hinge.add(top);

  // Écran extérieur, au dos de la moitié haute (portrait quand le Duo fermé est tourné de 90°).
  {
    const ow = H - 0.05, oh = W - 0.05;                 // dans le repère de la moitié : largeur le long de Y
    const shape = new THREE.Shape();
    const rr = R - 0.02;
    const x0 = -oh / 2, x1 = oh / 2, y0 = 0.025, y1 = H - 0.025;
    shape.moveTo(x0 + rr, y0); shape.lineTo(x1 - rr, y0); shape.quadraticCurveTo(x1, y0, x1, y0 + rr);
    shape.lineTo(x1, y1 - rr); shape.quadraticCurveTo(x1, y1, x1 - rr, y1);
    shape.lineTo(x0 + rr, y1); shape.quadraticCurveTo(x0, y1, x0, y1 - rr);
    shape.lineTo(x0, y0 + rr); shape.quadraticCurveTo(x0, y0, x0 + rr, y0);
    // L'image portrait est couchée le long de X : u suit Y, v suit X.
    const g = new THREE.ShapeGeometry(shape, 24);
    const pos = g.attributes.position;
    const uvs = new Float32Array(pos.count * 2);
    for (let i = 0; i < pos.count; i++) {
      const x = pos.getX(i), y = pos.getY(i);
      uvs[i * 2] = (y - y0) / (y1 - y0);
      uvs[i * 2 + 1] = 1 - (x - x0) / (x1 - x0);
    }
    g.setAttribute('uv', new THREE.BufferAttribute(uvs, 2));
    const glassBack = new THREE.Mesh(new THREE.ShapeGeometry(halfShape(W - 0.03, H - 0.02, R - 0.015), glassMat));
    glassBack.position.set(0, 0.01, -T - 0.0012);
    glassBack.rotation.y = Math.PI;
    top.add(glassBack);
    const outer = new THREE.Mesh(g, outerMat);
    outer.position.set(0, 0, -T - 0.0022);
    outer.rotation.y = Math.PI;
    top.add(outer);
    const sheen = new THREE.Mesh(new THREE.ShapeGeometry(shape, 24), sheenMat);
    sheen.position.set(0, 0, -T - 0.0026);
    sheen.rotation.y = Math.PI;
    top.add(sheen);
  }

  // Bloc photo au dos de la moitié basse (en haut à gauche quand le Duo fermé est vu de dos, en portrait).
  {
    const cam = new THREE.Group();
    const plateShape = new THREE.Shape();
    const pw = 0.32, ph = 0.17, pr = 0.06;
    plateShape.moveTo(-pw / 2 + pr, -ph / 2); plateShape.lineTo(pw / 2 - pr, -ph / 2);
    plateShape.quadraticCurveTo(pw / 2, -ph / 2, pw / 2, -ph / 2 + pr); plateShape.lineTo(pw / 2, ph / 2 - pr);
    plateShape.quadraticCurveTo(pw / 2, ph / 2, pw / 2 - pr, ph / 2); plateShape.lineTo(-pw / 2 + pr, ph / 2);
    plateShape.quadraticCurveTo(-pw / 2, ph / 2, -pw / 2, ph / 2 - pr); plateShape.lineTo(-pw / 2, -ph / 2 + pr);
    plateShape.quadraticCurveTo(-pw / 2, -ph / 2, -pw / 2 + pr, -ph / 2);
    const plate = new THREE.Mesh(extrude(plateShape, 0.008, 0.004), frameMat);
    cam.add(plate);
    const lensMat = new THREE.MeshPhysicalMaterial({ color: 0x0b0e16, metalness: 0.2, roughness: 0.05, clearcoat: 1 });
    const ringMat = new THREE.MeshPhysicalMaterial({ color: 0x2a3550, metalness: 0.8, roughness: 0.25 });
    for (const dx of [-0.075, 0.075]) {
      const ring = new THREE.Mesh(new THREE.CylinderGeometry(0.062, 0.062, 0.016, 40), ringMat);
      ring.rotation.x = Math.PI / 2; ring.position.set(dx, 0, 0.012);
      cam.add(ring);
      const lens = new THREE.Mesh(new THREE.CylinderGeometry(0.045, 0.045, 0.018, 40), lensMat);
      lens.rotation.x = Math.PI / 2; lens.position.set(dx, 0, 0.014);
      cam.add(lens);
    }
    const flash = new THREE.Mesh(new THREE.CylinderGeometry(0.014, 0.014, 0.01, 20),
      new THREE.MeshStandardMaterial({ color: 0xf2efe6, roughness: 0.4 }));
    flash.rotation.x = Math.PI / 2; flash.position.set(0.2, 0.03, 0.006);
    cam.add(flash);
    // Au dos de la moitié basse : z négatif. Moitié basse : y de −H à 0.
    cam.rotation.y = Math.PI;
    cam.rotation.z = Math.PI / 2;
    cam.position.set(W / 2 - 0.13, -H + 0.22, -T - 0.002);
    device.add(cam);
  }

  // Boutons sur la tranche (côté droit de la moitié basse)
  {
    const btnMat = edgeMat;
    const b1 = new THREE.Mesh(new RoundedBox(0.008, 0.11, 0.01), btnMat);
    b1.position.set(W / 2 + 0.003, -0.25, -T / 2);
    device.add(b1);
  }

  function RoundedBox(w, h, d) { return new THREE.BoxGeometry(w, h, d); }

  let fold = 180;
  function setFold(deg) {
    fold = deg;
    // 180 : à plat. La moitié haute tourne vers l'avant (+Z) en se fermant.
    hinge.rotation.x = (180 - deg) * Math.PI / 180;
    // Centré : ouvert, la charnière est au milieu ; fermé, le Duo ne fait plus qu'une moitié.
    const k = 1 - Math.min(1, Math.max(0, deg) / 180);
    device.position.y = (DUO.H / 2) * Math.min(1, k * 2);
  }
  setFold(180);

  function setInner(texture) { innerMat.map = texture; innerMat.needsUpdate = true; }
  function setOuter(texture) { outerMat.map = texture; outerMat.needsUpdate = true; }

  return { root, device, hinge, top, bottom, setFold, setInner, setOuter, get fold() { return fold; }, materials: { frameMat, innerMat, outerMat } };
}
