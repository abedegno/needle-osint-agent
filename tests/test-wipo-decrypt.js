// Deterministic offline test: the vendored crypto-js + key construction + parsing must reproduce
// the known plaintext of a frozen (uuid, ciphertext) fixture. No network.
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const { decrypt } = require("../bin/lib/wipo-search.js");

const fx = JSON.parse(fs.readFileSync(path.join(__dirname, "fixtures/wipo-search-fixture.json"), "utf8"));
const o = decrypt(fx.uuid, fx.ciphertext_b64);
assert.ok(o && o.response, "decrypt did not return a {response} object");
assert.strictEqual(o.response.numFound, fx.expect_numFound, "numFound mismatch");
assert.deepStrictEqual(o.response.docs[0].brandName, fx.expect_first_brand, "first brand mismatch");
console.log("decrypt fixture OK: numFound", o.response.numFound, "first", JSON.stringify(o.response.docs[0].brandName));
