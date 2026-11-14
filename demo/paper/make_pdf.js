// Writes demo/paper/learning-rate-note.pdf: a two-page paper-style handout for the study-mode demo.
// Pure Node, no packages, no network:   node demo/paper/make_pdf.js
// The text and the numbers are made up for the demo; this is not a published paper.
const fs = require("fs");
const path = require("path");

// Times-Roman character widths (per 1000 units), enough for line breaking.
const W = { " ": 250, ".": 250, ",": 250, ":": 278, ";": 278, "-": 333, "(": 333, ")": 333, "'": 333, "/": 278,
  "%": 833, "=": 564, "+": 564, "!": 333, "?": 444, '"': 408,
  a: 444, b: 500, c: 444, d: 500, e: 444, f: 333, g: 500, h: 500, i: 278, j: 278, k: 500, l: 278, m: 778,
  n: 500, o: 500, p: 500, q: 500, r: 333, s: 389, t: 278, u: 500, v: 500, w: 722, x: 500, y: 500, z: 444,
  A: 722, B: 667, C: 667, D: 722, E: 611, F: 556, G: 722, H: 722, I: 333, J: 389, K: 722, L: 611, M: 889,
  N: 722, O: 722, P: 556, Q: 722, R: 667, S: 556, T: 611, U: 722, V: 722, W: 944, X: 722, Y: 722, Z: 611 };
const FONTS = { R: "F1", B: "F2", I: "F3" };            // roman, bold, italic
const widthOf = (s, size, font) => {
  let w = 0;
  for (const ch of s) w += W[ch] || 500;                 // digits and anything else: 500
  return w * size / 1000 * (font === "B" ? 1.07 : 1);
};
const esc = (s) => s.replace(/\\/g, "\\\\").replace(/\(/g, "\\(").replace(/\)/g, "\\)");

const PAGE_W = 612, PAGE_H = 792, LEFT = 82, RIGHT = 530, TOP = 720, BOTTOM = 80;
const pages = [[]];
let y = TOP;
const out = (s) => pages[pages.length - 1].push(s);
const need = (h) => { if (y - h < BOTTOM) { pages.push([]); y = TOP; } };
const textAt = (s, x, yy, size, font = "R") => out(`BT /${FONTS[font]} ${size} Tf ${x.toFixed(1)} ${yy.toFixed(1)} Td (${esc(s)}) Tj ET`);

function wrap(s, size, font, maxW) {
  const lines = []; let line = "";
  for (const word of s.split(/\s+/)) {
    const t = line ? line + " " + word : word;
    if (widthOf(t, size, font) > maxW && line) { lines.push(line); line = word; } else line = t;
  }
  if (line) lines.push(line);
  return lines;
}
function para(s, { size = 11, font = "R", lead = 1.36, indent = 0, after = 8, center = false } = {}) {
  for (const line of wrap(s, size, font, RIGHT - LEFT - indent)) {
    need(size * lead);
    y -= size * lead;
    const x = center ? (PAGE_W - widthOf(line, size, font)) / 2 : LEFT + indent;
    textAt(line, x, y, size, font);
  }
  y -= after;
}
const heading = (s) => { need(40); y -= 6; para(s, { size: 13, font: "B", after: 4 }); };

// ---- content ----
para("Choosing a Learning Rate: A Short Practical Note", { size: 19, font: "B", center: true, after: 6 });
para("ML 201 course handout, Lecture 7", { size: 11.5, font: "I", center: true, after: 2 });
para("Demo material for Clueless. The experiment and its numbers are illustrative, not published results.",
  { size: 9.5, font: "I", center: true, after: 16 });

para("Abstract", { size: 11, font: "B", center: true, after: 2 });
para("The learning rate is the setting that most often decides whether gradient descent works at all. We train the " +
  "same small classifier with five learning rates and report the final validation loss and the number of epochs " +
  "needed to converge. A rate of 0.01 reaches the lowest loss, 0.27, in 14 epochs. A rate of 0.001 reaches a " +
  "similar loss but needs 96 epochs, and a rate of 1.0 diverges within 3 epochs. We end with three rules that " +
  "are easy to apply in practice.", { size: 10.5, indent: 28, after: 14 });

heading("1. Introduction");
para("Gradient descent updates the weights by moving against the gradient of the loss. The size of that move is " +
  "the learning rate, written eta. If eta is too small, training is correct but slow. If it is too large, each " +
  "step overshoots the minimum and the loss grows instead of shrinking. Between the two there is usually a wide " +
  "range that works, and finding it takes only a few short runs.");

heading("2. Setup");
para("We train a two-layer network with 128 hidden units on 50,000 training examples, and keep 10,000 examples " +
  "for validation. We use mini-batch stochastic gradient descent with a batch size of 64, which gives 782 steps " +
  "per epoch. Each run lasts at most 100 epochs. A run counts as converged when the validation loss changes by " +
  "less than 0.001 for five epochs in a row. Every setting is run with three random seeds and we report the mean.");

heading("3. Results");
para("Table 1 shows the outcome for each learning rate. Figure 1 shows the validation loss during the first " +
  "epochs of three of the runs.");

// Table 1
need(150);
y -= 6;
const cols = [LEFT + 30, LEFT + 150, LEFT + 290];
const rows = [
  ["Learning rate", "Final validation loss", "Epochs to converge"],
  ["0.0001", "0.61", "did not converge in 100"],
  ["0.001", "0.29", "96"],
  ["0.01", "0.27", "14"],
  ["0.1", "0.34", "9"],
  ["1.0", "diverged", "stopped after 3"],
];
const tableTop = y;
out(`0.6 w ${LEFT + 20} ${tableTop} m ${RIGHT - 20} ${tableTop} l S`);
rows.forEach((r, k) => {
  y -= 16;
  r.forEach((cell, c) => textAt(cell, cols[c], y, 10.5, k === 0 || r[0] === "0.01" ? "B" : "R"));
  if (k === 0) out(`0.6 w ${LEFT + 20} ${y - 5} m ${RIGHT - 20} ${y - 5} l S`);
});
y -= 6;
out(`0.6 w ${LEFT + 20} ${y} m ${RIGHT - 20} ${y} l S`);
y -= 4;
para("Table 1. Final validation loss and epochs to converge for five learning rates. Best result in bold.",
  { size: 9.5, font: "I", center: true, after: 12 });

para("The best rate, 0.01, is ten times larger than the slowest rate that still converges, and it reaches a " +
  "slightly lower loss in about one seventh of the time. A rate of 0.1 converges even faster, in 9 epochs, but " +
  "it settles at a higher loss of 0.34 because the steps are too large to reach the bottom of the valley.");

// Figure 1: a small line chart drawn with PDF path operators.
need(215);
y -= 10;
const fx = LEFT + 70, fy = y - 160, fw = 300, fh = 150;
out(`0 0 0 RG 0.8 w ${fx} ${fy} m ${fx + fw} ${fy} l S ${fx} ${fy} m ${fx} ${fy + fh} l S`);
const curve = (pts, rgb, widthPt = 1.8) =>
  out(`${rgb} RG ${widthPt} w ` + pts.map((p, k) => `${(fx + p[0] * fw).toFixed(1)} ${(fy + p[1] * fh).toFixed(1)} ${k ? "l" : "m"}`).join(" ") + " S");
const decay = (rate, floor) => Array.from({ length: 31 }, (_, k) => [k / 30, floor + (0.62 - floor) * Math.exp(-rate * k / 30)]);
curve(decay(0.45, 0.25), "0.15 0.39 0.66");                       // 0.001: slow
curve(decay(9, 0.2), "0.18 0.49 0.31");                           // 0.01: converges
curve([[0, 0.62], [0.05, 0.5], [0.1, 0.74], [0.15, 0.42], [0.2, 0.9], [0.25, 0.3], [0.3, 1.0]], "0.75 0.22 0.17"); // 1.0: diverges
out("0 0 0 RG");
textAt("validation loss", fx - 62, fy + fh - 8, 9, "I");
textAt("epoch", fx + fw / 2 - 12, fy - 14, 9, "I");
out("0.75 0.22 0.17 rg"); textAt("1.0 (diverges)", fx + fw * 0.33, fy + fh - 6, 9.5, "B");
out("0.15 0.39 0.66 rg"); textAt("0.001 (slow)", fx + fw + 6, fy + fh * 0.44, 9.5, "B");
out("0.18 0.49 0.31 rg"); textAt("0.01 (converges)", fx + fw + 6, fy + fh * 0.19, 9.5, "B");
out("0 0 0 rg");
y = fy - 22;
para("Figure 1. Validation loss during training for three learning rates. The red run diverges, the blue run " +
  "is still falling at the end, and the green run converges.", { size: 9.5, font: "I", center: true, after: 12 });

heading("4. Recommendations");
para("First, start at 0.01. In our runs it was the best single value, and it is a common default for plain " +
  "stochastic gradient descent.");
para("Second, if the loss goes up during the first epoch, divide the learning rate by ten and start again. " +
  "Do not wait: a run that diverges early does not recover.");
para("Third, if the loss falls steadily but slowly, multiply the learning rate by three. Stop increasing it " +
  "as soon as the final loss gets worse, as it did here at 0.1.");

heading("5. Limitations");
para("These results come from one small network and one dataset. Larger models, other optimizers such as Adam, " +
  "and learning rate schedules can all move the best value. The method of trying a few rates a factor of ten " +
  "apart carries over; the specific numbers do not.");

// ---- write the PDF ----
const objects = [];
const add = (body) => { objects.push(body); return objects.length; };        // returns the object number
const catalog = add("");
const pagesObj = add("");
const f1 = add("<< /Type /Font /Subtype /Type1 /BaseFont /Times-Roman /Encoding /WinAnsiEncoding >>");
const f2 = add("<< /Type /Font /Subtype /Type1 /BaseFont /Times-Bold /Encoding /WinAnsiEncoding >>");
const f3 = add("<< /Type /Font /Subtype /Type1 /BaseFont /Times-Italic /Encoding /WinAnsiEncoding >>");
const kids = [];
pages.forEach((ops, n) => {
  const footer = `BT /F1 9 Tf ${PAGE_W / 2 - 3} 48 Td (${n + 1}) Tj ET`;
  const stream = ops.join("\n") + "\n" + footer + "\n";
  const content = add(`<< /Length ${Buffer.byteLength(stream, "latin1")} >>\nstream\n${stream}endstream`);
  kids.push(add(`<< /Type /Page /Parent ${pagesObj} 0 R /MediaBox [0 0 ${PAGE_W} ${PAGE_H}] ` +
    `/Resources << /Font << /F1 ${f1} 0 R /F2 ${f2} 0 R /F3 ${f3} 0 R >> >> /Contents ${content} 0 R >>`));
});
objects[catalog - 1] = `<< /Type /Catalog /Pages ${pagesObj} 0 R >>`;
objects[pagesObj - 1] = `<< /Type /Pages /Kids [${kids.map((k) => k + " 0 R").join(" ")}] /Count ${kids.length} >>`;

let pdf = "%PDF-1.4\n";
const offsets = [];
objects.forEach((body, k) => { offsets.push(Buffer.byteLength(pdf, "latin1")); pdf += `${k + 1} 0 obj\n${body}\nendobj\n`; });
const xref = Buffer.byteLength(pdf, "latin1");
pdf += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n` + offsets.map((o) => String(o).padStart(10, "0") + " 00000 n \n").join("");
pdf += `trailer\n<< /Size ${objects.length + 1} /Root ${catalog} 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
const file = path.join(__dirname, "learning-rate-note.pdf");
fs.writeFileSync(file, Buffer.from(pdf, "latin1"));
console.log(`wrote ${file}: ${pages.length} pages, ${pdf.length} bytes`);
