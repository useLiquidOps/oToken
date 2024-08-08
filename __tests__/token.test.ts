import { createMessage, env, setupProcess } from "./utils";
import { it, describe, before } from "node:test";
import AoLoader from "@permaweb/ao-loader";
import assert from "node:assert";

describe("Token standard functionalities", () => {
  let handle: AoLoader.handleFunction;
  let memory: ArrayBuffer | null = null;

  before(async () => handle = await setupProcess());

  it("Returns token info", async () => {
    const message = createMessage({ Action: "Info" });
    const res = handle(memory, message, env);

    console.log(res);
    /*assert.deepEqual(res.Messages, [{

    }])
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
    )*/

    memory = res.Memory;
  });
});
