#!/usr/bin/env -S deno run --allow-read --allow-write
/**
 * MathML to OMML converter script
 * Reads MathML from stdin or file argument, outputs OMML to stdout
 *
 * Usage:
 *   echo '<math>...</math>' | deno run --allow-read mml2omml.ts
 *   deno run --allow-read mml2omml.ts input.xml
 */

import { mml2omml } from "npm:mathml2omml";

async function main() {
  let mathml: string;

  if (Deno.args.length > 0) {
    // Read from file argument
    mathml = await Deno.readTextFile(Deno.args[0]);
  } else {
    // Read from stdin
    const decoder = new TextDecoder();
    const buf = new Uint8Array(1024 * 1024); // 1MB buffer
    let input = "";
    let n = await Deno.stdin.read(buf);
    while (n !== null) {
      input += decoder.decode(buf.subarray(0, n));
      n = await Deno.stdin.read(buf);
    }
    mathml = input;
  }

  if (!mathml.trim()) {
    console.error("Error: Empty input");
    Deno.exit(1);
  }

  try {
    const omml = mml2omml(mathml.trim());
    console.log(omml);
  } catch (e) {
    console.error(`Error converting MathML: ${e}`);
    Deno.exit(1);
  }
}

main();
