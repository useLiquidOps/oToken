import { createMessage, env, normalizeTags, setupProcess, HandleFunction, generateOracleResponse } from "./utils";
import { expect } from "@jest/globals";

describe("Token standard functionalities", () => {
  let handle: HandleFunction;

  const testWallet = "yrsibjwtvbgqjkuqoquppebfdntvrztgmupvikndumk";
  const testQty = "1000000000000000";

  beforeAll(async () => {
    handle = await setupProcess(env);

    // mint some tokens for transfer and balance tests
    const tags = normalizeTags(env.Process.Tags);
    await handle(createMessage({
      Action: "Credit-Notice",
      "X-Action": "Mint",
      Owner: tags["Collateral-Id"],
      From: tags["Collateral-Id"],
      "From-Process": tags["Collateral-Id"],
      Quantity: testQty,
      Recipient: env.Process.Id,
      Sender: testWallet
    }));
  });

  it("Returns token info", async () => {
    const message = createMessage({ Action: "Info" });
    const res = await handle(message);

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
            }),
            expect.objectContaining({
              name: "Collateral-Id",
              value: expect.toBeArweaveAddress()
            }),
            expect.objectContaining({
              name: "Collateral-Ratio",
              value: expect.toBeFloatStringEncoded()
            }),
            expect.objectContaining({
              name: "Collateral-Denomination",
              value: expect.toBeIntegerStringEncoded()
            }),
            expect.objectContaining({
              name: "Liquidation-Threshold",
              value: expect.toBeFloatStringEncoded()
            }),
            expect.objectContaining({
              name: "Oracle",
              value: expect.toBeArweaveAddress()
            }),
            expect.objectContaining({
              name: "Oracle-Delay-Tolerance",
              value: expect.toBeIntegerStringEncoded()
            })
          ])
        })
      ])
    )
  });

  it("Returns token total supply", async () => {
    const message = createMessage({ Action: "Total-Supply" });
    const res = await handle(message);

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
  });

  it("Returns wallet balance", async () => {
    const message = createMessage({
      Action: "Balance",
      Owner: testWallet,
      From: testWallet
    });
    const res = await handle(message);

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: message.From,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Balance",
              value: testQty
            }),
            expect.objectContaining({
              name: "Ticker",
              value: expect.any(String)
            })
          ]),
          Data: testQty
        })
      ])
    )
/*
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
*/
  });

  it("Returns wallet balance for recipient", async () => {
    const message = createMessage({
      Action: "Balance",
      Recipient: testWallet
    });
    const res = await handle(message);

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: message.From,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Balance",
              value: testQty
            }),
            expect.objectContaining({
              name: "Ticker",
              value: expect.any(String)
            })
          ]),
          Data: testQty
        })
      ])
    )
  });

  it("Returns all wallet balances", async () => {
    const msg = createMessage({ Action: "Balances" });
    const res = await handle(msg);

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: msg.From,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Ticker",
              value: expect.any(String)
            })
          ]),
          Data: expect.toBeJsonEncoded(expect.objectContaining({
            [testWallet]: testQty
          }))
        })
      ])
    )
  });

  it("Transfers assets", async () => {
    const recipientWallet = "F72_1lyx0Y9QW7m3ePcED5KRETjuaGM6j7JrbPfJAEk";
    const transferQty = "12507";
    const testForwardTag = {
      name: "X-Forward-Test",
      value: "testVal"
    };
    const envTags = normalizeTags(env.Process.Tags);
    const msg = createMessage({
      Action: "Transfer",
      Quantity: transferQty,
      Recipient: recipientWallet,
      From: testWallet,
      Owner: testWallet,
      [testForwardTag.name]: testForwardTag.value
    });

    // send transfer
    const res = await handle(msg);

    // expect collateralization check oracle request
    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: envTags["Oracle"],
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "v2.Request-Latest-Data"
            }),
            expect.objectContaining({
              name: "Tickers",
              value: expect.toBeJsonEncoded(
                expect.arrayContaining([envTags["Collateral-Ticker"]])
              )
            })
          ])
        })
      ])
    );

    // send dummy oracle data
    const oracleInputRes = await handle(
      generateOracleResponse({ AR: 17.96991872 }, res)
    );

    // expect successful transfer
    expect(oracleInputRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: msg.From,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Debit-Notice"
            }),
            expect.objectContaining({
              name: "Recipient",
              value: recipientWallet
            }),
            expect.objectContaining({
              name: "Quantity",
              value: transferQty
            }),
            expect.objectContaining({
              name: testForwardTag.name,
              value: testForwardTag.value
            })
          ])
        }),
        expect.objectContaining({
          Target: recipientWallet,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Credit-Notice"
            }),
            expect.objectContaining({
              name: "Sender",
              value: testWallet
            }),
            expect.objectContaining({
              name: "Quantity",
              value: transferQty
            }),
            expect.objectContaining({
              name: testForwardTag.name,
              value: testForwardTag.value
            })
          ])
        })
      ])
    )

    // check if balances have been updated correctly
    const balancesRes = await handle(createMessage({
      Action: "Balances",
      From: testWallet,
      Owner: testWallet
    }));

    expect(balancesRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: msg.From,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Ticker",
              value: expect.any(String)
            })
          ]),
          Data: expect.toBeJsonEncoded(expect.objectContaining({
            [testWallet]: (BigInt(testQty) - BigInt(transferQty)).toString(),
            [recipientWallet]: transferQty
          }))
        })
      ])
    );
  });
});
