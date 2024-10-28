import { expect } from "@jest/globals";
import {
  createMessage,
  env,
  normalizeTags,
  setupProcess,
  HandleFunction,
  generateOracleResponse,
  generateArweaveAddress
} from "./utils";

describe("Token standard functionalities", () => {
  let handle: HandleFunction;
  let tags: Record<string, string>;
  let testWallet: string;
  let recipientWallet: string;

  const testQty = "1000000000000000";
  const transferQty = "12507";

  beforeAll(async () => {
    handle = await setupProcess(env);
    tags = normalizeTags(env.Process.Tags);
    testWallet = generateArweaveAddress();
    recipientWallet = generateArweaveAddress();

    // mint some tokens for transfer and balance tests
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
    const testForwardTag = {
      name: "X-Forward-Test",
      value: "testVal"
    };
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
          Target: tags["Oracle"],
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "v2.Request-Latest-Data"
            }),
            expect.objectContaining({
              name: "Tickers",
              value: expect.toBeJsonEncoded(
                expect.arrayContaining([tags["Collateral-Ticker"]])
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
    );

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

  it("Prevents transferring more than the wallet balance", async () => {
    const msg = createMessage({
      Action: "Transfer",
      Quantity: (BigInt(transferQty) + 1n).toString(),
      Recipient: testWallet,
      From: recipientWallet,
      Owner: recipientWallet
    });

    // send transfer
    const res = await handle(msg);

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: msg.From,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.any(String)
            })
          ])
        })
      ])
    );
  });
});
