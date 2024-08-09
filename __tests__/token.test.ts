import { createMessage, env, setupProcess } from "./utils";
import AoLoader from "@permaweb/ao-loader";
import { expect } from "@jest/globals";

describe("Token standard functionalities", () => {
  let handle: AoLoader.handleFunction;
  let memory: ArrayBuffer | null = null;

  beforeAll(async () => {
    handle = await setupProcess();
  });

  it("Returns token info", async () => {
    const message = createMessage({ Action: "Info" });
    const res = handle(memory, message, env);

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: message.From,
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
              value: expect.toBeArweaveAddress()
            }),
            expect.objectContaining({
              name: "Denomination",
              value: expect.toBeIntegerStringEncoded()
            })
          ])
        })
      ])
    )

    memory = res.Memory;
  });

  //it("")
});
