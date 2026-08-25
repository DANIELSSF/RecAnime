// Generates the RecAnime design canvas artboards (.dc.html) from shared tokens and
// components so every screen uses the exact same palette, type ramp and glass recipe.
// Usage: node docs/design/build-canvas.mjs  -> writes docs/design/canvas/*.dc.html + canvas.json
import { writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const OUT = join(dirname(fileURLToPath(import.meta.url)), "canvas");
mkdirSync(OUT, { recursive: true });

// ---------------------------------------------------------------------------
// Tokens (single source of truth for the mockups; mirrors packages/RecAnimeUI/Theme)
// ---------------------------------------------------------------------------
const PHONE = { w: 402, h: 874 }; // iPhone 17 Pro logical points
const WATCH = { w: 416, h: 496 }; // Apple Watch 46 mm logical points

const CSS = `
  * { box-sizing: border-box; }
  body { margin: 0; background: transparent; }
  a { color: #FF4B58; text-decoration: none; } a:hover { color: #EF3B47; }
  .root {
    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", system-ui, sans-serif;
    -webkit-font-smoothing: antialiased; position: relative; overflow: hidden;
    color: var(--label); background: var(--bg);
  }
  .dark {
    --bg: #000000; --bg2: #1C1C1E; --bg3: #2C2C2E;
    --label: #FFFFFF; --label2: rgba(235,235,245,0.60); --label3: rgba(235,235,245,0.30);
    --sep: rgba(84,84,88,0.65); --fill: rgba(120,120,128,0.24); --fill2: rgba(120,120,128,0.16);
    --accent: #FF4B58; --accent-deep: #C92935; --accent-soft: rgba(255,75,88,0.18);
    --pending: #BD9A9E; --watched: #FF8552; --favorite: #FF63A3;
    --glass-bg: rgba(255,255,255,0.10); --glass-border: rgba(255,255,255,0.16);
    --glass-hi: rgba(255,255,255,0.22); --glass-shadow: rgba(0,0,0,0.45);
    --glass-sel: rgba(255,255,255,0.18);
  }
  .light {
    --bg: #FFFFFF; --bg2: #F2F2F7; --bg3: #E5E5EA;
    --label: #000000; --label2: rgba(60,60,67,0.60); --label3: rgba(60,60,67,0.30);
    --sep: rgba(60,60,67,0.29); --fill: rgba(120,120,128,0.20); --fill2: rgba(120,120,128,0.12);
    --accent: #EF3B47; --accent-deep: #B9202C; --accent-soft: rgba(239,59,71,0.14);
    --pending: #B08A8E; --watched: #F2703C; --favorite: #F0468C;
    --glass-bg: rgba(255,255,255,0.55); --glass-border: rgba(255,255,255,0.75);
    --glass-hi: rgba(255,255,255,0.9); --glass-shadow: rgba(0,0,0,0.14);
    --glass-sel: rgba(255,255,255,0.85);
  }
  .glass {
    background: var(--glass-bg);
    -webkit-backdrop-filter: blur(24px) saturate(170%); backdrop-filter: blur(24px) saturate(170%);
    border: 1px solid var(--glass-border);
    box-shadow: 0 10px 30px var(--glass-shadow), inset 0 1px 0 var(--glass-hi);
  }
  .capsule { border-radius: 999px; }
  .lt { font-size: 34px; line-height: 41px; font-weight: 700; letter-spacing: 0.37px; }
  .t1 { font-size: 28px; line-height: 34px; font-weight: 700; }
  .t2 { font-size: 22px; line-height: 28px; font-weight: 700; }
  .t3 { font-size: 20px; line-height: 25px; font-weight: 600; }
  .hl { font-size: 17px; line-height: 22px; font-weight: 600; }
  .body { font-size: 17px; line-height: 22px; }
  .sub { font-size: 15px; line-height: 20px; }
  .fn { font-size: 13px; line-height: 18px; }
  .c1 { font-size: 12px; line-height: 16px; }
  .c2 { font-size: 11px; line-height: 13px; }
  .sec { color: var(--label2); }
  .ter { color: var(--label3); }
  .mono { font-variant-numeric: tabular-nums; }
  .row { display: flex; align-items: center; }
  .col { display: flex; flex-direction: column; }
  .clamp2 { display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
  .clamp3 { display: -webkit-box; -webkit-line-clamp: 3; -webkit-box-orient: vertical; overflow: hidden; }
  .poster { border-radius: 12px; position: relative; overflow: hidden; flex: none;
    box-shadow: 0 2px 8px rgba(0,0,0,0.25); }
  .poster::after { content: ""; position: absolute; inset: 0;
    background: radial-gradient(120% 80% at 20% 0%, rgba(255,255,255,0.28), rgba(255,255,255,0) 55%),
                linear-gradient(180deg, rgba(0,0,0,0) 45%, rgba(0,0,0,0.35) 100%); }
  .hair { height: 0.5px; background: var(--sep); }
  .progress { height: 4px; border-radius: 2px; background: var(--fill); overflow: hidden; }
  .progress > div { height: 100%; border-radius: 2px;
    background: linear-gradient(90deg, var(--accent), var(--watched)); }
  .badge { display: inline-flex; align-items: center; height: 20px; padding: 0 8px; border-radius: 999px;
    font-size: 11px; font-weight: 600; line-height: 13px; }
  .chip { display: inline-flex; align-items: center; height: 36px; padding: 0 14px; font-size: 15px;
    font-weight: 600; line-height: 20px; color: var(--label); white-space: nowrap; }
  .chip.sel { background: var(--accent); border-color: transparent; color: #FFFFFF;
    box-shadow: 0 6px 18px rgba(239,59,71,0.35), inset 0 1px 0 rgba(255,255,255,0.35); }
  .icon { width: 24px; height: 24px; flex: none; }
  .avatar { width: 32px; height: 32px; border-radius: 16px; display: flex; align-items: center;
    justify-content: center; font-size: 14px; font-weight: 700; color: #FFFFFF;
    background: linear-gradient(135deg, #FF4B58, #B9202C); }
`;

// Poster placeholders: muted duotone fills standing in for MAL artwork (no real images).
const ART = {
  frieren: "linear-gradient(160deg, #6D7FE0 0%, #2C3A78 60%, #1B2350 100%)",
  frieren2: "linear-gradient(160deg, #8FA0F0 0%, #3A4C9A 60%, #1F2A5E 100%)",
  onepiece: "linear-gradient(160deg, #E8A24B 0%, #9B4B2A 60%, #4B2417 100%)",
  jjk: "linear-gradient(160deg, #3E4A8F 0%, #1D2352 60%, #0E1130 100%)",
  dandadan: "linear-gradient(160deg, #D65C8B 0%, #6B2A66 60%, #2E1240 100%)",
  kaiju: "linear-gradient(160deg, #6FB1B8 0%, #2C5D6B 60%, #12303A 100%)",
  oshi: "linear-gradient(160deg, #C46BD8 0%, #5F2E8F 60%, #2A1447 100%)",
  spy: "linear-gradient(160deg, #B8B5C9 0%, #5A5872 60%, #2B2A3A 100%)",
  csm: "linear-gradient(160deg, #D9573F 0%, #6E2A22 60%, #2E1210 100%)",
  vinland: "linear-gradient(160deg, #7C9AA8 0%, #354B57 60%, #17262E 100%)",
  mushoku: "linear-gradient(160deg, #7DB889 0%, #2F5A46 60%, #142A22 100%)",
  fma: "linear-gradient(160deg, #C9A24E 0%, #6B4E1E 60%, #2E2110 100%)",
  steins: "linear-gradient(160deg, #A9B4B8 0%, #4A555C 60%, #1E2629 100%)",
  gintama: "linear-gradient(160deg, #8CB0E6 0%, #3B5A8C 60%, #1A2A45 100%)",
  snk: "linear-gradient(160deg, #8A7A5E 0%, #3E3527 60%, #1B1710 100%)",
  hxh: "linear-gradient(160deg, #5FB57A 0%, #2A5F3B 60%, #12301C 100%)",
  hero: "linear-gradient(160deg, #E6764A 0%, #8C3A1E 60%, #3E1A0E 100%)",
};

const poster = (art, w, h, radius = 12) =>
  `<div class="poster" style="width: ${w}px; height: ${h}px; border-radius: ${radius}px; background: ${ART[art]};"></div>`;

// ---------------------------------------------------------------------------
// Icons: stroke-based inline SVG on a 24 px grid (SF Symbols stand-ins)
// ---------------------------------------------------------------------------
const svg = (paths, extra = "") => {
  const width = extra.includes("stroke-width") ? "" : ' stroke-width="1.8"';
  return `<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor"${width} stroke-linecap="round" stroke-linejoin="round" ${extra}>${paths}</svg>`;
};
const ICON = {
  calendar: svg('<rect x="3.5" y="5" width="17" height="15" rx="3"></rect><path d="M3.5 10h17M8 3v4M16 3v4"></path>'),
  trophy: svg('<path d="M8 4h8v5a4 4 0 0 1-8 0V4z"></path><path d="M8 6H5.5a2.5 2.5 0 0 0 0 5H8M16 6h2.5a2.5 2.5 0 0 1 0 5H16"></path><path d="M12 13v4M8.5 20h7M10 17h4"></path>'),
  sparkles: svg('<path d="M12 3l1.8 4.7L18.5 9.5l-4.7 1.8L12 16l-1.8-4.7L5.5 9.5l4.7-1.8L12 3z"></path><path d="M19 15l.9 2.1L22 18l-2.1.9L19 21l-.9-2.1L16 18l2.1-.9L19 15z"></path>'),
  bookmark: svg('<path d="M7 4.5h10a1 1 0 0 1 1 1V20l-6-3.5L6 20V5.5a1 1 0 0 1 1-1z"></path>'),
  search: svg('<circle cx="11" cy="11" r="6.5"></circle><path d="M16 16l4 4"></path>'),
  plus: svg('<path d="M12 5v14M5 12h14"></path>'),
  minus: svg('<path d="M5 12h14"></path>'),
  heart: svg('<path d="M12 20s-7-4.4-7-9.5A4 4 0 0 1 12 8a4 4 0 0 1 7 2.5C19 15.6 12 20 12 20z"></path>'),
  heartFill: svg('<path d="M12 20s-7-4.4-7-9.5A4 4 0 0 1 12 8a4 4 0 0 1 7 2.5C19 15.6 12 20 12 20z" fill="currentColor"></path>'),
  chevron: svg('<path d="M9 6l6 6-6 6"></path>'),
  back: svg('<path d="M15 5l-7 7 7 7"></path>', 'stroke-width="2.2"'),
  more: svg('<circle cx="6" cy="12" r="1.4" fill="currentColor" stroke="none"></circle><circle cx="12" cy="12" r="1.4" fill="currentColor" stroke="none"></circle><circle cx="18" cy="12" r="1.4" fill="currentColor" stroke="none"></circle>'),
  star: svg('<path d="M12 3.5l2.6 5.4 5.9.8-4.3 4.1 1.1 5.9L12 16.9l-5.3 2.8 1.1-5.9-4.3-4.1 5.9-.8L12 3.5z" fill="currentColor" stroke="none"></path>'),
  arrow: svg('<path d="M5 12h14M13 6l6 6-6 6"></path>'),
  play: svg('<path d="M8 6v12l10-6-10-6z" fill="currentColor" stroke="none"></path>'),
  clock: svg('<circle cx="12" cy="12" r="8.5"></circle><path d="M12 7.5V12l3 2"></path>'),
  check: svg('<path d="M5 12.5l4.5 4.5L19 7.5"></path>', 'stroke-width="2.2"'),
  google: `<svg class="icon" viewBox="0 0 24 24" width="20" height="20"><path fill="#4285F4" d="M21.6 12.23c0-.68-.06-1.33-.17-1.96H12v3.7h5.38a4.6 4.6 0 0 1-2 3.02v2.5h3.23c1.89-1.74 2.99-4.3 2.99-7.26z"></path><path fill="#34A853" d="M12 22c2.7 0 4.96-.9 6.61-2.42l-3.23-2.5c-.9.6-2.04.95-3.38.95-2.6 0-4.8-1.75-5.59-4.11H3.08v2.58A10 10 0 0 0 12 22z"></path><path fill="#FBBC05" d="M6.41 13.92A6 6 0 0 1 6.1 12c0-.67.11-1.31.31-1.92V7.5H3.08A10 10 0 0 0 2 12c0 1.61.39 3.14 1.08 4.5l3.33-2.58z"></path><path fill="#EA4335" d="M12 5.97c1.47 0 2.79.5 3.83 1.5l2.87-2.87A9.6 9.6 0 0 0 12 2 10 10 0 0 0 3.08 7.5l3.33 2.58C7.2 7.72 9.4 5.97 12 5.97z"></path></svg>`,
};

// ---------------------------------------------------------------------------
// Shared iPhone chrome
// ---------------------------------------------------------------------------
const TABS = [
  ["Temporada", "calendar"],
  ["Top", "trophy"],
  ["Recomendados", "sparkles"],
  ["Mi lista", "bookmark"],
];

function tabBar(selected) {
  const items = TABS.map(([label, icon]) => {
    const on = label === selected;
    return `<div class="col" style="align-items: center; justify-content: center; gap: 3px; width: 72px; height: 52px; border-radius: 26px; ${on ? "background: var(--glass-sel);" : ""} color: ${on ? "var(--accent)" : "var(--label2)"};">
        ${ICON[icon]}<span class="c2" style="font-weight: 600;">${label}</span></div>`;
  }).join("");
  return `
  <div class="row" style="position: absolute; left: 12px; right: 12px; bottom: 44px; gap: 10px; align-items: flex-end;">
    <div class="glass capsule row" style="flex: 1; height: 64px; padding: 6px 8px; justify-content: space-between;">${items}</div>
    <div class="glass row" style="width: 64px; height: 64px; border-radius: 32px; justify-content: center; color: var(--label);">${ICON.search}</div>
  </div>`;
}

function nowWatchingBar({ inline = false } = {}) {
  const inner = `
    ${poster("frieren2", 36, 36, 8)}
    <div class="col" style="flex: 1; min-width: 0; gap: 1px;">
      ${inline ? "" : '<span class="c2 sec" style="font-weight: 600; letter-spacing: 0.3px;">VIENDO AHORA</span>'}
      <span class="sub" style="font-weight: 600; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">Frieren 2nd Season <span class="sec mono">· ep 7/24</span></span>
    </div>
    <div class="row" style="width: 34px; height: 34px; border-radius: 17px; justify-content: center; color: var(--accent); background: var(--accent-soft);">${ICON.plus}</div>`;
  if (inline) {
    // Tab bar minimized on scroll: current tab collapses to a small pill, accessory goes inline.
    return `
    <div class="row" style="position: absolute; left: 12px; right: 12px; bottom: 44px; gap: 10px;">
      <div class="glass row" style="width: 64px; height: 56px; border-radius: 28px; justify-content: center; color: var(--accent);">${ICON.bookmark}</div>
      <div class="glass capsule row" style="flex: 1; height: 56px; padding: 0 12px 0 10px; gap: 10px;">${inner}</div>
    </div>`;
  }
  return `
  <div class="glass capsule row" style="position: absolute; left: 12px; right: 12px; bottom: 118px; height: 58px; padding: 0 12px 0 10px; gap: 10px;">${inner}</div>`;
}

// System chrome (status bar, home indicator, keyboard) is never drawn: iOS renders it on top.
const homeIndicator = "";

function largeTitle(title, subtitle, { avatar = true } = {}) {
  return `
  <div class="row" style="padding: 62px 16px 0 16px; justify-content: space-between; align-items: flex-end;">
    <div class="col" style="gap: 2px;">
      <span class="lt">${title}</span>
      ${subtitle ? `<span class="sub sec" style="font-weight: 500;">${subtitle}</span>` : ""}
    </div>
    ${avatar ? '<div class="avatar" style="margin-bottom: 8px;">D</div>' : ""}
  </div>`;
}

function sectionHeader(title, action = "Ver todo") {
  return `
  <div class="row" style="padding: 0 16px; justify-content: space-between; align-items: baseline;">
    <span class="t2">${title}</span>
    ${action ? `<span class="sub" style="color: var(--accent); font-weight: 500;">${action}</span>` : ""}
  </div>`;
}

const scoreLabel = (score, size = "fn") =>
  `<span class="row sec ${size} mono" style="gap: 3px;"><span style="display: inline-flex; width: 14px; height: 14px;">${ICON.star.replace('class="icon"', 'class="icon" style="width: 14px; height: 14px;"')}</span>${score}</span>`;

const statusBadge = (label, token) =>
  `<span class="badge" style="background: color-mix(in srgb, var(--${token}) 16%, transparent); color: var(--${token});">${label}</span>`;

// ---------------------------------------------------------------------------
// Artboard shell
// ---------------------------------------------------------------------------
function artboard(theme, size, body, extraCss = "") {
  return `<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
  <style>${CSS}${extraCss}</style>
</helmet>
<div class="root ${theme}" style="width: ${size.w}px; height: ${size.h}px;">
${body}
</div>
</x-dc>
</body>
</html>
`;
}

// ---------------------------------------------------------------------------
// Screens
// ---------------------------------------------------------------------------
function loginScreen(theme) {
  const body = `
  <div style="position: absolute; inset: 0; background: radial-gradient(60% 40% at 50% 18%, rgba(239,59,71,0.55), rgba(239,59,71,0) 70%);"></div>
  <div class="col" style="position: absolute; inset: 0; align-items: center; justify-content: center; gap: 0; padding: 0 32px;">
    <div class="row" style="width: 96px; height: 96px; border-radius: 26px; justify-content: center; color: #FFFFFF; background: linear-gradient(135deg, #FF4B58, #B9202C); box-shadow: 0 18px 40px rgba(239,59,71,0.35), inset 0 1px 0 rgba(255,255,255,0.4);">
      <svg viewBox="0 0 24 24" width="52" height="52" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M7 4.5h10a1 1 0 0 1 1 1V20l-6-3.5L6 20V5.5a1 1 0 0 1 1-1z"></path><path d="M9.5 9.5h5M9.5 12.5h3"></path></svg>
    </div>
    <span class="lt" style="margin-top: 28px;">RecAnime</span>
    <span class="body sec" style="margin-top: 8px; text-align: center; text-wrap: pretty;">Tu seguimiento de anime, en el bolsillo y en la muñeca.</span>
  </div>
  <div class="col" style="position: absolute; left: 24px; right: 24px; bottom: 64px; gap: 16px; align-items: center;">
    <div class="glass capsule row" style="width: 100%; height: 54px; justify-content: center; gap: 10px; background: rgba(255,255,255,0.92); color: #000000; border-color: rgba(255,255,255,0.95);">
      ${ICON.google}<span class="hl">Continuar con Google</span>
    </div>
    <span class="c1 ter" style="text-align: center; text-wrap: pretty;">Solo para las dos cuentas autorizadas. Los datos de anime provienen de MyAnimeList vía Jikan.</span>
  </div>
  ${homeIndicator}`;
  return artboard(theme, PHONE, body);
}

function seasonScreen(theme) {
  const cont = [
    ["frieren2", "Sousou no Frieren 2nd Season", 7, 24],
    ["onepiece", "One Piece", 1122, 0],
    ["jjk", "Jujutsu Kaisen 3rd Season", 3, 24],
  ].map(([art, title, ep, total]) => {
    const pct = total ? Math.round((ep / total) * 100) : 62;
    return `<div class="col" style="width: 110px; gap: 8px; flex: none;">
      ${poster(art, 110, 165)}
      <div class="progress"><div style="width: ${pct}%;"></div></div>
      <span class="fn clamp2" style="font-weight: 600;">${title}</span>
      <span class="c1 sec mono" style="margin-top: -6px;">${total ? `ep ${ep}/${total}` : `ep ${ep}`}</span>
    </div>`;
  }).join("");

  const carousel = (items) =>
    items.map(([art, title, meta]) => `<div class="col" style="width: 140px; gap: 8px; flex: none;">
      ${poster(art, 140, 210)}
      <span class="sub clamp2" style="font-weight: 600;">${title}</span>
      <span class="fn sec" style="margin-top: -6px;">${meta}</span>
    </div>`).join("");

  const body = `
  ${largeTitle("Temporada", "Verano 2026")}
  <div class="col" style="gap: 24px; padding-top: 22px;">
    <div class="col" style="gap: 12px;">
      ${sectionHeader("Sigue viendo", "")}
      <div class="row" style="gap: 12px; padding: 0 16px; align-items: flex-start;">${cont}</div>
    </div>
    <div class="col" style="gap: 12px;">
      ${sectionHeader("Esta temporada")}
      <div class="row" style="gap: 12px; padding: 0 16px; align-items: flex-start;">${carousel([
        ["dandadan", "Dandadan 3rd Season", "TV · 12 ep"],
        ["kaiju", "Kaijuu 8-gou Season 3", "TV · 12 ep"],
        ["oshi", "Oshi no Ko 4th Season", "TV · 13 ep"],
      ])}</div>
    </div>
    <div class="col" style="gap: 12px;">
      ${sectionHeader("Próximamente")}
      <div class="row" style="gap: 12px; padding: 0 16px; align-items: flex-start;">${carousel([
        ["spy", "Spy x Family Season 4", "Otoño 2026"],
        ["csm", "Chainsaw Man Part 2", "Otoño 2026"],
        ["vinland", "Vinland Saga Season 3", "2027"],
      ])}</div>
    </div>
  </div>
  <div style="position: absolute; left: 0; right: 0; bottom: 0; height: 240px; background: linear-gradient(180deg, rgba(0,0,0,0), var(--bg) 70%); pointer-events: none; opacity: 0.9;"></div>
  ${nowWatchingBar()}
  ${tabBar("Temporada")}
  ${homeIndicator}`;
  return artboard(theme, PHONE, body);
}

function topScreen(theme) {
  const rows = [
    ["frieren", "Sousou no Frieren", "9.30", "TV · 28 ep · 2023"],
    ["fma", "Fullmetal Alchemist: Brotherhood", "9.10", "TV · 64 ep · 2009"],
    ["steins", "Steins;Gate", "9.07", "TV · 24 ep · 2011"],
    ["gintama", "Gintama°", "9.06", "TV · 51 ep · 2015"],
    ["snk", "Shingeki no Kyojin Season 3 Part 2", "9.05", "TV · 10 ep · 2019"],
    ["hxh", "Hunter x Hunter (2011)", "9.03", "TV · 148 ep · 2011"],
    ["onepiece", "One Piece", "8.74", "TV · En emisión · 1999"],
  ].map(([art, title, score, meta], i) => `
    <div class="col">
      <div class="row" style="gap: 12px; padding: 10px 16px; min-height: 104px;">
        <span class="t3 sec mono" style="width: 28px; text-align: center; font-weight: 700;">${i + 1}</span>
        ${poster(art, 56, 84, 8)}
        <div class="col" style="flex: 1; min-width: 0; gap: 4px;">
          <span class="hl clamp2">${title}</span>
          <span class="fn sec">${meta}</span>
          ${scoreLabel(score)}
        </div>
        <span class="sec" style="display: inline-flex;">${ICON.chevron}</span>
      </div>
      <div class="hair" style="margin-left: 112px;"></div>
    </div>`).join("");

  const chips = ["Puntuación", "Emisión", "Próximos", "Populares", "Favoritos"]
    .map((c, i) => `<div class="glass capsule chip ${i === 0 ? "sel" : ""}">${c}</div>`).join("");

  const body = `
  ${largeTitle("Top", "")}
  <div class="row" style="gap: 8px; padding: 14px 16px 10px 16px; overflow: hidden;">${chips}</div>
  <div class="col" style="padding-top: 4px;">${rows}</div>
  <div style="position: absolute; left: 0; right: 0; bottom: 0; height: 220px; background: linear-gradient(180deg, rgba(0,0,0,0), var(--bg) 75%); pointer-events: none; opacity: 0.9;"></div>
  ${nowWatchingBar()}
  ${tabBar("Top")}
  ${homeIndicator}`;
  return artboard(theme, PHONE, body);
}

function recommendationsScreen(theme) {
  const card = (a, at, b, bt, text, user, date) => `
    <div class="col" style="margin: 0 16px; padding: 14px; gap: 12px; border-radius: 16px; background: var(--bg2);">
      <span class="c1 sec" style="font-weight: 600; letter-spacing: 0.3px;">SI TE GUSTÓ · TE GUSTARÁ</span>
      <div class="row" style="gap: 12px; align-items: flex-start;">
        <div class="col" style="width: 100px; gap: 6px;">${poster(a, 100, 150)}<span class="fn clamp2" style="font-weight: 600;">${at}</span></div>
        <div class="row" style="height: 150px; align-items: center; color: var(--accent);">${ICON.arrow}</div>
        <div class="col" style="width: 100px; gap: 6px;">${poster(b, 100, 150)}<span class="fn clamp2" style="font-weight: 600;">${bt}</span></div>
      </div>
      <span class="sub clamp3" style="color: var(--label); text-wrap: pretty;">${text}</span>
      <span class="c1 ter">por ${user} · ${date}</span>
    </div>`;

  const body = `
  ${largeTitle("Recomendados", "Comunidad de MyAnimeList · en vivo")}
  <div class="col" style="gap: 14px; padding-top: 18px;">
    ${card("frieren", "Sousou no Frieren", "mushoku", "Mushoku Tensei", "Both follow a slow, contemplative journey through a fantasy world where the passage of time and the relationships left behind matter more than the fights.", "aoi_k", "hoy")}
    ${card("csm", "Chainsaw Man", "jjk", "Jujutsu Kaisen", "Dark urban fantasy with a reluctant protagonist, gruesome monsters and studio-level animation. If one hooked you, the other will.", "renji", "ayer")}
    ${card("vinland", "Vinland Saga", "snk", "Shingeki no Kyojin", "Historical weight, moral ambiguity and characters that change with the war around them.", "mika", "hace 2 días")}
  </div>
  <div style="position: absolute; left: 0; right: 0; bottom: 0; height: 220px; background: linear-gradient(180deg, rgba(0,0,0,0), var(--bg) 75%); pointer-events: none; opacity: 0.9;"></div>
  ${nowWatchingBar()}
  ${tabBar("Recomendados")}
  ${homeIndicator}`;
  return artboard(theme, PHONE, body);
}

function libraryScreen(theme) {
  const seg = ["Favoritos", "Pendientes", "Viendo", "Vistos"]
    .map((s, i) => `<div class="row fn" style="flex: 1; height: 32px; justify-content: center; border-radius: 16px; font-weight: 600; ${i === 2 ? "background: var(--glass-sel); color: var(--label); box-shadow: 0 2px 8px rgba(0,0,0,0.2);" : "color: var(--label2);"}">${s}</div>`).join("");

  const rows = [
    ["frieren2", "Sousou no Frieren 2nd Season", 7, 24, true],
    ["onepiece", "One Piece", 1122, 0, true],
    ["jjk", "Jujutsu Kaisen 3rd Season", 3, 24, false],
    ["kaiju", "Kaijuu 8-gou Season 3", 5, 12, false],
    ["dandadan", "Dandadan 3rd Season", 2, 12, false],
    ["oshi", "Oshi no Ko 4th Season", 1, 13, true],
  ].map(([art, title, ep, total, fav]) => {
    const pct = total ? Math.round((ep / total) * 100) : 62;
    return `
    <div class="col">
      <div class="row" style="gap: 12px; padding: 10px 16px;">
        ${poster(art, 56, 84, 8)}
        <div class="col" style="flex: 1; min-width: 0; gap: 6px;">
          <span class="hl clamp2">${title}</span>
          <div class="row" style="gap: 8px;">${statusBadge("Viendo", "accent")}<span class="fn sec mono">${total ? `ep ${ep}/${total}` : `ep ${ep}`}</span></div>
          <div class="progress" style="width: 100%;"><div style="width: ${pct}%;"></div></div>
        </div>
        <span style="display: inline-flex; color: ${fav ? "var(--favorite)" : "var(--label3)"};">${fav ? ICON.heartFill : ICON.heart}</span>
      </div>
      <div class="hair" style="margin-left: 84px;"></div>
    </div>`;
  }).join("");

  const body = `
  ${largeTitle("Mi lista", "")}
  <div class="col" style="padding: 14px 16px 6px 16px; gap: 10px;">
    <div class="glass capsule row" style="height: 40px; padding: 4px; gap: 2px;">${seg}</div>
    <span class="fn sec" style="padding-left: 4px;">6 series</span>
  </div>
  <div class="col">${rows}</div>
  <div style="position: absolute; left: 0; right: 0; bottom: 0; height: 220px; background: linear-gradient(180deg, rgba(0,0,0,0), var(--bg) 75%); pointer-events: none; opacity: 0.9;"></div>
  ${nowWatchingBar()}
  ${tabBar("Mi lista")}
  ${homeIndicator}`;
  return artboard(theme, PHONE, body);
}

function detailScreen(theme) {
  const chain = [
    ["frieren", "T1 · 2023", "28 ep · Visto", "watched"],
    ["frieren2", "T2 · 2026", "24 ep", "current"],
    ["frieren", "Película", "2027", "next"],
  ].map(([art, cap, cap2, kind]) => `
    <div class="col" style="width: 90px; gap: 6px; flex: none;">
      <div style="position: relative;">
        <div style="border-radius: 12px; ${kind === "current" ? "box-shadow: 0 0 0 2px var(--accent);" : ""}">${poster(art, 90, 135, 12)}</div>
        ${kind === "current" ? '<div class="row" style="position: absolute; left: 6px; bottom: 6px; height: 20px; padding: 0 7px; border-radius: 10px; background: var(--accent); color: #FFFFFF;"><span class="c2" style="font-weight: 700;">Estás aquí</span></div>' : ""}
        ${kind === "next" ? '<div class="row" style="position: absolute; left: 6px; bottom: 6px; height: 20px; padding: 0 7px; border-radius: 10px; background: var(--bg3); color: var(--label);"><span class="c2" style="font-weight: 700;">Siguiente</span></div>' : ""}
        ${kind === "watched" ? '<div class="row" style="position: absolute; right: 6px; top: 6px; width: 18px; height: 18px; border-radius: 9px; background: var(--watched); color: #FFFFFF; justify-content: center;">' + ICON.check.replace('class="icon"', 'class="icon" style="width: 12px; height: 12px;"') + '</div>' : ""}
      </div>
      <span class="c1" style="font-weight: 600; white-space: nowrap;">${cap}</span>
      <span class="c1 sec" style="margin-top: -4px; white-space: nowrap;">${cap2}</span>
    </div>`).join("");

  const infoCell = (k, v) => `<div class="col" style="gap: 2px;"><span class="c1 sec" style="font-weight: 600; letter-spacing: 0.3px; text-transform: uppercase;">${k}</span><span class="sub">${v}</span></div>`;

  const body = `
  <!-- Hero: the large poster feeds a mirrored, blurred extension behind the toolbar area (backgroundExtensionEffect) -->
  <div style="position: absolute; left: 0; right: 0; top: 0; height: 470px; overflow: hidden;">
    <div style="position: absolute; inset: -40px; background: ${ART.frieren2}; filter: blur(28px) saturate(140%); opacity: 0.9; transform: scale(1.1);"></div>
    <div style="position: absolute; left: 0; right: 0; top: 0; height: 470px; background: ${ART.frieren2}; background-blend-mode: multiply;"></div>
    <div style="position: absolute; inset: 0; background: radial-gradient(90% 60% at 30% 10%, rgba(255,255,255,0.22), rgba(255,255,255,0) 60%), linear-gradient(180deg, rgba(0,0,0,0) 40%, var(--bg) 100%);"></div>
  </div>
  <div class="glass row" style="position: absolute; left: 16px; top: 62px; width: 44px; height: 44px; border-radius: 22px; justify-content: center; color: var(--label);">${ICON.back}</div>
  <div class="glass row" style="position: absolute; right: 16px; top: 62px; width: 44px; height: 44px; border-radius: 22px; justify-content: center; color: var(--label);">${ICON.more}</div>

  <div class="col" style="position: absolute; left: 0; right: 0; top: 340px; gap: 14px;">
    <div class="col" style="padding: 0 16px; gap: 6px;">
      <span class="t1" style="text-wrap: balance;">Sousou no Frieren 2nd Season</span>
      <span class="sub sec">Frieren: Beyond Journey's End Season 2 · 葬送のフリーレン 第2期</span>
      <div class="row" style="gap: 6px; flex-wrap: wrap; margin-top: 4px;">
        <span class="badge" style="background: var(--fill2); color: var(--label);">TV</span>
        <span class="badge" style="background: var(--fill2); color: var(--label);">2026</span>
        <span class="badge" style="background: var(--fill2); color: var(--label);">24 ep</span>
        ${statusBadge("En emisión", "accent")}
        <span class="badge sec" style="background: var(--fill2); gap: 3px;">${scoreLabel("9.12", "c2")}</span>
        <span class="badge sec" style="background: var(--fill2);">#4</span>
      </div>
    </div>

    <!-- Action cluster: the single custom GlassEffectContainer of the app -->
    <div class="col" style="padding: 0 16px; gap: 10px;">
      <div class="row" style="gap: 10px;">
        <div class="glass capsule row" style="flex: 1; height: 44px; padding: 4px; gap: 2px;">
          <div class="row fn sec" style="flex: 1; height: 36px; justify-content: center; border-radius: 18px; font-weight: 600;">Pendiente</div>
          <div class="row fn" style="flex: 1; height: 36px; justify-content: center; border-radius: 18px; font-weight: 700; background: var(--accent); color: #FFFFFF; box-shadow: 0 4px 12px rgba(239,59,71,0.4);">Viendo</div>
          <div class="row fn sec" style="flex: 1; height: 36px; justify-content: center; border-radius: 18px; font-weight: 600;">Visto</div>
        </div>
        <div class="glass row" style="width: 44px; height: 44px; border-radius: 22px; justify-content: center; color: var(--favorite); flex: none;">${ICON.heartFill}</div>
      </div>
      <div class="glass capsule row" style="height: 44px; padding: 0 6px; justify-content: space-between;">
        <span class="row sec" style="width: 36px; height: 36px; justify-content: center;">${ICON.minus}</span>
        <span class="row" style="gap: 6px; align-items: baseline; white-space: nowrap;"><span class="c1 sec" style="font-weight: 600; letter-spacing: 0.3px;">EPISODIO</span><span class="hl mono" style="font-weight: 700;">7</span><span class="sub sec mono" style="font-weight: 500;">/ 24</span></span>
        <span class="row" style="width: 36px; height: 36px; justify-content: center; color: var(--accent);">${ICON.plus}</span>
      </div>
    </div>
    <div class="col" style="padding: 0 16px; gap: 10px;">
      <div class="progress"><div style="width: 29%;"></div></div>
      <div class="row" style="justify-content: space-between;">
        <span class="fn sec" style="white-space: nowrap;">Faltan 17 · próximo vie 9:00</span>
        <span class="fn" style="color: var(--accent); font-weight: 600; white-space: nowrap;">Marcar temporada vista</span>
      </div>
    </div>

    <div class="col" style="gap: 10px;">
      ${sectionHeader("Temporadas", "Ver cadena")}
      <div class="row" style="gap: 12px; padding: 0 16px; align-items: flex-start;">${chain}</div>
    </div>

    <div class="col" style="padding: 0 16px; gap: 6px;">
      <span class="sub clamp3" style="color: var(--label); text-wrap: pretty;">Frieren, Fern and Stark continue north toward Aureole, the resting place of souls, retracing the road the hero's party once travelled. New companions, old regrets and the slow passage of time shape the second half of the journey.</span>
      <span class="sub" style="color: var(--accent); font-weight: 600;">Más</span>
    </div>

    <div style="display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 14px 16px; padding: 4px 16px 0 16px;">
      ${infoCell("Emisión", "16 ene 2026 – en curso")}
      ${infoCell("Horario", "Viernes 23:00 JST · 9:00 aquí")}
      ${infoCell("Estudio", "Madhouse")}
      ${infoCell("Fuente", "Manga")}
    </div>
  </div>
  <div style="position: absolute; left: 0; right: 0; bottom: 0; height: 140px; background: linear-gradient(180deg, rgba(0,0,0,0), var(--bg) 70%); pointer-events: none;"></div>
  ${nowWatchingBar({ inline: true })}
  ${homeIndicator}`;
  return artboard(theme, PHONE, body);
}

// ---------------------------------------------------------------------------
// Watch
// ---------------------------------------------------------------------------
const WATCH_CSS = `
  .watch { border-radius: 96px; background: #000000; color: #FFFFFF; }
  .wrow { display: flex; align-items: center; gap: 12px; padding: 10px 12px; border-radius: 18px; background: #1C1C1E; }
`;

function watchListScreen() {
  const rows = [
    ["frieren2", "Sousou no Frieren 2nd Season", 7, 24, false],
    ["onepiece", "One Piece", 1122, 0, true],
    ["jjk", "Jujutsu Kaisen 3rd Season", 3, 24, false],
    ["kaiju", "Kaijuu 8-gou Season 3", 5, 12, false],
  ].map(([art, title, ep, total, pending]) => `
    <div class="wrow">
      ${poster(art, 40, 60, 8)}
      <div class="col" style="flex: 1; min-width: 0; gap: 6px;">
        <span class="sub clamp2" style="font-weight: 600;">${title}</span>
        <div class="row" style="gap: 8px;">
          <div class="progress" style="flex: 1;"><div style="width: ${total ? Math.round((ep / total) * 100) : 62}%;"></div></div>
          <span class="c1 sec mono">${total ? `${ep}/${total}` : ep}</span>
          ${pending ? `<span class="sec" style="display: inline-flex;">${ICON.clock.replace('class="icon"', 'class="icon" style="width: 14px; height: 14px;"')}</span>` : ""}
        </div>
      </div>
    </div>`).join("");
  const body = `
  <div class="col" style="padding: 44px 14px 0 14px; gap: 10px;">
    <div class="row" style="justify-content: space-between; padding: 0 4px;">
      <span class="t3" style="color: var(--accent);">Viendo</span>
      <span class="c1 sec mono">6</span>
    </div>
    ${rows}
  </div>
  <div style="position: absolute; left: 0; right: 0; bottom: 0; height: 70px; background: linear-gradient(180deg, rgba(0,0,0,0), #000000 80%);"></div>`;
  return artboard("dark watch", WATCH, body, WATCH_CSS);
}

function watchDetailScreen() {
  const r = 58, c = 2 * Math.PI * r, pct = 7 / 24;
  const body = `
  <div class="col" style="padding: 40px 16px 0 16px; gap: 6px; align-items: center;">
    <div class="row" style="width: 100%; justify-content: space-between;">
      <span class="row" style="color: var(--accent);">${ICON.back}</span>
      <span class="sub clamp2" style="font-weight: 600; text-align: right; max-width: 240px;">Frieren 2nd Season</span>
    </div>
    <div style="position: relative; width: 150px; height: 150px; margin-top: 4px;">
      <svg viewBox="0 0 150 150" width="150" height="150">
        <circle cx="75" cy="75" r="${r}" fill="none" stroke="rgba(120,120,128,0.32)" stroke-width="12"></circle>
        <circle cx="75" cy="75" r="${r}" fill="none" stroke="url(#g)" stroke-width="12" stroke-linecap="round" stroke-dasharray="${(c * pct).toFixed(1)} ${(c * (1 - pct)).toFixed(1)}" transform="rotate(-90 75 75)"></circle>
        <defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FF4B58"></stop><stop offset="1" stop-color="#FF8552"></stop></linearGradient></defs>
      </svg>
      <div class="col" style="position: absolute; inset: 0; align-items: center; justify-content: center; gap: 0;">
        <span class="t1 mono" style="font-weight: 700;">7</span>
        <span class="fn sec mono">de 24</span>
      </div>
    </div>
    <div class="col" style="width: 100%; gap: 8px; margin-top: 10px;">
      <div class="glass capsule row" style="height: 50px; justify-content: center; gap: 8px; background: var(--accent); border-color: rgba(255,255,255,0.3); color: #FFFFFF; box-shadow: 0 8px 20px rgba(239,59,71,0.45), inset 0 1px 0 rgba(255,255,255,0.4);">
        ${ICON.plus}<span class="hl">Episodio visto</span>
      </div>
      <div class="glass capsule row" style="height: 44px; justify-content: center; color: var(--label);">
        <span class="sub" style="font-weight: 600;">Deshacer</span>
      </div>
    </div>
  </div>`;
  return artboard("dark watch", WATCH, body, WATCH_CSS);
}

function complicationsBoard() {
  const tile = (label, w, h, inner) => `
    <div class="col" style="gap: 10px; align-items: center;">
      <div class="col" style="width: ${w}px; height: ${h}px; border-radius: ${Math.min(w, h) / 2 > 40 ? 22 : 999}px; background: #0A0A0A; border: 1px solid rgba(255,255,255,0.08); justify-content: center; align-items: center; overflow: hidden;">${inner}</div>
      <span class="c1 sec">${label}</span>
    </div>`;
  const ring = (size, stroke, pct) => {
    const r = (size - stroke) / 2, c = 2 * Math.PI * r;
    return `<svg viewBox="0 0 ${size} ${size}" width="${size}" height="${size}" style="position: absolute; inset: 0;">
      <circle cx="${size / 2}" cy="${size / 2}" r="${r}" fill="none" stroke="rgba(120,120,128,0.32)" stroke-width="${stroke}"></circle>
      <circle cx="${size / 2}" cy="${size / 2}" r="${r}" fill="none" stroke="#FF4B58" stroke-width="${stroke}" stroke-linecap="round" stroke-dasharray="${(c * pct).toFixed(1)} ${(c * (1 - pct)).toFixed(1)}" transform="rotate(-90 ${size / 2} ${size / 2})"></circle></svg>`;
  };
  const body = `
  <div class="row" style="padding: 28px 32px; gap: 40px; align-items: flex-start; justify-content: center;">
    ${tile("Rectangular", 172, 78, `
      <div class="col" style="width: 100%; padding: 8px 12px; gap: 1px;">
        <span class="c2" style="color: var(--accent); font-weight: 700; letter-spacing: 0.4px;">PRÓXIMO EPISODIO</span>
        <span class="sub" style="font-weight: 700; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">Frieren 2nd Season</span>
        <span class="fn sec">Ep 8 · en 2 h 15 min</span>
      </div>`)}
    ${tile("Circular", 78, 78, `
      <div style="position: relative; width: 78px; height: 78px;">${ring(78, 7, 0.29)}
        <div class="col" style="position: absolute; inset: 0; align-items: center; justify-content: center;">
          <span class="hl mono" style="font-weight: 700;">8</span><span class="c2 sec">ep</span>
        </div></div>`)}
    ${tile("Inline", 260, 34, `<span class="fn" style="font-weight: 600;">Frieren · ep 8 · vie 9:00</span>`)}
    ${tile("Esquina", 78, 78, `
      <div class="col" style="align-items: center; gap: 0;">
        <span class="hl mono" style="font-weight: 700;">Ep 8</span>
        <span class="c2 sec">en 2 h</span>
      </div>`)}
  </div>
  <div class="col" style="padding: 0 32px 24px 32px; gap: 4px;">
    <span class="fn sec" style="text-wrap: pretty;">Complicación "Próximo episodio" en las cuatro familias accessory de WidgetKit. Solo visual: tocar abre la ficha en el Watch; los tiempos son relativos (<code>Text(date, style: .relative)</code>).</span>
  </div>`;
  return artboard("dark", { w: 720, h: 240 }, body, ".root code { font-family: ui-monospace, Menlo, monospace; font-size: 12px; }");
}

// ---------------------------------------------------------------------------
// Write files + canvas.json
// ---------------------------------------------------------------------------
const files = {
  "Login.dc.html": loginScreen("dark"),
  "Main.dc.html": seasonScreen("dark"),
  "Top.dc.html": topScreen("dark"),
  "Recomendados.dc.html": recommendationsScreen("dark"),
  "MiLista.dc.html": libraryScreen("dark"),
  "Detalle.dc.html": detailScreen("dark"),
  "TemporadaClaro.dc.html": seasonScreen("light"),
  "DetalleClaro.dc.html": detailScreen("light"),
  "WatchViendo.dc.html": watchListScreen(),
  "WatchDetalle.dc.html": watchDetailScreen(),
  "Complicaciones.dc.html": complicationsBoard(),
};
for (const [name, html] of Object.entries(files)) writeFileSync(join(OUT, name), html);

const GAP = 90, ROW2 = PHONE.h + 150;
const row1 = ["Login.dc.html", "Main.dc.html", "Top.dc.html", "Recomendados.dc.html", "MiLista.dc.html", "Detalle.dc.html"];
const artboards = row1.map((file, i) => ({ file, x: i * (PHONE.w + GAP), y: 0, w: PHONE.w, h: PHONE.h,
  title: { "Login.dc.html": "Login", "Main.dc.html": "Temporada", "Top.dc.html": "Top", "Recomendados.dc.html": "Recomendados", "MiLista.dc.html": "Mi lista", "Detalle.dc.html": "Detalle" }[file] }));
artboards.push({ file: "TemporadaClaro.dc.html", x: 0, y: ROW2, w: PHONE.w, h: PHONE.h, title: "Temporada · claro" });
artboards.push({ file: "DetalleClaro.dc.html", x: PHONE.w + GAP, y: ROW2, w: PHONE.w, h: PHONE.h, title: "Detalle · claro" });
const wx = 2 * (PHONE.w + GAP) + 40;
artboards.push({ file: "WatchViendo.dc.html", x: wx, y: ROW2, w: WATCH.w, h: WATCH.h, title: "Watch · Viendo" });
artboards.push({ file: "WatchDetalle.dc.html", x: wx + WATCH.w + GAP, y: ROW2, w: WATCH.w, h: WATCH.h, title: "Watch · Detalle" });
artboards.push({ file: "Complicaciones.dc.html", x: wx, y: ROW2 + WATCH.h + 130, w: 720, h: 240, title: "Complicaciones" });

const canvas = {
  artboards,
  annotations: [
    { id: "paleta", x: -360, y: 0, w: 300, text: "Paleta RecAnime (un solo acento)\n\nAcento rojo: #EF3B47 (claro) · #FF4B58 (oscuro)\nAcento profundo: #B9202C · #C92935\nPendiente: #B08A8E · #BD9A9E\nViendo: = acento\nVisto (coral): #F2703C · #FF8552\nFavorito (rosa): #F0468C · #FF63A3\nFondos y texto: colores semánticos del sistema (systemBackground, label, secondaryLabel).\nPuntuaciones en gris secundario: nunca amarillo." },
    { id: "glass", x: -360, y: 330, w: 300, text: "Liquid Glass — dónde sí y dónde no\n\nSÍ (lo pone el sistema): tab bar flotante, pestaña Buscar separada, accesorio inferior \"Viendo ahora\" (como el mini reproductor), toolbars, sheets, botones .glass/.glassProminent.\n\nSÍ (a mano, pocos sitios): clúster de acciones del Detalle (GlassEffectContainer), chips de filtro en Top, control segmentado de Mi lista y el toast de error (no aparece en estos mockups).\n\nNO: filas, tarjetas, posters, badges, cabeceras, barras de progreso." },
    { id: "notas", x: -360, y: 620, w: 300, text: "Notas\n\n· Mockups estáticos (no prototipo clicable).\n· Sin barra de estado, indicador de inicio ni teclado dibujados: en el dispositivo los pone iOS.\n· Los posters son marcadores de posición (en la app son las imágenes de MAL).\n· En Detalle la tab bar aparece minimizada (tabBarMinimizeBehavior .onScrollDown) con el accesorio en línea.\n· Sinopsis y textos de recomendaciones llegan en inglés desde MAL; la interfaz va en español." },
  ],
  launch: { view: "canvas" },
};
writeFileSync(join(OUT, "canvas.json"), JSON.stringify(canvas, null, 2) + "\n");
console.log(`wrote ${Object.keys(files).length} artboards + canvas.json to ${OUT}`);
