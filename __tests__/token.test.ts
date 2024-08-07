import { expect, test, describe, beforeAll } from "bun:test";
import AoLoader from "@permaweb/ao-loader";
import { env } from "./utils";
import fs from "fs/promises";
import path from "path";

describe("Token standard functionalities", () => {
  let handle: AoLoader.handleFunction;

  beforeAll(async () => {
    const wasmBinary = await fs.readFile(path.join(__dirname, "../src/process.wasm"));
    // @ts-expect-error
    handle = await AoLoader(wasmBinary, {
      format: "wasm32-unknown-emscripten2",
      inputEncoding: "JSON-1",
      outputEncoding: "JSON-1", 
      memoryLimit: "524288000",
      computeLimit: 9e12.toString(),
      extensions: []
    })
  });

  test("Returns token info", async () => {
    const res = handle(null, {
      Target: env.process.id,
      Owner: env.process.owner,
      From: env.process.owner,
      Tags: [
        { name: "Action", value: "Info" }
      ],
      Cron: false,
      "Block-Height": "1",
      Timestamp: "172302981"
    }, env);

    console.log(res);
  });
});
