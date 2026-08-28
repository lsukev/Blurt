// Generates the six onboarding artboards.
//
// Every value below is lifted verbatim from Sources/MurmurYouTube/UI/DesignSystem.swift
// and Equipment.swift — this file exists so the shared chassis, rail and lamp states stay
// identical across all six pages instead of drifting through copy-paste.
//
//   node design/_build.mjs
//
import { writeFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const OUT = dirname(fileURLToPath(import.meta.url));

// ── DS tokens ────────────────────────────────────────────────────────────────
const C = {
  chassis: "#2A2825", panel: "#B8B4AD", panelHighlight: "#C9C5BE", panelShade: "#9E9A93",
  well: "#6E6A64", deck: "#38352F", cap: "#E8E3D8", seam: "#6B6862",
  ink: "#1C1A17", inkSecondary: "#514D47", silkscreen: "#3A3630", inkOnDeck: "#D8D2C4",
  record: "#C8342A", selection: "#CDC8C0", selectionEdge: "#8A857D",
  meterFace: "#D8CFB4", meterLamp: "#E8B860", meterRed: "#C0392B",
};
const MONO = "ui-monospace, 'SF Mono', Menlo, monospace";

// ── primitives ───────────────────────────────────────────────────────────────
const silk = (t, color = C.silkscreen, size = 9) =>
  `<span style="font-size: ${size}px; font-weight: 500; letter-spacing: 1.1px; text-transform: uppercase; color: ${color};">${t}</span>`;

// Lamp: lit lamps get a specular dot, never a bloom (DS.Material.lampSpecular).
const lamp = (state = "unlit", size = 7) => {
  const fill = state === "lit" ? C.cap : state === "rec" ? C.record : "rgba(232,227,216,0.22)";
  const spec = state === "unlit" ? "" :
    `<span style="position: absolute; left: ${size * 0.2}px; top: ${size * 0.18}px; width: ${size * 0.3}px; height: ${size * 0.3}px; border-radius: 50%; background: rgba(255,255,255,0.45);"></span>`;
  return `<span style="display: block; position: relative; flex: none; width: ${size}px; height: ${size}px; border-radius: 50%; box-sizing: border-box; background: ${fill}; border: 1px solid rgba(107,104,98,0.7);">${spec}</span>`;
};

// TransportKey: cap, top bevel catches the light, short hard raised shadow.
const key = (label, { dim = false, selected = false, pad = 16, font = 9 } = {}) => {
  const bg = selected ? C.selection : C.cap;
  const ring = selected ? C.selectionEdge : "rgba(107,104,98,0.5)";
  return `<div style="display: inline-flex; align-items: center; justify-content: center; min-width: 52px; height: 34px; padding: 0 ${pad}px; box-sizing: border-box; border-radius: 3px; background: ${bg}; border: 1px solid ${ring}; box-shadow: inset 0 1px 0 ${C.panelHighlight}, 0 1px 3px rgba(0,0,0,0.35); font-size: ${font}px; font-weight: 500; letter-spacing: 1.1px; text-transform: uppercase; color: ${C.ink};${dim ? " opacity: 0.4;" : ""}">${label}</div>`;
};

const screw = () =>
  `<span style="display: block; position: relative; width: 9px; height: 9px; border-radius: 50%; box-sizing: border-box; background: ${C.panelShade}; border: 1px solid rgba(107,104,98,0.6);"><span style="position: absolute; left: 1px; right: 1px; top: 3px; height: 1px; background: rgba(107,104,98,0.7); transform: rotate(28deg);"></span></span>`;

const vents = (n = 6) =>
  `<div style="display: flex; gap: 4px;">${Array.from({ length: n }, () =>
    `<span style="width: 3px; height: 22px; border-radius: 1.5px; background: ${C.seam}; opacity: 0.5;"></span>`).join("")}</div>`;

const well = (inner, pad = "14px 16px") =>
  `<div style="background: ${C.well}; border-radius: 5px; border: 1px solid rgba(107,104,98,0.55); box-shadow: inset 0 1px 2px rgba(0,0,0,0.45), inset 0 -1px 0 rgba(201,197,190,0.35); padding: ${pad};">${inner}</div>`;

const deck = (inner, pad = "14px 16px") =>
  `<div style="background: ${C.deck}; border-radius: 5px; border: 1px solid ${C.seam}; color: ${C.inkOnDeck}; padding: ${pad};">${inner}</div>`;

const title = (t) =>
  `<h1 style="margin: 0; font-size: 17px; font-weight: 600; letter-spacing: -0.1px; color: ${C.ink};">${t}</h1>`;

const body = (t, color = C.ink, max = "48ch") =>
  `<p style="margin: 0; max-width: ${max}; font-size: 13px; line-height: 1.5; color: ${color}; text-wrap: pretty;">${t}</p>`;

// A monospaced self-test log on the dark readout — how equipment reports its own state.
const logLine = (label, value, value_color = C.inkOnDeck) =>
  `<div style="display: flex; align-items: baseline; gap: 12px; font-family: ${MONO}; font-size: 13px; line-height: 1.7;"><span style="flex-grow: 1; color: rgba(216,210,196,0.65);">${label}</span><span style="color: ${value_color};">${value}</span></div>`;

// ── chassis + rail ───────────────────────────────────────────────────────────
const STEPS = ["Welcome", "Accessibility", "Microphone", "Key", "Try it", "Done"];

const rail = (current) => {
  const rows = STEPS.map((name, i) => {
    const done = i < current;
    const active = i === current;
    const style = active
      ? `padding: 7px 8px; border-radius: 2px; background: ${C.selection}; box-shadow: inset 0 0 0 1px ${C.selectionEdge};`
      : `padding: 7px 8px; border-radius: 2px;`;
    return `<div style="display: flex; align-items: center; gap: 10px; ${style}">${lamp(done ? "lit" : "unlit")}${silk(name, active ? C.ink : C.silkscreen)}</div>`;
  }).join("");

  return `<div style="position: relative; z-index: 1; width: 208px; box-sizing: border-box; padding: 20px 16px; border-right: 1px solid ${C.seam}; display: flex; flex-direction: column; gap: 20px;">
      <div style="display: flex; flex-direction: column; gap: 3px;">${silk("Blurt", C.silkscreen, 11)}${silk("Push-to-talk dictation", C.inkSecondary)}</div>
      <div style="height: 1px; background: ${C.seam}; opacity: 0.5;"></div>
      <div style="display: flex; flex-direction: column; gap: 2px;">
        <div style="padding: 0 8px 6px;">${silk("Setup", C.inkSecondary)}</div>
        ${rows}
      </div>
      <div style="flex-grow: 1;"></div>
      <div style="display: flex; align-items: flex-end; justify-content: space-between;">${screw()}${vents()}</div>
    </div>`;
};

const page = (current, stage) => `<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
  <style>
    body { margin: 0; font-family: "Helvetica Neue", Helvetica, Arial, sans-serif; }
    /* Neutral family, never the record red: AGENTS.md reserves red for recording alone. */
    a { color: #514D47; text-decoration-color: rgba(107,104,98,0.6); } a:hover { color: #1C1A17; }
  </style>
</helmet>
<div style="width: 860px; height: 620px; box-sizing: border-box; padding: 14px; background: ${C.chassis};">
  <div style="position: relative; width: 832px; height: 592px; box-sizing: border-box; overflow: hidden; border-radius: 5px; background: ${C.panel}; box-shadow: inset 0 1px 0 rgba(201,197,190,0.5), 0 2px 10px rgba(0,0,0,0.25); display: flex;">
    <div style="position: absolute; inset: 0; pointer-events: none; background: repeating-linear-gradient(180deg, rgba(255,255,255,0.055) 0px, rgba(255,255,255,0.055) 1px, rgba(0,0,0,0.07) 1px, rgba(0,0,0,0.07) 2px);"></div>
    ${rail(current)}
    <div style="position: relative; z-index: 1; flex-grow: 1; box-sizing: border-box; padding: 28px 32px; display: flex; flex-direction: column; gap: 18px;">
      <div style="display: flex; align-items: baseline; justify-content: space-between;">${silk(`Step ${current + 1} of 6`, C.inkSecondary)}${screw()}</div>
      ${stage}
    </div>
  </div>
</div>
</x-dc>
</body>
</html>
`;

const spacer = `<div style="flex-grow: 1;"></div>`;
const actions = (inner) =>
  `<div style="display: flex; align-items: center; justify-content: flex-end; gap: 10px;">${inner}</div>`;

// ── 1 · Welcome ──────────────────────────────────────────────────────────────
const beat = (art, label) =>
  `<div style="background: ${C.panel}; padding: 18px 16px; display: flex; flex-direction: column; align-items: center; gap: 12px;">${art}${silk(label)}</div>`;

const welcome = `
      <div style="display: flex; flex-direction: column; gap: 10px;">
        ${title("Hold a key. Talk. Let go.")}
        ${body("Blurt types what you said into whatever you were already working in. Everything runs on this Mac — nothing you say leaves it.", C.ink, "46ch")}
      </div>
      <div style="display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 1px; background: ${C.seam}; border: 1px solid ${C.seam}; border-radius: 5px; overflow: hidden;">
        ${beat(`<div style="display: inline-flex; align-items: center; justify-content: center; min-width: 52px; height: 34px; padding: 0 12px; box-sizing: border-box; border-radius: 3px; background: ${C.cap}; border: 1px solid rgba(107,104,98,0.5); box-shadow: inset 0 1px 0 ${C.panelHighlight}, 0 1px 3px rgba(0,0,0,0.35); font-size: 15px; color: ${C.ink};">⌥</div>`, "Hold")}
        ${beat(`<svg width="56" height="34" viewBox="0 0 56 34" fill="none" aria-hidden="true">
            <line x1="2" y1="14" x2="2" y2="20" stroke="${C.silkscreen}" stroke-width="2" stroke-linecap="round"/>
            <line x1="9" y1="10" x2="9" y2="24" stroke="${C.silkscreen}" stroke-width="2" stroke-linecap="round"/>
            <line x1="16" y1="6" x2="16" y2="28" stroke="${C.silkscreen}" stroke-width="2" stroke-linecap="round"/>
            <line x1="23" y1="12" x2="23" y2="22" stroke="${C.silkscreen}" stroke-width="2" stroke-linecap="round"/>
            <line x1="30" y1="4" x2="30" y2="30" stroke="${C.silkscreen}" stroke-width="2" stroke-linecap="round"/>
            <line x1="37" y1="11" x2="37" y2="23" stroke="${C.silkscreen}" stroke-width="2" stroke-linecap="round"/>
            <line x1="44" y1="8" x2="44" y2="26" stroke="${C.silkscreen}" stroke-width="2" stroke-linecap="round"/>
            <line x1="51" y1="14" x2="51" y2="20" stroke="${C.silkscreen}" stroke-width="2" stroke-linecap="round"/>
          </svg>`, "Talk")}
        ${beat(`<svg width="56" height="34" viewBox="0 0 56 34" fill="none" aria-hidden="true">
            <rect x="4" y="8" width="40" height="2" rx="1" fill="${C.silkscreen}"/>
            <rect x="4" y="16" width="48" height="2" rx="1" fill="${C.silkscreen}"/>
            <rect x="4" y="24" width="22" height="2" rx="1" fill="${C.silkscreen}"/>
            <rect x="28" y="21" width="1.5" height="9" fill="${C.ink}"/>
          </svg>`, "It's typed")}
      </div>
      ${well(`<div style="display: flex; flex-direction: column; gap: 7px;">${silk("Before you start", C.inkOnDeck)}${body("Blurt needs two permissions from macOS. It can ask for the microphone itself. Accessibility you have to switch on by hand — that's the one that takes a minute.", C.inkOnDeck, "52ch")}</div>`)}
      ${spacer}
      ${actions(key("Begin"))}`;

// ── 2 · Accessibility ────────────────────────────────────────────────────────
const accessibility = `
      <div style="display: flex; flex-direction: column; gap: 10px;">
        ${title("Switch on Accessibility")}
        ${body("Blurt watches for one key, and types text for you. macOS files both of those under Accessibility. It's the permission the system won't grant on an app's say-so — the switch has to be yours.", C.ink, "50ch")}
      </div>
      ${deck(`<div style="display: flex; flex-direction: column; gap: 10px;">
        <div style="display: flex; align-items: center; gap: 10px;">${lamp("unlit")}${silk("Waiting for the switch", "rgba(216,210,196,0.75)")}</div>
        <div style="height: 1px; background: rgba(107,104,98,0.6);"></div>
        <div>
          ${logLine("added to accessibility list", "yes")}
          ${logLine("event tap", "not permitted", "rgba(216,210,196,0.5)")}
          ${logLine("microphone", "not asked yet", "rgba(216,210,196,0.5)")}
        </div>
      </div>`, "14px 16px")}
      ${well(`<div style="display: flex; align-items: center; gap: 14px;">
        <div style="flex-grow: 1; display: flex; flex-direction: column; gap: 4px;">
          ${silk("Switched it on and nothing happened?", C.inkOnDeck)}
          ${body("macOS can keep showing the switch as on while still refusing the app. It's a known state, and it takes one click to clear.", "rgba(216,210,196,0.8)", "44ch")}
        </div>
        ${key("Fix it", { pad: 14 })}
      </div>`)}
      ${spacer}
      ${actions(`${key("Skip", { dim: true })}${key("Open System Settings")}`)}`;

// ── 3 · Microphone ───────────────────────────────────────────────────────────
const microphone = `
      <div style="display: flex; flex-direction: column; gap: 10px;">
        ${title("Allow the microphone")}
        ${body("This one macOS asks for directly — no trip to System Settings. Blurt listens only while you're holding the key, and stops the moment you let go.", C.ink, "50ch")}
      </div>
      ${well(`<div style="display: flex; align-items: center; gap: 18px;">
        <div style="position: relative; width: 208px; height: 58px; flex: none; border-radius: 2px; background: ${C.well}; border: 1px solid ${C.seam}; box-sizing: border-box; overflow: hidden; opacity: 0.75;">
          <svg width="206" height="56" viewBox="0 0 208 58" fill="none" aria-hidden="true">
            <line x1="104" y1="60.9" x2="73.07" y2="17.4" stroke="rgba(28,26,23,0.35)" stroke-width="1.5" stroke-linecap="round"/>
          </svg>
        </div>
        <div style="display: flex; flex-direction: column; gap: 5px;">
          ${silk("No signal", C.inkOnDeck)}
          ${body("The meter wakes up once macOS lets Blurt hear you.", "rgba(216,210,196,0.8)", "30ch")}
        </div>
      </div>`)}
      ${well(`<div style="display: flex; align-items: center; gap: 14px;">
        <div style="flex-grow: 1; display: flex; flex-direction: column; gap: 4px;">
          ${silk("Turned it down before?", C.inkOnDeck)}
          ${body("macOS only ever asks once. If you said no to Blurt previously, the button above does nothing and you'll need to switch it on by hand.", "rgba(216,210,196,0.8)", "46ch")}
        </div>
        ${key("Settings", { pad: 14 })}
      </div>`)}
      ${spacer}
      ${actions(`${key("Skip", { dim: true })}${key("Allow microphone")}`)}`;

// ── 4 · Key ──────────────────────────────────────────────────────────────────
const keyOption = (glyph, name, selected) => `
        <div style="display: flex; flex-direction: column; align-items: center; gap: 10px;">
          ${lamp(selected ? "lit" : "unlit")}
          <div style="display: inline-flex; align-items: center; justify-content: center; width: 118px; height: 56px; box-sizing: border-box; border-radius: 3px; background: ${selected ? C.selection : C.cap}; border: 1px solid ${selected ? C.selectionEdge : "rgba(107,104,98,0.5)"}; box-shadow: inset 0 1px 0 ${C.panelHighlight}, 0 1px 3px rgba(0,0,0,0.35); font-size: 17px; color: ${C.ink};">${glyph}</div>
          ${silk(name)}
        </div>`;

const keyStep = `
      <div style="display: flex; flex-direction: column; gap: 10px;">
        ${title("Choose your key")}
        ${body("Hold it to dictate, let go to stop. Pick one nothing else on your Mac already wants.", C.ink, "50ch")}
      </div>
      <div style="display: flex; gap: 16px; justify-content: flex-start;">
        ${keyOption("⌥", "Right option", true)}
        ${keyOption("fn", "Fn", false)}
        ${keyOption("⌘", "Right command", false)}
      </div>
      ${deck(`<div style="display: flex; align-items: center; gap: 14px;">
        ${lamp("lit", 11)}
        <div style="flex-grow: 1; display: flex; flex-direction: column; gap: 3px;">
          ${silk("Holding — Blurt sees it", "rgba(216,210,196,0.75)")}
          <span style="font-family: ${MONO}; font-size: 13px; color: ${C.inkOnDeck};">right option · held 0.42s</span>
        </div>
      </div>`)}
      ${well(`<div style="display: flex; flex-direction: column; gap: 4px;">
        ${silk("Already run another dictation app?", C.inkOnDeck)}
        ${body("Hold the key now. If that app's window appears too, both are listening and they'll fight over the text — come back here and pick a different one.", "rgba(216,210,196,0.8)", "58ch")}
      </div>`)}
      ${spacer}
      ${actions(`${key("Skip", { dim: true })}${key("Continue")}`)}`;

// ── 5 · Try it ───────────────────────────────────────────────────────────────
// Meter geometry reproduced from VUMeter.draw(): pivot (104, 60.9), radius 53.36,
// 96° sweep, red zone from 0.72, needle at 0.62.
const meterTicks = [
  ["73.07", "33.05", "64.35", "25.2", C.ink], ["75.5", "24.94", "70.86", "19.08", C.ink],
  ["83.95", "24.43", "78.29", "14.14", C.ink], ["88.91", "17.56", "86.45", "10.51", C.ink],
  ["97.06", "19.86", "95.1", "8.29", C.ink], ["104", "15.01", "104", "7.54", C.ink],
  ["110.94", "19.86", "112.9", "8.29", C.ink], ["119.09", "17.56", "121.55", "10.51", C.ink],
  ["124.05", "24.43", "129.71", "14.14", C.meterRed], ["132.5", "24.94", "137.14", "19.08", C.meterRed],
  ["134.93", "33.05", "143.65", "25.2", C.meterRed],
].map(([x1, y1, x2, y2, s]) => `<line x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}" stroke="${s}" stroke-width="1"/>`).join("");

const tryIt = `
      <div style="display: flex; flex-direction: column; gap: 10px;">
        ${title("Say something.")}
        ${body("Hold your key and talk. This runs the real thing — the same path Blurt uses in every other app.", C.ink, "50ch")}
      </div>
      <div style="display: flex; gap: 14px; align-items: stretch;">
        <div style="position: relative; width: 208px; height: 58px; flex: none; border-radius: 2px; background: ${C.meterFace}; border: 1px solid ${C.seam}; box-sizing: border-box; overflow: hidden;">
          <div style="position: absolute; inset: 0; background: ${C.meterLamp}; opacity: 0.14;"></div>
          <svg style="position: relative;" width="206" height="56" viewBox="0 0 208 58" fill="none" aria-hidden="true">
            ${meterTicks}
            <line x1="104" y1="60.9" x2="114.44" y2="9.66" stroke="${C.ink}" stroke-width="1.5" stroke-linecap="round"/>
          </svg>
        </div>
        ${well(`<div style="height: 100%; box-sizing: border-box; display: flex; align-items: center; gap: 14px;">
          ${lamp("rec", 11)}
          <div style="display: flex; flex-direction: column; gap: 2px;">
            ${silk("Recording", C.inkOnDeck)}
            <span style="font-family: ${MONO}; font-size: 13px; color: ${C.inkOnDeck};">0:04</span>
          </div>
        </div>`, "0 18px")}
      </div>
      ${deck(`<div style="display: flex; flex-direction: column; gap: 9px;">
        ${silk("Blurt types here", "rgba(216,210,196,0.6)")}
        <div style="font-size: 13px; line-height: 1.55; color: ${C.inkOnDeck};">Testing the microphone — this is what Blurt heard, cleaned up and typed.<span style="display: inline-block; width: 1.5px; height: 14px; margin-left: 2px; background: ${C.inkOnDeck}; vertical-align: text-bottom;"></span></div>
      </div>`, "16px 18px")}
      ${spacer}
      ${actions(`${key("Skip", { dim: true })}${key("That worked")}`)}`;

// ── 6 · Done ─────────────────────────────────────────────────────────────────
const done = `
      <div style="display: flex; flex-direction: column; gap: 10px;">
        ${title("You're set.")}
        ${body("Hold Right ⌥ anywhere on your Mac and talk. Blurt types into whatever has focus — a search field, a chat box, a code editor.", C.ink, "50ch")}
      </div>
      ${deck(`<div style="display: flex; align-items: center; gap: 16px;">
        <div style="display: inline-flex; align-items: center; justify-content: center; width: 96px; height: 48px; flex: none; box-sizing: border-box; border-radius: 3px; background: ${C.cap}; border: 1px solid rgba(107,104,98,0.5); box-shadow: inset 0 1px 0 ${C.panelHighlight}, 0 1px 3px rgba(0,0,0,0.35); font-size: 17px; color: ${C.ink};">⌥</div>
        <div style="display: flex; flex-direction: column; gap: 3px;">
          ${silk("Your key", "rgba(216,210,196,0.6)")}
          <span style="font-size: 13px; color: ${C.inkOnDeck};">Right option — hold to dictate</span>
        </div>
      </div>`, "18px 20px")}
      ${well(`<div style="display: flex; flex-direction: column; gap: 9px;">
        ${silk("Two things worth knowing", C.inkOnDeck)}
        <div style="display: flex; flex-direction: column; gap: 6px;">
          ${body("The menu bar icon holds your settings, your word list, and everything you've dictated.", "rgba(216,210,196,0.85)", "56ch")}
          ${body("Nothing you say leaves this Mac. Transcription and cleanup both run on-device.", "rgba(216,210,196,0.85)", "56ch")}
        </div>
      </div>`)}
      ${spacer}
      ${actions(key("Start using Blurt"))}`;

// ── emit ─────────────────────────────────────────────────────────────────────
const files = {
  "Main.dc.html": page(0, welcome),
  "Accessibility.dc.html": page(1, accessibility),
  "Microphone.dc.html": page(2, microphone),
  "Key.dc.html": page(3, keyStep),
  "TryIt.dc.html": page(4, tryIt),
  "Done.dc.html": page(5, done),
};

for (const [name, html] of Object.entries(files)) {
  writeFileSync(join(OUT, name), html, "utf8");
  console.log(`wrote ${name}  ${html.length} bytes`);
}

// Canvas layout: two rows of three, 80px between columns, 120px between rows.
const canvas = {
  artboards: [
    { file: "Main.dc.html", title: "1 · Welcome", x: 0, y: 0, w: 860, h: 620 },
    { file: "Accessibility.dc.html", title: "2 · Accessibility", x: 940, y: 0, w: 860, h: 620 },
    { file: "Microphone.dc.html", title: "3 · Microphone", x: 1880, y: 0, w: 860, h: 620 },
    { file: "Key.dc.html", title: "4 · Key", x: 0, y: 740, w: 860, h: 620 },
    { file: "TryIt.dc.html", title: "5 · Try it", x: 940, y: 740, w: 860, h: 620 },
    { file: "Done.dc.html", title: "6 · Done", x: 1880, y: 740, w: 860, h: 620 },
  ],
  annotations: [
    {
      id: "rail-note", x: 0, y: -150, w: 420,
      text: "The rail is the wizard's only navigation — a lamp per step, lit as you clear it.\nNo Next/Back chrome: granting a permission advances the page on its own.",
    },
    {
      id: "lamp-note", x: 1880, y: -150, w: 400,
      text: "Lit lamps are cream, not green.\nAGENTS.md reserves red for recording and amber/green for level instrumentation, so \"granted\" can't use the obvious colour.",
    },
    {
      id: "hard-note", x: 940, y: 1400, w: 420,
      text: "Steps 2 and 5 carry the real weight — 2 is where people get stuck (the wedged-TCC recovery lives there), and 5 exercises the one path CI can never reach.",
    },
  ],
  launch: { view: "canvas" },
};
writeFileSync(join(OUT, "canvas.json"), JSON.stringify(canvas, null, 2), "utf8");
console.log("wrote canvas.json");
