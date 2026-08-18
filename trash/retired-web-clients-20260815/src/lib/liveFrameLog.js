// Polls a growing NDJSON file (one JSON frame object per line, written by
// missionsim.streamManualSceneToFile) and reports newly-arrived frames.
// Pure data plumbing -- no detection/tracking/physics computation, same
// boundary frameLog.js already holds for the static-log path.
import { normalizeFrame } from './frameLog.js';

const END_MARKER = '__end__';

export function pollLiveLog(url, { onFrames, onDone, onError, intervalMs = 500 }) {
  let stopped = false;
  let linesConsumed = 0;
  let timer = null;

  async function tick() {
    if (stopped) return;
    try {
      const res = await fetch(`${url}?t=${Date.now()}`, { cache: 'no-store' });
      if (res.ok) {
        const text = await res.text();
        const lines = text.split('\n').map((l) => l.trim()).filter(Boolean);
        if (lines.length > linesConsumed) {
          const newLines = lines.slice(linesConsumed);
          linesConsumed = lines.length;
          const newFrames = [];
          let done = false;
          for (const line of newLines) {
            let obj;
            try {
              obj = JSON.parse(line);
            } catch {
              continue; // a line caught mid-write by the poll; picked up whole next tick
            }
            if (obj && obj.marker === END_MARKER) {
              done = true;
              continue;
            }
            newFrames.push(normalizeFrame(obj));
          }
          if (newFrames.length) onFrames(newFrames);
          if (done) {
            stop();
            onDone?.();
            return;
          }
        }
      }
    } catch (err) {
      onError?.(err);
    }
    timer = setTimeout(tick, intervalMs);
  }

  function stop() {
    stopped = true;
    if (timer) clearTimeout(timer);
  }

  tick();
  return stop;
}
