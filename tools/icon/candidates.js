// Three PubDates icon candidates as SVG, rendered to 1024 px PNG with resvg.
const { Resvg } = require("@resvg/resvg-js");
const fs = require("fs");
const out = process.argv[2];

const AMBER = "#E68A00", AMBER_DEEP = "#B86A00", INK = "#2A1700", CREAM = "rgba(255,255,255,0.42)", FOAM = "#FFFDF6", BEER = "#F5B335";

// A pint: slight taper, rounded bottom corners. Coordinates in a 400x600 box; origin at top-left of the glass.
function pintPath(x, y, w, h) {
  const taper = 0.16 * w, r = 0.13 * w;
  return `M ${x} ${y} L ${x + w} ${y} L ${x + w - taper} ${y + h - r} Q ${x + w - taper} ${y + h} ${x + w - taper - r} ${y + h} L ${x + taper + r} ${y + h} Q ${x + taper} ${y + h} ${x + taper} ${y + h - r} Z`;
}
// Foam: a scalloped band across the glass at `top`, clipped to the glass.
function foamPath(x, y, w, h, level) {
  const top = y + h * (1 - level);
  const band = h * 0.075;
  let d = `M ${x - 20} ${top + band}`;
  const n = 5, seg = (w + 40) / n;
  for (let i = 0; i < n; i++) {
    const sx = x - 20 + i * seg;
    d += ` C ${sx + seg * 0.25} ${top - band * 0.9}, ${sx + seg * 0.75} ${top - band * 0.9}, ${sx + seg} ${top + band * 0.15}`;
  }
  d += ` L ${x + w + 20} ${top + band * 3} L ${x - 20} ${top + band * 3} Z`;
  return d;
}
function glass({ x, y, w, h, level, outline, outlineW, fillGlass, beer, foam, rotate = 0, cx = 0, cy = 0 }) {
  const top = y + h * (1 - level);
  const id = `c${Math.round(x)}${Math.round(rotate)}`;
  return `
  <g transform="rotate(${rotate} ${cx} ${cy})">
    <defs><clipPath id="${id}"><path d="${pintPath(x, y, w, h)}"/></clipPath></defs>
    <path d="${pintPath(x, y, w, h)}" fill="${fillGlass}"/>
    <g clip-path="url(#${id})">
      <rect x="${x - 40}" y="${top}" width="${w + 80}" height="${h}" fill="${beer}"/>
      <rect x="${x + w * 0.16}" y="${top}" width="${w * 0.09}" height="${h}" fill="#FFFFFF" opacity="0.28"/>
      <path d="${foamPath(x, y, w, h, level)}" fill="${foam}"/>
    </g>
    <path d="${pintPath(x, y, w, h)}" fill="none" stroke="${outline}" stroke-width="${outlineW}" stroke-linejoin="round"/>
  </g>`;
}
const bg = (a, b, id) => `<defs><linearGradient id="${id}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${a}"/><stop offset="1" stop-color="${b}"/></linearGradient></defs><rect width="1024" height="1024" fill="url(#${id})"/>`;

const A = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">${bg("#F09A0C", "#DC8000", "gA")}
${glass({ x: 322, y: 205, w: 380, h: 620, level: 0.8, outline: INK, outlineW: 22, fillGlass: CREAM, beer: BEER, foam: FOAM })}
</svg>`;

const B = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">${bg("#C86E00", "#96500A", "gB")}
${glass({ x: 322, y: 205, w: 380, h: 620, level: 0.66, outline: FOAM, outlineW: 30, fillGlass: "rgba(255,255,255,0.10)", beer: "rgba(255,253,246,0.22)", foam: FOAM })}
</svg>`;

const C = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">${bg("#F09A0C", "#DC8000", "gC")}
${glass({ x: 222, y: 300, w: 300, h: 520, level: 0.76, outline: INK, outlineW: 20, fillGlass: CREAM, beer: BEER, foam: FOAM, rotate: 12, cx: 372, cy: 700 })}
${glass({ x: 502, y: 300, w: 300, h: 520, level: 0.76, outline: INK, outlineW: 20, fillGlass: CREAM, beer: BEER, foam: FOAM, rotate: -12, cx: 652, cy: 700 })}
<g fill="${FOAM}"><path d="M512 150 l14 42 42 14 -42 14 -14 42 -14 -42 -42 -14 42 -14 Z"/><path d="M400 215 l8 24 24 8 -24 8 -8 24 -8 -24 -24 -8 24 -8 Z"/><path d="M624 215 l8 24 24 8 -24 8 -8 24 -8 -24 -24 -8 24 -8 Z"/></g>
</svg>`;

for (const [name, svg] of [["icon-A-pint", A], ["icon-B-lineart", B], ["icon-C-cheers", C]]) {
  fs.writeFileSync(`${out}/${name}.svg`, svg);
  const png = new Resvg(svg, { fitTo: { mode: "width", value: 1024 } }).render().asPng();
  fs.writeFileSync(`${out}/${name}.png`, png);
}
console.log("rendered");
