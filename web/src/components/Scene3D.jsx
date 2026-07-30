import React, { useEffect, useRef } from 'react';
import * as THREE from 'three';
import { C } from '../theme.js';

// 3D scenario view. Renders ONLY positions/states already present in the
// current frame: phantom truth positions (frame.truth.phantoms[].pos) and
// track range estimates (frame.radar.tracks[].rangeEst), plus range rings
// derived from the frame's own radar.identity numbers. No terrain mesh --
// MISSION_SIMULATOR_UI_SPEC.md Section 11 lists terrain as deliberately out
// of scope ("would look like capability you do not have"), so the ground is
// a flat reference grid only. No flight path is scripted here: every marker
// position is read straight from the frame passed in.
//
// HONEST GAP: this project's radar model is 1D (range + radial velocity),
// documented in +missionsim/buildFrameLog.m -- there is no bearing/azimuth
// field anywhere in the schema. Every entity is placed along one fixed,
// ASSUMED bearing (+X), matching truth.phantoms[].pos's own [range,0,0]
// convention. Track markers are drawn at a small fixed height above their
// phantom counterpart purely so the "synth truth vs. radar belief" gap is
// visible -- that vertical offset is a rendering choice, not altitude data.

const SCENE_RADIUS = 210; // rendering canvas scale, not a physical quantity

function droneMesh(color, s = 1) {
  const g = new THREE.Group();
  const mat = new THREE.MeshStandardMaterial({
    color, emissive: color, emissiveIntensity: 0.3, roughness: 0.5, metalness: 0.4, transparent: true,
  });
  g.add(new THREE.Mesh(new THREE.BoxGeometry(2.2 * s, 0.7 * s, 2.8 * s), mat));
  [[-1, -1], [1, -1], [-1, 1], [1, 1]].forEach(([sx, sz]) => {
    const arm = new THREE.Mesh(new THREE.CylinderGeometry(0.16 * s, 0.16 * s, 2.6 * s, 6), mat);
    arm.rotation.z = Math.PI / 2;
    arm.position.set(sx * 1.3 * s, 0, sz * 1.3 * s);
    arm.rotation.y = sx * sz > 0 ? Math.PI / 4 : -Math.PI / 4;
    g.add(arm);
  });
  g.userData.mat = mat;
  return g;
}

function radarEmplacement() {
  const g = new THREE.Group();
  const steel = new THREE.MeshStandardMaterial({ color: 0x2a2f36, roughness: 0.7, metalness: 0.5 });
  const hot = new THREE.MeshStandardMaterial({
    color: 0x9e2a2a, emissive: 0x6a1414, emissiveIntensity: 0.8, roughness: 0.5, side: THREE.DoubleSide,
  });
  const pad = new THREE.Mesh(new THREE.CylinderGeometry(7, 8, 1.2, 24), steel);
  pad.position.y = 0.6; g.add(pad);
  const turret = new THREE.Group(); turret.position.y = 1.2; g.add(turret);
  const cab = new THREE.Mesh(new THREE.BoxGeometry(5, 2.8, 4), steel);
  cab.position.y = 1.4; turret.add(cab);
  const mast = new THREE.Mesh(new THREE.CylinderGeometry(0.55, 0.7, 5.6, 10), steel);
  mast.position.y = 4.8; turret.add(mast);
  const dish = new THREE.Mesh(new THREE.SphereGeometry(5, 26, 16, 0, Math.PI * 2, 0, Math.PI / 2.4), hot);
  dish.rotation.x = Math.PI / 2.5; dish.position.set(0, 9, 1.1); turret.add(dish);
  g.userData.turret = turret;
  g.userData.dish = dish;
  const l = new THREE.PointLight(0xff3535, 2.2, 70); l.position.y = 10; g.add(l);
  return g;
}

export default function Scene3D({ frame, identity }) {
  const mountRef = useRef(null);
  const stateRef = useRef(null);

  // one-time three.js setup
  useEffect(() => {
    const mount = mountRef.current;
    if (!mount) return;
    let W = mount.clientWidth || 800, H = mount.clientHeight || 460;

    const scene = new THREE.Scene();
    scene.background = new THREE.Color('#070b10');
    scene.fog = new THREE.Fog('#070b10', 260, 620);

    const cam = new THREE.PerspectiveCamera(42, W / H, 0.5, 2000);
    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(W, H);
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    mount.appendChild(renderer.domElement);

    scene.add(new THREE.HemisphereLight(0x2a3f52, 0x05070a, 0.9));
    const key = new THREE.DirectionalLight(0x8fb4dd, 0.7);
    key.position.set(-140, 200, 120); scene.add(key);

    // flat reference grid -- explicitly NOT a terrain model (out of scope)
    const grid = new THREE.GridHelper(SCENE_RADIUS * 2.6, 24, 0x24303b, 0x161f27);
    scene.add(grid);

    const ringGroup = new THREE.Group();
    scene.add(ringGroup);

    const radar = radarEmplacement();
    scene.add(radar);

    const markerGroup = new THREE.Group();
    scene.add(markerGroup);

    const target = new THREE.Vector3(SCENE_RADIUS * 0.28, 12, 0);
    const drag = { on: false, x: 0, y: 0, az: 0.55, el: 0.5, dist: 300 };
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
      drag.dist = THREE.MathUtils.clamp(drag.dist + e.deltaY * 0.35, 120, 560);
    };
    el.addEventListener('mousedown', onDown);
    window.addEventListener('mouseup', onUp);
    window.addEventListener('mousemove', onMove);
    el.addEventListener('wheel', onWheel, { passive: false });

    let raf;
    const animate = () => {
      raf = requestAnimationFrame(animate);
      cam.position.set(
        target.x + drag.dist * Math.cos(drag.el) * Math.sin(drag.az),
        target.y + drag.dist * Math.sin(drag.el),
        target.z + drag.dist * Math.cos(drag.el) * Math.cos(drag.az)
      );
      cam.lookAt(target);
      if (radar.userData.turret) radar.userData.turret.rotation.y += 0.004;
      renderer.render(scene, cam);
    };
    animate();

    const onResize = () => {
      W = mount.clientWidth; H = mount.clientHeight;
      cam.aspect = W / H; cam.updateProjectionMatrix(); renderer.setSize(W, H);
    };
    window.addEventListener('resize', onResize);

    stateRef.current = { scene, ringGroup, markerGroup, markers: new Map() };

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

  // per-frame update: pure rendering of already-computed data
  useEffect(() => {
    const st = stateRef.current;
    if (!st || !frame || !identity) return;
    const rangeCellM = identity.rangeCellM?.value ?? 0;
    const unambigM = identity.unambigRangeM?.value ?? 0;
    const ceilM = rangeCellM * 512;
    const worldPerM = ceilM > 0 ? SCENE_RADIUS / ceilM : 0;

    st.ringGroup.clear();
    [
      { r: unambigM * worldPerM, color: 0xffab2e, opacity: 0.55 },
      { r: ceilM * worldPerM, color: 0xff4a4a, opacity: 0.3 },
    ].forEach(({ r, color, opacity }) => {
      if (!(r > 0)) return;
      const pts = [];
      for (let i = 0; i <= 128; i++) {
        const a = (i / 128) * Math.PI * 2;
        pts.push(new THREE.Vector3(Math.cos(a) * r, 0.4, Math.sin(a) * r));
      }
      const line = new THREE.LineLoop(
        new THREE.BufferGeometry().setFromPoints(pts),
        new THREE.LineBasicMaterial({ color, transparent: true, opacity })
      );
      st.ringGroup.add(line);
    });

    const wanted = new Set();

    frame.truth.phantoms.forEach((p) => {
      const key = `phantom:${p.id}`;
      wanted.add(key);
      let mesh = st.markers.get(key);
      if (!mesh) {
        mesh = droneMesh(0xb8c2cc, 0.9);
        st.markerGroup.add(mesh);
        st.markers.set(key, mesh);
      }
      const rangeM = Array.isArray(p.pos) ? p.pos[0] : 0;
      mesh.position.set(rangeM * worldPerM, 0, 0);
    });

    frame.radar.tracks.forEach((tr) => {
      const key = `track:${tr.id}`;
      wanted.add(key);
      let mesh = st.markers.get(key);
      if (!mesh) {
        mesh = new THREE.Mesh(
          new THREE.OctahedronGeometry(2.4),
          new THREE.MeshStandardMaterial({ transparent: true, roughness: 0.4 })
        );
        st.markerGroup.add(mesh);
        st.markers.set(key, mesh);
      }
      const stateColorHex = {
        TENTATIVE: 0x3d4d5b, CONFIRMED: 0xc6d5e0, COASTING: 0xffab2e, DELETED: 0xff4a4a,
      }[tr.state] ?? 0xc6d5e0;
      mesh.material.color.setHex(stateColorHex);
      mesh.material.emissive.setHex(stateColorHex);
      mesh.material.emissiveIntensity = 0.4;
      // opacity fades with consecutive misses, matching Section 7's
      // "trajectory weakens" language and the deleteMofN read straight off
      // this frame's own radar.tracker block (not a hardcoded [5,5]).
      const deleteMiss = frame.radar.tracker?.deleteMofN?.[0] ?? 5;
      const misses = Number.isFinite(tr.misses) ? tr.misses : 0;
      mesh.material.opacity = tr.state === 'DELETED'
        ? 0
        : Math.max(0.15, 1 - misses / Math.max(1, deleteMiss));
      const rangeM = Number.isFinite(tr.rangeEst) ? tr.rangeEst : 0;
      mesh.position.set(rangeM * worldPerM, 6, 0);
    });

    // drop markers for entities no longer present in this frame
    for (const [key, mesh] of st.markers.entries()) {
      if (!wanted.has(key)) {
        st.markerGroup.remove(mesh);
        mesh.geometry?.dispose?.();
        st.markers.delete(key);
      }
    }
  }, [frame, identity]);

  return <div ref={mountRef} style={{ position: 'absolute', inset: 0 }} />;
}
