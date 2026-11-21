// Generates Reminder/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
// (1024×1024, opaque RGB) with no dependencies. Run: node scripts/gen-icon.mjs
import { writeFileSync } from "node:fs";
import { deflateSync } from "node:zlib";

const SIZE = 1024;
const MINT = [0x2b, 0xb5, 0xa0];
const MINT_LIGHT = [0xd5, 0xf2, 0xec];
const WHITE = [0xff, 0xff, 0xff];

// Calendar card
const card = { x0: 232, y0: 252, x1: 792, y1: 812, r: 96 };
const bandBottom = 380;
// Check mark
const check = [[386, 592], [480, 686], [652, 508]];
const checkHalfWidth = 30;

function insideRoundedRect(x, y, { x0, y0, x1, y1, r }) {
  if (x < x0 || x > x1 || y < y0 || y > y1) return false;
  const cx = Math.min(Math.max(x, x0 + r), x1 - r);
  const cy = Math.min(Math.max(y, y0 + r), y1 - r);
  return (x - cx) ** 2 + (y - cy) ** 2 <= r * r;
}

function distToSegment(px, py, [ax, ay], [bx, by]) {
  const dx = bx - ax, dy = by - ay;
  const t = Math.max(0, Math.min(1, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)));
  return Math.hypot(px - (ax + t * dx), py - (ay + t * dy));
}

function colorAt(x, y) {
  if (!insideRoundedRect(x, y, card)) return MINT;
  for (let i = 0; i < check.length - 1; i++) {
    if (distToSegment(x, y, check[i], check[i + 1]) <= checkHalfWidth) return MINT;
  }
  return y < bandBottom ? MINT_LIGHT : WHITE;
}

// 4×4 supersampling for anti-aliasing
const SS = 4;
const raw = Buffer.alloc(SIZE * (SIZE * 3 + 1));
let o = 0;
for (let y = 0; y < SIZE; y++) {
  raw[o++] = 0; // filter: none
  for (let x = 0; x < SIZE; x++) {
    let r = 0, g = 0, b = 0;
    for (let sy = 0; sy < SS; sy++) {
      for (let sx = 0; sx < SS; sx++) {
        const c = colorAt(x + (sx + 0.5) / SS, y + (sy + 0.5) / SS);
        r += c[0]; g += c[1]; b += c[2];
      }
    }
    const n = SS * SS;
    raw[o++] = Math.round(r / n);
    raw[o++] = Math.round(g / n);
    raw[o++] = Math.round(b / n);
  }
}

const crcTable = Array.from({ length: 256 }, (_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});
function crc32(buf) {
  let c = 0xffffffff;
  for (const byte of buf) c = crcTable[(c ^ byte) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, "ascii"), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([len, body, crc]);
}

const ihdr = Buffer.alloc(13);
ihdr.writeUInt32BE(SIZE, 0);
ihdr.writeUInt32BE(SIZE, 4);
ihdr[8] = 8;  // bit depth
ihdr[9] = 2;  // color type: RGB (no alpha)
const png = Buffer.concat([
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  chunk("IHDR", ihdr),
  chunk("IDAT", deflateSync(raw, { level: 9 })),
  chunk("IEND", Buffer.alloc(0)),
]);

const out = new URL("../Reminder/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png", import.meta.url);
writeFileSync(out, png);
console.log(`wrote ${out.pathname} (${png.length} bytes)`);
