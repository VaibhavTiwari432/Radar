import React, { useEffect, useRef } from 'react';
import * as THREE from 'three';
import { C } from '../theme.js';
import { STATUS_COLOR, sampleSeries } from '../lib/consoleFrame.js';

// Higher-visual-fidelity variant of Scene3D.jsx. Same rule as the standard
// client: every position/state rendered here comes from the current frame
// object (truth.phantoms[].pos, radar.tracks[].rangeEst/state) -- nothing
// here reads a clock and invents a trajectory.
//
// WHAT IS DECORATIVE HERE, AND WHY IT IS SAFE TO BE. These carry no numeric
// meaning and must never be read as measurements:
//   * idle camera drift, ambient turret rotation, expanding pulse rings
//     (arbitrary period, NOT tied to PRI/PRF -- microsecond pulse timing at
//     human scale would be meaningless, and implying otherwise is exactly the
//     fabricated precision this project avoids elsewhere)
//   * the rotating SWEEP WEDGE. It shows the radar scanning; it does NOT gate
//     what is drawn. Nothing appears or disappears as it passes, because this
//     export path reports angle_source:'none' and there IS no per-target
//     bearing to reveal. A sweep that lit targets up as it crossed them would
//     be claiming azimuth the console does not have.
//   * TERRAIN. MISSION_SIMULATOR_UI_SPEC.md Section 11 ruled a terrain mesh
//     out ("would look like capability you do not have"). It is here because
//     the operator asked for it. The radar has no terrain model: these peaks
//     occlude nothing, mask nothing, and attenuate nothing.
//   * the MOTHER DRONE and its transit. The jammer carries a power budget and
//     NO POSITION in this project's model (RADAR_REALISM_AUDIT.md Tier 1 #3),
//     so this flight path is illustrative. It exists to make the ~125 s
//     planning wait legible as a mission, and is labelled ILLUSTRATIVE on
//     screen so it cannot be mistaken for a tracked platform.
//
// Phantom colour, by contrast, IS data: white until a verdict exists, then it
// eases to the judge's own per-phantom status colour.

const SCENE_RADIUS = 210;
const UNRESOLVED = 0xb8c2cc;    // white -- "no verdict yet", never a result

// Mission replay timing. NOTHING MOVES UNTIL MATLAB HAS RETURNED: the transit
// is a playback of the engagement the judge just scored, not a progress bar
// for it. A bar that filled while the planner searched would be inventing
// progress -- the search has no known duration.
const FLIGHT_S = 13;            // fallback only; see flightS below
const SPAWN_START = 0.26;       // phantoms appear BEFORE the midpoint...
const SPAWN_END = 0.48;         // ...and are on station by it

// THE TRANSIT IS SCALED TO THE MISSION, not the other way round. The window
// after SPAWN_END is where the scored engagement replays, so it is stretched
// to hold exactly frame.mission.durationS seconds -- the replay then runs at
// 1x real time and no "sped up Nx" caveat is needed anywhere on screen. The
// mother drone and every phantom therefore share ONE clock: what you watch
// her fly through is the same 8 s the judge scored.
const flightSecondsFor = (durationS) =>
  (durationS > 0 ? durationS / (1 - SPAWN_END) : FLIGHT_S);

// The replay LOOPS. It is a recording of a fixed, already-scored engagement,
// so repeating it invents nothing -- and playing it once, ~13 s out of a ~76 s
// wait, meant the operator usually arrived to find everything already parked
// at its final range. A replay you cannot watch is not a replay.

// Deterministic value hash. Terrain must be identical between mounts so a
// screenshot regression compares like with like; Math.random would not be.
const hash = (i) => {
  const x = Math.sin(i * 127.1) * 43758.5453;
  return x - Math.floor(x);
};

function mountain(seed, radius, height) {
  const geo = new THREE.ConeGeometry(radius, height, 7, 2);
  const pos = geo.attributes.position;
  const apex = height / 2;
  for (let i = 0; i < pos.count; i++) {
    const y = pos.getY(i);
    if (y > apex - 0.01) continue;              // leave the summit sharp
    // 0.24 over 3 height bands read as spiky conifers, not massif
    const k = 0.15 * radius;
    pos.setX(i, pos.getX(i) + (hash(seed + i) - 0.5) * k);
    pos.setZ(i, pos.getZ(i) + (hash(seed + i + 91) - 0.5) * k);
    pos.setY(i, y + (hash(seed + i + 313) - 0.5) * k * 0.55);
  }
  geo.computeVertexNormals();
  // Lit enough to read as rock. At 0x141d25 the peaks silhouetted into flat
  // black cutouts and looked like a broken render rather than terrain.
  return new THREE.Mesh(geo, new THREE.MeshStandardMaterial({
    color: 0x2b3947, roughness: 0.94, metalness: 0.05, flatShading: true,
    emissive: 0x0a1219, emissiveIntensity: 0.6,
  }));
}

/** Ring of peaks around the horizon. Returns summit points for the transit. */
function terrain() {
  const g = new THREE.Group();
  const peaks = [];
  const N = 11;
  for (let i = 0; i < N; i++) {
    const a = (i / N) * Math.PI * 2 + hash(i) * 0.4;
    // Just outside the data zone (rings + phantoms reach ~175 world units).
    // At 125-220 the peaks stood inside it and occluded the phantoms they
    // are meant to frame; at 275-440 they fell off the edge of the default
    // camera entirely. This band reads as a horizon without intruding.
    const d = 230 + hash(i + 40) * 125;
    const h = 55 + hash(i + 80) * 72;
    const r = 50 + hash(i + 120) * 46;
    const m = mountain(i * 17, r, h);
    m.position.set(Math.cos(a) * d, h / 2, Math.sin(a) * d);
    g.add(m);
    peaks.push(new THREE.Vector3(m.position.x, h * 0.94, m.position.z));
  }
  // Waypoints picked by where they land IN VIEW, not by index: the two
  // widest-apart peaks on the far ridge, so the transit crosses the horizon
  // left-to-right instead of flying at/away from the default camera.
  const far = peaks.filter((p) => p.z < -120).sort((a, b) => a.x - b.x);
  g.userData.from = far[0] ?? peaks[0];
  g.userData.to = far[far.length - 1] ?? peaks[1];
  return g;
}

/** Rotating scan wedge. Decorative -- see the header note on why it must not
 *  gate target visibility. */
function sweepBeam(radius) {
  const g = new THREE.Group();
  const wedge = new THREE.Mesh(
    new THREE.CircleGeometry(radius, 72, 0, Math.PI / 6),
    new THREE.MeshBasicMaterial({
      color: 0x2fd47e, transparent: true, opacity: 0.085,
      side: THREE.DoubleSide, depthWrite: false,
    })
  );
  wedge.rotation.x = -Math.PI / 2;
  g.add(wedge);
  const edge = new THREE.Line(
    new THREE.BufferGeometry().setFromPoints([
      new THREE.Vector3(0, 0, 0), new THREE.Vector3(radius, 0, 0)]),
    new THREE.LineBasicMaterial({ color: 0x7cf3b4, transparent: true, opacity: 0.45 })
  );
  g.add(edge);
  // PPI graticule: decorative spokes + minor rings. The two DATA rings
  // (unambiguous range, range ceiling) are drawn from `identity` elsewhere.
  const soft = new THREE.LineBasicMaterial({ color: 0x1d2b36, transparent: true, opacity: 0.5 });
  for (let i = 0; i < 12; i++) {
    const a = (i / 12) * Math.PI * 2;
    g.add(new THREE.Line(new THREE.BufferGeometry().setFromPoints([
      new THREE.Vector3(0, 0, 0),
      new THREE.Vector3(Math.cos(a) * radius, 0, Math.sin(a) * radius)]), soft));
  }
  g.position.y = 0.55;
  return g;
}

/** Quadratic bezier, ridge A -> ridge B, arcing over the valley. */
function transitPoint(a, b, t, out) {
  const u = 1 - t;
  const mx = (a.x + b.x) / 2, mz = (a.z + b.z) / 2;
  const my = Math.max(a.y, b.y) + 38;
  return out.set(
    u * u * a.x + 2 * u * t * mx + t * t * b.x,
    u * u * a.y + 2 * u * t * my + t * t * b.y,
    u * u * a.z + 2 * u * t * mz + t * t * b.z
  );
}

function droneHiFi(color, s = 1) {
  const g = new THREE.Group();
  const bodyMat = new THREE.MeshStandardMaterial({
    color, emissive: color, emissiveIntensity: 0.32, roughness: 0.45, metalness: 0.5, transparent: true,
  });
  const body = new THREE.Mesh(new THREE.BoxGeometry(2.4 * s, 0.8 * s, 3.2 * s), bodyMat);
  g.add(body);
  const nose = new THREE.Mesh(new THREE.ConeGeometry(0.5 * s, 1.3 * s, 8), bodyMat);
  nose.rotation.x = -Math.PI / 2;
  nose.position.z = 2.1 * s;
  g.add(nose);

  const rotors = [];
  [[-1, -1], [1, -1], [-1, 1], [1, 1]].forEach(([sx, sz]) => {
    const arm = new THREE.Mesh(new THREE.CylinderGeometry(0.14 * s, 0.14 * s, 2.5 * s, 6), bodyMat);
    arm.rotation.z = Math.PI / 2;
    arm.position.set(sx * 1.25 * s, 0.1 * s, sz * 1.25 * s);
    arm.rotation.y = sx * sz > 0 ? Math.PI / 4 : -Math.PI / 4;
    g.add(arm);
    const hub = new THREE.Mesh(new THREE.CylinderGeometry(0.28 * s, 0.28 * s, 0.4 * s, 8), bodyMat);
    hub.position.set(sx * 2.2 * s, 0.32 * s, sz * 2.2 * s);
    g.add(hub);
    const disc = new THREE.Mesh(
      new THREE.CylinderGeometry(1.3 * s, 1.3 * s, 0.04 * s, 20),
      new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.16, side: THREE.DoubleSide })
    );
    disc.position.copy(hub.position);
    disc.position.y += 0.22 * s;
    g.add(disc);
    rotors.push(disc);
  });
  g.userData.mat = bodyMat;
  g.userData.rotors = rotors;
  return g;
}

function radarEmplacementHiFi() {
  const g = new THREE.Group();
  const steel = new THREE.MeshStandardMaterial({ color: 0x2a2f36, roughness: 0.65, metalness: 0.55 });
  // Muted and shallower than the original 0x9e2a2a/0.85 bowl: once the
  // emplacement was scaled up to match the ridgeline, a deep saturated dish
  // rendered as a glowing red sphere from behind rather than an antenna.
  const hot = new THREE.MeshStandardMaterial({
    color: 0x5e3235, emissive: 0x7d1c1c, emissiveIntensity: 0.35,
    roughness: 0.5, metalness: 0.35, side: THREE.DoubleSide,
  });
  const pad = new THREE.Mesh(new THREE.CylinderGeometry(7.5, 8.6, 1.3, 28), steel);
  pad.position.y = 0.65; g.add(pad);
  const turret = new THREE.Group(); turret.position.y = 1.3; g.add(turret);
  const cab = new THREE.Mesh(new THREE.BoxGeometry(5.2, 3, 4.2), steel);
  cab.position.y = 1.5; turret.add(cab);
  const mast = new THREE.Mesh(new THREE.CylinderGeometry(0.6, 0.75, 6, 12), steel);
  mast.position.y = 5.2; turret.add(mast);
  // Flat planar array, not a parabolic bowl. A deep dish renders as a
  // featureless dome from behind -- and this radar IS an array: the angle
  // channel is phase-comparison monopulse across array elements, so a panel
  // is the more faithful depiction as well as the more legible one.
  const dish = new THREE.Group();
  dish.add(new THREE.Mesh(new THREE.BoxGeometry(9.6, 7.2, 0.45), hot));
  const backing = new THREE.Mesh(new THREE.BoxGeometry(10.5, 8.1, 0.3), steel);
  backing.position.z = -0.4; dish.add(backing);
  const lattice = [];
  for (let i = -4; i <= 4; i++) lattice.push(new THREE.Vector3(i, -3.4, 0.26), new THREE.Vector3(i, 3.4, 0.26));
  for (let j = -3; j <= 3; j++) lattice.push(new THREE.Vector3(-4.5, j, 0.26), new THREE.Vector3(4.5, j, 0.26));
  dish.add(new THREE.LineSegments(
    new THREE.BufferGeometry().setFromPoints(lattice),
    new THREE.LineBasicMaterial({ color: 0xff7a7a, transparent: true, opacity: 0.3 })));
  dish.position.set(0, 9.6, 1.15);
  dish.rotation.x = -0.2;              // tilted back ~11 deg
  turret.add(dish);
  const l1 = new THREE.PointLight(0xff3535, 2.4, 80); l1.position.y = 10.5; g.add(l1);
  g.userData.turret = turret;
  g.userData.dish = dish;
  g.userData.light = l1;
  return g;
}

function trackMarker() {
  const g = new THREE.Group();
  const mat = new THREE.MeshStandardMaterial({ transparent: true, roughness: 0.35, metalness: 0.3 });
  const core = new THREE.Mesh(new THREE.OctahedronGeometry(2.1), mat);
  g.add(core);
  const ringMat = new THREE.MeshBasicMaterial({ transparent: true, side: THREE.DoubleSide });
  const ring = new THREE.Mesh(new THREE.RingGeometry(2.8, 3.2, 24), ringMat);
  ring.rotation.x = -Math.PI / 2;
  g.add(ring);
  g.userData.mat = mat;
  g.userData.ringMat = ringMat;
  return g;
}

/**
 * @param {'idle'|'planning'|'verdict'} phase  drives the mother-drone transit
 *   only. 'planning' = a real plan+judge cycle is in flight.
 */
export default function Scene3DHiFi({
  frame, identity, labelHost, phase = 'idle', verdictAt = null, onPositions = null,
}) {
  const mountRef = useRef(null);
  const stateRef = useRef(null);
  const phaseRef = useRef(phase);
  phaseRef.current = phase;   // read by the rAF loop without re-mounting it
  const verdictRef = useRef(verdictAt);
  verdictRef.current = verdictAt;
  const onPosRef = useRef(onPositions);
  onPosRef.current = onPositions;

  useEffect(() => {
    const mount = mountRef.current;
    if (!mount) return;
    let W = mount.clientWidth || 800, H = mount.clientHeight || 460;

    const scene = new THREE.Scene();
    scene.background = new THREE.Color('#05080d');
    // pushed out from 220 so the ridgeline reads as terrain, not as haze
    scene.fog = new THREE.Fog('#05080d', 420, 1500);

    const cam = new THREE.PerspectiveCamera(40, W / H, 0.5, 2200);
    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(W, H);
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    mount.appendChild(renderer.domElement);

    scene.add(new THREE.HemisphereLight(0x2a3f52, 0x05070a, 0.85));
    const key = new THREE.DirectionalLight(0x9fc4ec, 0.75);
    key.position.set(-150, 210, 130); scene.add(key);
    const rim = new THREE.DirectionalLight(0x1f4a6b, 0.5);
    rim.position.set(180, 90, -160); scene.add(rim);

    const grid = new THREE.GridHelper(SCENE_RADIUS * 2.6, 30, 0x27333f, 0x151f28);
    scene.add(grid);

    const ringGroup = new THREE.Group();
    scene.add(ringGroup);
    const pulseGroup = new THREE.Group();
    scene.add(pulseGroup);
    const pulses = [0, 1].map(() => {
      const m = new THREE.Mesh(
        new THREE.RingGeometry(1, 1.6, 96),
        new THREE.MeshBasicMaterial({ color: 0xff5a5a, transparent: true, opacity: 0.35, side: THREE.DoubleSide })
      );
      m.rotation.x = -Math.PI / 2;
      m.position.y = 0.5;
      pulseGroup.add(m);
      return m;
    });

    const sweep = sweepBeam(SCENE_RADIUS * 0.62);
    scene.add(sweep);

    const land = terrain();
    scene.add(land);

    const radar = radarEmplacementHiFi();
    radar.scale.setScalar(2.6);   // was a speck once the scene grew to the ridgeline
    scene.add(radar);

    // Mother drone: bigger and amber so it never reads as one of the phantoms.
    const mother = droneHiFi(0xffab2e, 2.3);
    mother.position.copy(land.userData.from);
    scene.add(mother);
    const motherBeacon = new THREE.PointLight(0xffab2e, 1.6, 120);
    mother.add(motherBeacon);

    const trail = new THREE.Line(
      new THREE.BufferGeometry().setFromPoints(
        Array.from({ length: 48 }, (_, i) =>
          transitPoint(land.userData.from, land.userData.to, i / 47, new THREE.Vector3()))),
      new THREE.LineDashedMaterial({
        color: 0xffab2e, transparent: true, opacity: 0.22, dashSize: 4, gapSize: 5 })
    );
    trail.computeLineDistances();
    scene.add(trail);

    const markerGroup = new THREE.Group();
    scene.add(markerGroup);

    // EMISSION LEADERS, mother -> each live phantom. The PPI has drawn these
    // since it was written; the 3D view had nothing showing WHERE the false
    // targets come from, so a phantom read as an aircraft rather than as
    // something one repeater is projecting.
    //
    // This asserts no geometry the project does not already assert: every
    // phantom in a scene is made by the same jammer (CLAUDE.md Honest Limits),
    // which is precisely why they share a bearing and why an angle channel
    // would flag the whole group at once. The mother's END of the line is
    // illustrative -- she has a power budget and no modelled position -- and
    // is labelled so on screen.
    const LEADER_MAX = 32;
    const leaderGeo = new THREE.BufferGeometry();
    leaderGeo.setAttribute('position',
      new THREE.BufferAttribute(new Float32Array(LEADER_MAX * 6), 3));
    const leaders = new THREE.LineSegments(leaderGeo, new THREE.LineBasicMaterial({
      color: 0xffab2e, transparent: true, opacity: 0.22 }));
    leaders.frustumCulled = false;      // endpoints move every frame
    scene.add(leaders);

    let repAcc = 0;                 // position-feed throttle (~11 Hz)
    const target = new THREE.Vector3(SCENE_RADIUS * 0.26, 11, 0);
    // lower elevation than the old 0.48 so the ridgeline sits on the horizon
    // behind the engagement instead of being looked down on
    const drag = { on: false, x: 0, y: 0, az: 0.5, el: 0.34, dist: 400, idle: 0 };
    const flight = { t: 0 };
    const _look = new THREE.Vector3();
    const _home = new THREE.Vector3();   // scratch: phantom position at tau
    const el = renderer.domElement;
    const onDown = (e) => { drag.on = true; drag.x = e.clientX; drag.y = e.clientY; };
    const onUp = () => { drag.on = false; };
    const onMove = (e) => {
      if (!drag.on) return;
      drag.az -= (e.clientX - drag.x) * 0.005;
      drag.el = THREE.MathUtils.clamp(drag.el + (e.clientY - drag.y) * 0.004, 0.1, 1.2);
      drag.x = e.clientX; drag.y = e.clientY;
    };
    const onWheel = (e) => {
      e.preventDefault();
      // upper bound raised so the operator can pull back far enough to see
      // the whole ridgeline, not just the engagement zone
      drag.dist = THREE.MathUtils.clamp(drag.dist + e.deltaY * 0.35, 120, 900);
    };
    el.addEventListener('mousedown', onDown);
    window.addEventListener('mouseup', onUp);
    window.addEventListener('mousemove', onMove);
    el.addEventListener('wheel', onWheel, { passive: false });

    let raf;
    const clock = new THREE.Clock();
    const animate = () => {
      raf = requestAnimationFrame(animate);
      const dt = Math.min(clock.getDelta(), 0.08);
      drag.idle += dt;
      // gentle ambient auto-orbit only while the user isn't dragging --
      // decorative camera motion, not tied to any data value.
      const az = drag.on ? drag.az : drag.az + Math.sin(drag.idle * 0.05) * 0.0003;
      if (!drag.on) drag.az = az;
      cam.position.set(
        target.x + drag.dist * Math.cos(drag.el) * Math.sin(drag.az),
        target.y + drag.dist * Math.sin(drag.el),
        target.z + drag.dist * Math.cos(drag.el) * Math.cos(drag.az)
      );
      cam.lookAt(target);

      if (radar.userData.turret) radar.userData.turret.rotation.y += dt * 0.18;
      if (radar.userData.dish) radar.userData.dish.rotation.z = Math.sin(drag.idle * 0.6) * 0.15;
      if (radar.userData.light) radar.userData.light.intensity = 2.0 + 0.6 * Math.sin(drag.idle * 3);

      pulses.forEach((ring, i) => {
        const period = 2.6;
        const ph = ((drag.idle + (i * period) / pulses.length) % period) / period;
        const outer = Math.max(ph * SCENE_RADIUS * 0.9, 1.2);
        ring.geometry.dispose();
        ring.geometry = new THREE.RingGeometry(Math.max(outer - 1.2, 0.3), outer, 96);
        ring.material.opacity = 0.32 * (1 - ph);
      });

      sweep.rotation.y -= dt * 0.55;          // ~11 s/rev, decorative

      // Mother-drone transit. Parked until the judge has returned; then the
      // mission plays back on a real clock, looping.
      const vAt = verdictRef.current;
      const flightS = stateRef.current?.flightS ?? FLIGHT_S;
      flight.t = vAt
        ? (((Date.now() - vAt) / (flightS * 1000)) % 1 + 1) % 1
        : 0;
      // Mission time in SECONDS, on the judge's own frame time base. Runs
      // 0 -> durationS across the post-spawn window; everything positional
      // below is sampled at this one value, which is what makes the mother
      // drone and the phantoms share a trajectory instead of each animating
      // to its own private timer.
      const durationS = stateRef.current?.durationS ?? 0;
      const tau = THREE.MathUtils.clamp(
        ((flight.t - SPAWN_END) / (1 - SPAWN_END)) * durationS, 0, durationS);
      transitPoint(land.userData.from, land.userData.to, flight.t, mother.position);
      transitPoint(land.userData.from, land.userData.to,
        Math.min(1, flight.t + 0.02), _look);
      mother.lookAt(_look);
      mother.userData.rotors.forEach((r, ri) => { r.rotation.y += dt * (26 + ri * 3); });
      motherBeacon.intensity = 1.2 + 0.7 * Math.sin(drag.idle * 4);

      const st = stateRef.current;
      if (st) {
        st.motherPos = mother.position;

        // SPAWN, keyed to the transit rather than to its own timer: the
        // phantoms leave the mother drone before it reaches the midpoint and
        // are on station by it. The emission arc is decorative; where it ENDS
        // is the planner's real range at t=0, so nothing arrives anywhere the
        // backend did not put it.
        //
        // THEN THEY FLY THEIR OWN TRAJECTORY. Past the spawn the mesh tracks
        // path(tau) -- the per-frame range server/app.py replayed out of
        // advance_phantom, the same propagation that was rendered into the
        // cube the judge scored. This is what the scene was missing: it used
        // to park every phantom at its t=0 range for the whole engagement,
        // which is why a multi-phantom scene read as a static row.
        //
        // Motion here can legitimately be small. The planner picks a radial
        // velocity, and a few m/s over 8 s is a fraction of one 46.8 m range
        // cell -- real, sub-resolution, and not the renderer's to exaggerate.
        st.markers.forEach((mesh) => {
          const home = mesh.userData.homePos;
          if (!home) return;
          if (!vAt) { mesh.visible = false; return; }
          const lead = (mesh.userData.idx ?? 0) * 0.02;   // staggered emissions
          const g = THREE.MathUtils.clamp(
            (flight.t - SPAWN_START - lead) / (SPAWN_END - SPAWN_START), 0, 1);
          mesh.visible = g > 0;
          if (g <= 0) return;
          // Where this phantom is RIGHT NOW in mission time. Falls back to the
          // t=0 range on a payload with no truth_track, so an older backend
          // still renders exactly as it did before.
          const x = sampleSeries(st.missionTimeS, mesh.userData.path, tau);
          _home.set(Number.isFinite(x) ? x : home.x, home.y, home.z);
          const e = g * g * (3 - 2 * g);                  // smoothstep
          mesh.position.lerpVectors(mother.position, _home, e);
          mesh.position.y += Math.sin(Math.PI * e) * 14;  // arc over the valley
          mesh.scale.setScalar(0.35 + 0.65 * e);
        });

        // Track markers follow their own MEASURED range series, and exist
        // only while the radar actually held them. sampleSeries returns null
        // outside a track's hit window, and a track confirmed for 4 of 8
        // frames genuinely was not there for the other four -- so it winks
        // out rather than hovering at a mean range it never occupied.
        st.markers.forEach((mesh) => {
          const path = mesh.userData.trackPath;
          if (!path) return;
          if (!vAt) { mesh.visible = false; return; }
          if (!mesh.userData.trackTimeS?.length) { mesh.visible = true; return; }
          const x = sampleSeries(mesh.userData.trackTimeS, path, tau);
          mesh.visible = Number.isFinite(x);
          if (mesh.visible) mesh.position.x = x;
        });

        // Re-point the leaders at wherever the phantoms just moved to.
        const lp = leaders.geometry.attributes.position;
        let seg = 0;
        st.markers.forEach((mesh, key) => {
          if (seg >= LEADER_MAX || !key.startsWith('phantom:') || !mesh.visible) return;
          lp.setXYZ(seg * 2, mother.position.x, mother.position.y, mother.position.z);
          lp.setXYZ(seg * 2 + 1, mesh.position.x, mesh.position.y, mesh.position.z);
          seg += 1;
        });
        lp.needsUpdate = true;
        leaders.geometry.setDrawRange(0, seg * 2);

        st.markers.forEach((mesh) => {
          // White until the judge has ruled, then ease to the verdict colour.
          // The transition is cosmetic; the destination colour is data.
          const tc = mesh.userData.targetColor;
          if (tc && mesh.userData.mat) {
            const k = Math.min(1, dt * 2.2);
            mesh.userData.mat.color.lerp(tc, k);
            mesh.userData.mat.emissive.lerp(tc, k);
          }
          if (mesh.userData.rotors) {
            mesh.userData.rotors.forEach((r, ri) => { r.rotation.y += dt * (22 + ri * 3); });
          }
          if (mesh.userData.ringMat) {
            mesh.rotation.z += dt * 0.6;
          }
        });
      }

      // ---- position feed: the scope plots THESE, not its own copy ----
      // One source of truth for where everything is. The PPI used to derive
      // its own geometry, which meant the two views could disagree about the
      // same object mid-spawn. Now the 3D scene is authoritative and the scope
      // is a projection of it, so they cannot drift apart.
      //
      // Range is the MEASURED/planned quantity. Bearing is the scene's own
      // layout -- the mother's illustrative transit, and the single shared
      // axis this project places phantoms on because one jammer makes them
      // all. It is NOT a radar measurement; angle_source is 'none' and the
      // scope labels it so.
      repAcc += dt;
      if (repAcc > 0.09 && st && st.worldPerM > 0 && onPosRef.current) {
        repAcc = 0;
        const wpm = st.worldPerM;
        const polar = (p) => ({
          rangeM: Math.hypot(p.x, p.z) / wpm,
          azDeg: ((Math.atan2(p.x, -p.z) * 180) / Math.PI + 360) % 360,
        });
        const out = { mother: polar(mother.position), phantoms: [], tracks: [] };
        st.markers.forEach((mesh, key) => {
          if (!mesh.visible) return;
          if (key.startsWith('phantom:') && mesh.userData.homePos) {
            out.phantoms.push({
              id: key.slice('phantom:'.length),
              status: mesh.userData.status,
              ...polar(mesh.position),
            });
          } else if (key.startsWith('track:')) {
            // The radar's OWN returns, fed through so the scope can show what
            // the tracker holds next to what the jammer planned. The panel is
            // titled "what the radar holds" and until now plotted only the
            // truth phantoms; these are the measured side of that claim.
            out.tracks.push({ id: key.slice('track:'.length), ...polar(mesh.position) });
          }
        });
        onPosRef.current(out);
      }

      renderer.render(scene, cam);
    };
    animate();

    const onResize = () => {
      W = mount.clientWidth; H = mount.clientHeight;
      cam.aspect = W / H; cam.updateProjectionMatrix(); renderer.setSize(W, H);
    };
    window.addEventListener('resize', onResize);

    stateRef.current = { scene, cam, el, ringGroup, markerGroup, markers: new Map() };

    return () => {
      cancelAnimationFrame(raf);
      window.removeEventListener('resize', onResize);
      window.removeEventListener('mouseup', onUp);
      window.removeEventListener('mousemove', onMove);
      el.removeEventListener('mousedown', onDown);
      el.removeEventListener('wheel', onWheel);
      try { mount.removeChild(renderer.domElement); } catch { /* already unmounted */ }
      renderer.dispose();
    };
  }, []);

  // per-frame data update: positions/states only, all read from `frame`
  useEffect(() => {
    const st = stateRef.current;
    if (!st || !frame || !identity) return;
    const rangeCellM = identity.rangeCellM?.value ?? 0;
    const unambigM = identity.unambigRangeM?.value ?? 0;
    const ceilM = rangeCellM * 512;

    // SCALE. This used to map SCENE_RADIUS onto the 512-range-cell ceiling
    // (23983 m), which put every phantom in a live scene inside the middle
    // 15% of the view -- the engagement was a cluster of dots and the
    // dominant feature on screen was a ring nobody can be detected at (the
    // link budget puts detection at 7227 m). Scale to what is actually in
    // the scene instead. Ranges keep their measured values; only the
    // metres-per-world-unit changes, and any ring that no longer fits is
    // dropped rather than drawn off-scene at a misleading radius.
    //
    // The max is taken over the WHOLE trajectory, not just its first frame:
    // a phantom that opens 600 m during the engagement must not walk off the
    // edge of the scale that was fitted to where it started.
    const dataMaxM = Math.max(
      unambigM,
      ...frame.truth.phantoms.flatMap((p) => (p.rangeSeries?.length
        ? p.rangeSeries : [Array.isArray(p.pos) ? p.pos[0] : 0])),
      ...frame.radar.tracks.flatMap((t) => (t.rangeSeries?.length
        ? t.rangeSeries : [Number.isFinite(t.rangeEst) ? t.rangeEst : 0]))
    );
    const worldPerM = dataMaxM > 0 ? SCENE_RADIUS / (dataMaxM * 1.25) : 0;
    st.worldPerM = worldPerM;      // the position feed converts back through it

    // Mission clock, handed to the rAF loop. Absent on a payload with no
    // truth_track, in which case the transit keeps its old fixed length and
    // everything parks as it used to.
    st.missionTimeS = frame.mission?.timeS ?? null;
    st.durationS = frame.mission?.durationS ?? 0;
    st.flightS = flightSecondsFor(st.durationS);

    st.ringGroup.clear();
    [
      { r: unambigM * worldPerM, color: 0xffab2e, opacity: 0.55 },
      { r: ceilM * worldPerM, color: 0xff4a4a, opacity: 0.28 },
    ].forEach(({ r, color, opacity }) => {
      if (!(r > 0) || r > SCENE_RADIUS * 1.05) return;
      const pts = [];
      for (let i = 0; i <= 128; i++) {
        const a = (i / 128) * Math.PI * 2;
        pts.push(new THREE.Vector3(Math.cos(a) * r, 0.4, Math.sin(a) * r));
      }
      st.ringGroup.add(new THREE.LineLoop(
        new THREE.BufferGeometry().setFromPoints(pts),
        new THREE.LineBasicMaterial({ color, transparent: true, opacity })
      ));
    });

    const wanted = new Set();
    const labelPositions = [];

    frame.truth.phantoms.forEach((p, pi) => {
      const key = `phantom:${p.id}`;
      wanted.add(key);
      let mesh = st.markers.get(key);
      if (!mesh) {
        // Born WHITE -- "no verdict on this object yet". The animate loop
        // eases it to the status colour, so the moment the radar accepts a
        // phantom as real is something you watch happen.
        mesh = droneHiFi(UNRESOLVED, 2.6);
        st.markerGroup.add(mesh);
        st.markers.set(key, mesh);
      }
      // Judge's own per-phantom verdict, via the same STATUS_COLOR table the
      // results panel uses -- one source of truth for what green means.
      mesh.userData.targetColor = new THREE.Color(STATUS_COLOR[p.status] ?? '#b8c2cc');
      mesh.userData.mat.emissiveIntensity =
        { confirmed: 0.75, flagged: 0.3, undetected: 0.1 }[p.status] ?? 0.32;
      mesh.userData.mat.opacity = p.status === 'undetected' ? 0.35 : 1;
      // The planner's trajectory is the DESTINATION; the rAF loop flies the
      // mesh out from the mother drone and then along it. Position is not set
      // here, or the spawn would be overwritten on every data update.
      const rangeM = Array.isArray(p.pos) ? p.pos[0] : 0;
      mesh.userData.homePos = new THREE.Vector3(rangeM * worldPerM, 0, 0);
      // Pre-converted to world units so the rAF loop does no arithmetic per
      // frame beyond the lookup itself.
      mesh.userData.path = p.rangeSeries?.length
        ? p.rangeSeries.map((m) => m * worldPerM) : null;
      mesh.userData.idx = pi;
      mesh.userData.status = p.status;
      labelPositions.push({
        id: `${p.id}  ${String(p.status ?? '').toUpperCase()}`,
        kind: 'phantom',
        mesh,                       // label tracks the mesh while it flies
      });
    });

    frame.radar.tracks.forEach((tr) => {
      const key = `track:${tr.id}`;
      wanted.add(key);
      let mesh = st.markers.get(key);
      if (!mesh) {
        mesh = trackMarker();
        st.markerGroup.add(mesh);
        st.markers.set(key, mesh);
      }
      const stateColorHex = {
        TENTATIVE: 0x3d4d5b, CONFIRMED: 0xc6d5e0, COASTING: 0xffab2e, DELETED: 0xff4a4a,
      }[tr.state] ?? 0xc6d5e0;
      mesh.userData.mat.color.setHex(stateColorHex);
      mesh.userData.mat.emissive.setHex(stateColorHex);
      mesh.userData.mat.emissiveIntensity = 0.45;
      mesh.userData.ringMat.color.setHex(stateColorHex);
      const deleteMiss = frame.radar.tracker?.deleteMofN?.[0] ?? 5;
      const misses = Number.isFinite(tr.misses) ? tr.misses : 0;
      const opacity = tr.state === 'DELETED' ? 0 : Math.max(0.15, 1 - misses / Math.max(1, deleteMiss));
      mesh.userData.mat.opacity = opacity;
      mesh.userData.ringMat.opacity = opacity * 0.8;
      const rangeM = Number.isFinite(tr.rangeEst) ? tr.rangeEst : 0;
      mesh.position.set(rangeM * worldPerM, 7, 0);
      // The MEASURED series, at the times it was measured. The rAF loop moves
      // the marker along it and hides it outside its hit window.
      mesh.userData.trackPath = tr.rangeSeries?.length
        ? tr.rangeSeries.map((m) => m * worldPerM) : null;
      mesh.userData.trackTimeS = tr.timeS ?? [];
      if (opacity > 0.02) {
        // Label follows the marker, which now moves. A cloned start position
        // would leave the caption stranded at the track's first hit.
        labelPositions.push({ id: `${tr.id} ${tr.state}`, kind: 'track', mesh, dy: 3.5 });
      }
    });

    for (const [key, mesh] of st.markers.entries()) {
      if (!wanted.has(key)) {
        st.markerGroup.remove(mesh);
        mesh.geometry?.dispose?.();
        st.markers.delete(key);
      }
    }

    st.labelPositions = labelPositions;
  }, [frame, identity]);

  // screen-space label overlay, updated every frame via rAF against the
  // live camera -- text content is real (phantom/track id + state), only
  // the projection math is "computed" here (standard screen-space
  // projection, not scenario physics).
  const labelLayerRef = useRef(null);
  useEffect(() => {
    let raf;
    const tick = () => {
      raf = requestAnimationFrame(tick);
      const st = stateRef.current;
      const layer = labelLayerRef.current;
      if (!st || !layer) return;
      // The mother drone moves every frame, not every data update, so its
      // label is appended here rather than in the data effect. It is tagged
      // ILLUSTRATIVE on screen because its position is not modelled.
      const lps = st.motherPos
        ? [...(st.labelPositions ?? []),
           { id: 'MOTHER  ILLUSTRATIVE', kind: 'mother', pos: st.motherPos }]
        : (st.labelPositions ?? []);
      const rect = st.el.getBoundingClientRect();
      const v = new THREE.Vector3();
      const nodes = layer.children;
      lps.forEach((lp, i) => {
        let node = nodes[i];
        if (!node) {
          node = document.createElement('div');
          node.style.cssText = `position:absolute;top:0;left:0;pointer-events:none;white-space:nowrap;
            padding:2px 6px;border-radius:3px;font:9px ui-monospace,monospace;
            background:rgba(10,15,21,0.82);border:1px solid ${C.line};color:${C.silver};transform:translate(-50%,-100%);`;
          layer.appendChild(node);
        }
        // A phantom label follows its mesh while the mesh is still flying;
        // static entries (tracks, the mother) carry a fixed point instead.
        if (lp.mesh) { v.copy(lp.mesh.position); v.y += lp.dy ?? 7; }
        else v.copy(lp.pos);
        v.project(st.cam);
        const sx = (v.x * 0.5 + 0.5) * rect.width;
        const sy = (-v.y * 0.5 + 0.5) * rect.height;
        // A hidden mesh takes its label with it. Tracks now wink out on the
        // frames the radar was not holding them, and a caption left floating
        // over empty space would claim a contact that is not there.
        const vis = v.z < 1 && (lp.mesh ? lp.mesh.visible : true);
        node.style.opacity = vis ? '1' : '0';
        node.style.transform = `translate(${sx}px, ${sy}px) translate(-50%, -100%)`;
        node.style.color = lp.kind === 'mother' ? C.amber : C.silver;
        node.textContent = lp.id;
      });
      while (nodes.length > lps.length) layer.removeChild(nodes[nodes.length - 1]);
    };
    tick();
    return () => cancelAnimationFrame(raf);
  }, []);

  return (
    <div ref={mountRef} style={{ position: 'absolute', inset: 0 }}>
      <div ref={labelLayerRef} style={{ position: 'absolute', inset: 0, pointerEvents: 'none' }} />
    </div>
  );
}
