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
    const collateral = "0000000000000000000000000000000000000000002"
    const oracle = "00000000000000000000000000000000000000ORACLE"

    const mint1 = await handle(memory, createMessage({
      Action: "Credit-Notice",
      "X-Action": "Mint",
      Owner: collateral,
      From: collateral,
      "From-Process": collateral,
      Quantity: "1000000000000000",
      Recipient: env.Process.Id,
      Sender: "ljvCPN31XCLPkBo9FUeB7vAK0VC6-eY52-CS-6Iho8U"
    }), env);
    memory = mint1.Memory;

    const mint2 = await handle(memory, createMessage({
      Action: "Credit-Notice",
      "X-Action": "Mint",
      Owner: collateral,
      From: collateral,
      "From-Process": collateral,
      Quantity: "1000000000000000",
      Recipient: env.Process.Id,
      Sender: "0UWVo81RdMjeE08aZBfXoHAs1MQ-AX-A2RfGmOoNFKk"
    }), env);
    memory = mint2.Memory;

    const res = await handle(memory, createMessage({
      Action: "Global-Position",
      Owner: "ljvCPN31XCLPkBo9FUeB7vAK0VC6-eY52-CS-6Iho8U",
      From: "ljvCPN31XCLPkBo9FUeB7vAK0VC6-eY52-CS-6Iho8U",
    }), env);
    console.log(JSON.stringify(res.Messages, null, 2))

    const res2 = await handle(memory, createMessage({
      Action: "Positions",
      "X-Reference": res.Messages.find((msg) => msg.Tags.find(({ name }) => name === "Action")?.value === "v2.Request-Latest-Data")?.Tags?.find(({ name }) => name === "Reference")?.value || "0",
      Owner: oracle,
      From: oracle,
      Data: JSON.stringify({
        "AR": {
          "t": 1729682180000,
          "a": "0xDD682daEC5A90dD295d14DA4b0bec9281017b5bE",
          "v": 17.96991872
        }
      })
    }), env);
    console.log(JSON.stringify(res2.Messages, null, 2))

  });

  it("Returns all wallet balances", async () => {

  });

  it("Transfers assets", async () => {
    
  });
});
