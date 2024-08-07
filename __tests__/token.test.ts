import { expect, test, describe, beforeAll } from "bun:test";
import AoLoader, { type Environment } from "@permaweb/ao-loader";
import { env } from "./utils";
import fs from "fs/promises";
import path from "path";

describe("Token standard functionalities", () => {
  let handle: AoLoader.handleFunction;
  let memory: ArrayBuffer | null = null;

  beforeAll(async () => {
    const wasmBinary = await fs.readFile(path.join(__dirname, "../src/process.wasm"));
    // @ts-expect-error
    handle = await AoLoader(wasmBinary, { format: "wasm32-unknown-emscripten2" });
  });

  test("Returns token info", async () => {
    const res = handle(memory, {
      Target: env.Process.Id,
      Owner: env.Process.Owner,
      From: env.Process.Owner,
      Tags: [
        { name: "Action", value: "Info" }
      ],
      Cron: false,
      "Block-Height": "1",
      Timestamp: "172302981"
    }, (env as unknown) as Environment);

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Name",
              value: expect.any(String)
            }),
            expect.objectContaining({
              name: "Ticker",
              value: expect.any(String)
            }),
            expect.objectContaining({
              name: "Logo",
              value: expect.any(String)
            }),
            expect.objectContaining({
              name: "Denomination",
              value: expect.any(String)
            })
          ])
        })
      ])
    )

    memory = res.Memory;
  });
});
