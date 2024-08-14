import { createMessage, env, setupProcess } from "./utils";
import AoLoader from "@permaweb/ao-loader";
import { expect } from "@jest/globals";
import { writeFileSync } from "fs"
import { join } from "path"

describe("Token standard functionalities", () => {
  let handle: AoLoader.handleFunction;
  let memory: ArrayBuffer | null = null;

  beforeAll(async () => {
    handle = await setupProcess();
  });

  it("Returns token info", async () => {
    const message = createMessage({ Action: "Info" });
    const res = await handle(memory, message, env);

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

  it("Returns token total supply", async () => {
    const message = createMessage({ Action: "Total-Supply" });
    const res = await handle(memory, message, env);

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: message.From,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Total-Supply",
              value: expect.toBeIntegerStringEncoded()
            }),
            expect.objectContaining({
              name: "Ticker",
              value: expect.any(String)
            })
          ]),
          Data: expect.toBeIntegerStringEncoded()
        })
      ])
    )

    memory = res.Memory;
  });

  it("Returns wallet balance", async () => {

  });

  it("Returns all wallet balances", async () => {

  });

  it("Transfers assets", async () => {
    
  });
});
