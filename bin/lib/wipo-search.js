#!/usr/bin/env node
"use strict";
const https = require("https");
const crypto = require("crypto");
const path = require("path");
const CryptoJS = require(path.join(__dirname, "crypto-js.min.js"));

const HOST = "api.branddb.wipo.int";
const KEY_PREFIX = "8?)i_~Nk6qv0IX;2";
const FIELD = { owner: "applicant", brand: "brandName" };
const RE = "WIPO likely changed its scheme — re-derive (see BL-17 P2)";
// WIPO blocks requests with no User-Agent (403). Send browser-like headers on every call.
const BASE_HEADERS = {
  "User-Agent": "Mozilla/5.0",
  Accept: "application/json",
  Origin: "https://branddb.wipo.int",
  Referer: "https://branddb.wipo.int/",
};

function req(method, p, headers, body) {
  return new Promise((resolve, reject) => {
    const r = https.request({ host: HOST, path: p, method, headers: Object.assign({}, BASE_HEADERS, headers || {}), timeout: 30000 }, (rsp) => {
      const chunks = [];
      rsp.on("data", (c) => chunks.push(c));
      rsp.on("end", () => resolve({ status: rsp.statusCode, body: Buffer.concat(chunks).toString("utf8") }));
    });
    r.on("error", reject);
    r.on("timeout", () => r.destroy(new Error("timeout")));
    if (body) r.write(body);
    r.end();
  });
}

function solve(ch) {
  for (let n = 0; n <= ch.maxnumber; n++) {
    if (crypto.createHash("sha256").update(ch.salt + n).digest("hex") === ch.challenge) return n;
  }
  throw new Error("PoW: no solution in range");
}

function decrypt(uuid, ctB64) {
  const key = CryptoJS.enc.Utf8.parse(KEY_PREFIX + uuid);
  const pt = CryptoJS.AES.decrypt(ctB64, key, { mode: CryptoJS.mode.ECB }).toString(CryptoJS.enc.Utf8);
  if (!pt) throw new Error("decrypt produced empty output — " + RE);
  try { return JSON.parse(pt); } catch (e) { throw new Error("decrypt produced non-JSON — " + RE); }
}

async function search(mode, query, rows) {
  const field = FIELD[mode];
  if (!field) throw new Error("mode must be owner|brand");
  const uuid = crypto.randomUUID();
  const cap = await req("GET", "/captcha", {});
  if (cap.status !== 200) throw new Error("/captcha http " + cap.status + (cap.status === 429 ? " (rate-limited)" : ""));
  let ch;
  try { ch = JSON.parse(cap.body); } catch (e) { throw new Error("/captcha not JSON (rate-limited?): " + cap.body.slice(0, 80)); }
  if (!ch.maxnumber) throw new Error("/captcha not a challenge (rate-limited?): " + cap.body.slice(0, 80));
  const number = solve(ch);
  const payload = Buffer.from(JSON.stringify({ algorithm: ch.algorithm, challenge: ch.challenge, number, salt: ch.salt, signature: ch.signature })).toString("base64");
  const bind = await req("GET", "/dbinfo?token=" + encodeURIComponent(payload), { HashSearch: uuid });
  if (bind.status !== 200) throw new Error("/dbinfo bind http " + bind.status);
  const asStructure = JSON.stringify({ _id: "0", boolean: "AND", bricks: [{ _id: "1", key: field, value: query, strategy: "Simple" }] });
  const sbody = JSON.stringify({ sort: "score desc", rows: String(rows || 30), fg: "_void_", asStructure });
  const sr = await req("POST", "/search", { HashSearch: uuid, "Content-Type": "application/json" }, sbody);
  if (sr.status !== 200) throw new Error("/search http " + sr.status);
  const o = decrypt(uuid, sr.body.trim());
  const r = o.response || {};
  const docs = (r.docs || []).map((d) => ({
    brandName: d.brandName, applicant: d.applicant, applicantCountryCode: d.applicantCountryCode,
    office: d.office, applicationNumber: d.applicationNumber, registrationNumber: d.registrationNumber,
    status: d.status, niceClass: d.niceClass, markFeature: d.markFeature,
    applicationDate: d.applicationDate, registrationDate: d.registrationDate, st13: d.st13, kind: d.kind, type: d.type,
  }));
  return { numFound: r.numFound, docs };
}

module.exports = { decrypt, search, solve };

if (require.main === module) {
  const [mode, query, rows] = process.argv.slice(2);
  if (!mode || !query) { console.error("usage: wipo-search.js <owner|brand> <query> [rows]"); process.exit(2); }
  search(mode, query, rows ? parseInt(rows, 10) : 30)
    .then((r) => process.stdout.write(JSON.stringify(r)))
    .catch((e) => { console.error("wipo-search: " + e.message); process.exit(1); });
}
