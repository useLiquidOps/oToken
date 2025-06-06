import { expect } from "@jest/globals";
import {
  createMessage,
  env,
  normalizeTags,
  setupProcess,
  HandleFunction,
  generateOracleResponse,
  generateArweaveAddress,
  defaultTimestamp,
  getMessageByAction
} from "./utils";

describe("Token standard functionalities", () => {
  let handle: HandleFunction;
  let tags: Record<string, string>;
  let testWallet: string;
  let recipientWallet: string;

  const testQty = "1000000000000000";
  const transferQty = "12507";

  beforeAll(() => {
    tags = normalizeTags(env.Process.Tags);
    testWallet = generateArweaveAddress();
    recipientWallet = generateArweaveAddress();
  });

  beforeEach(async () => {
    handle = await setupProcess(env);

    // mint some tokens for transfer and balance tests
    const mintRes = await handle(createMessage({
      Action: "Credit-Notice",
      "X-Action": "Mint",
      Owner: tags["Collateral-Id"],
      From: tags["Collateral-Id"],
      "From-Process": tags["Collateral-Id"],
      Quantity: testQty,
      Recipient: env.Process.Id,
      Sender: testWallet
    }));
    await handle(createMessage({
      "Queued-User": testWallet,
      "X-Reference": normalizeTags(
        getMessageByAction("Add-To-Queue", mintRes.Messages)?.Tags || []
      )["Reference"]
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
              name: "Collateral-Factor",
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
              name: "Value-Limit",
              value: env.Process.Tags.find(
                ({ name }) => name === "Value-Limit"
              )?.value
            }),
            expect.objectContaining({
              name: "Oracle",
              value: expect.toBeArweaveAddress()
            }),
            expect.objectContaining({
              name: "Oracle-Delay-Tolerance",
              value: expect.toBeIntegerStringEncoded()
            }),
            expect.objectContaining({
              name: "Cash",
              value: expect.toBeIntegerStringEncoded()
            }),
            expect.objectContaining({
              name: "Total-Borrows",
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
              value: testQty
            }),
            expect.objectContaining({
              name: "Ticker",
              value: expect.any(String)
            })
          ]),
          Data: expect.toBeIntegerStringEncoded()
        })
      ])
    );
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
      Recipient: testWallet,
      From: testWallet,
      Owner: testWallet
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
    // mint some tokens for the other wallet
    const otherWalletBal = "475387"
    const mintRes = await handle(createMessage({
      Action: "Credit-Notice",
      "X-Action": "Mint",
      Owner: tags["Collateral-Id"],
      From: tags["Collateral-Id"],
      "From-Process": tags["Collateral-Id"],
      Quantity: otherWalletBal,
      Recipient: env.Process.Id,
      Sender: recipientWallet
    }));
    await handle(createMessage({
      "Queued-User": recipientWallet,
      "X-Reference": normalizeTags(
        getMessageByAction("Add-To-Queue", mintRes.Messages)?.Tags || []
      )["Reference"]
    }));

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
            [testWallet]: testQty,
            [recipientWallet]: otherWalletBal
          }))
        })
      ])
    )
  });

  it("Prevents transferring if the user is queued in the controller", async () => {
    // send transfer
    const queueRes = await handle(createMessage({
      Action: "Transfer",
      Quantity: transferQty,
      Recipient: recipientWallet,
      From: testWallet,
      Owner: testWallet
    }));

    expect(queueRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: env.Process.Owner,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Add-To-Queue"
            }),
            expect.objectContaining({
              name: "User",
              value: testWallet
            })
          ])
        })
      ])
    );

    const queueResTags = normalizeTags(
      getMessageByAction("Add-To-Queue", queueRes.Messages)?.Tags || []
    );

    // reply with in-queue response
    const res = await handle(createMessage({
      "Error": "Could not queue user",
      "X-Reference": queueResTags["Reference"]
    }));

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: testWallet,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "The sender is already queued for an operation"
              )
            })
          ])
        })
      ])
    );

    // do not include unqueue message
    expect(res.Messages).toEqual(
      expect.not.arrayContaining([
        expect.objectContaining({
          Target: env.Process.Owner,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Remove-From-Queue"
            }),
            expect.objectContaining({
              name: "User",
              value: testWallet
            })
          ])
        })
      ])
    );
  });

  it("Prevents transferring to an invalid address", async () => {
    const msg = createMessage({
      Action: "Transfer",
      Quantity: transferQty,
      Recipient: "invalid",
      From: testWallet,
      Owner: testWallet
    });

    // send transfer
    const queueRes = await handle(msg);

    expect(queueRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: env.Process.Owner,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Add-To-Queue"
            }),
            expect.objectContaining({
              name: "User",
              value: testWallet
            })
          ])
        })
      ])
    );

    const queueResTags = normalizeTags(
      getMessageByAction("Add-To-Queue", queueRes.Messages)?.Tags || []
    );

    // queue response
    const oracleRes = await handle(createMessage({
      "Queued-User": msg.From,
      "X-Reference": queueResTags["Reference"]
    }));

    expect(oracleRes.Messages).toEqual(
      expect.arrayContaining([
        expect.oracleRequest([tags["Collateral-Ticker"]])
      ])
    );

    const res = await handle(
      generateOracleResponse({ AR: 8.425 }, oracleRes)
    );

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: msg.From,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Invalid address"
              )
            })
          ])
        }),
        expect.objectContaining({
          Target: env.Process.Owner,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Remove-From-Queue"
            }),
            expect.objectContaining({
              name: "User",
              value: testWallet
            })
          ])
        })
      ])
    );
  });

  it("Prevents the sender from transferring to themselves", async () => {
    const msg = createMessage({
      Action: "Transfer",
      Quantity: transferQty,
      Recipient: testWallet,
      From: testWallet,
      Owner: testWallet
    });

    // send transfer
    const queueRes = await handle(msg);

    expect(queueRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: env.Process.Owner,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Add-To-Queue"
            }),
            expect.objectContaining({
              name: "User",
              value: testWallet
            })
          ])
        })
      ])
    );

    const queueResTags = normalizeTags(
      getMessageByAction("Add-To-Queue", queueRes.Messages)?.Tags || []
    );

    // queue response
    const oracleRes = await handle(createMessage({
      "Queued-User": msg.From,
      "X-Reference": queueResTags["Reference"]
    }));

    expect(oracleRes.Messages).toEqual(
      expect.arrayContaining([
        expect.oracleRequest([tags["Collateral-Ticker"]])
      ])
    );

    const res = await handle(
      generateOracleResponse({ AR: 8.425 }, oracleRes)
    );

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: msg.From,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Target cannot be the sender"
              )
            })
          ])
        }),
        expect.objectContaining({
          Target: env.Process.Owner,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Remove-From-Queue"
            }),
            expect.objectContaining({
              name: "User",
              value: testWallet
            })
          ])
        })
      ])
    );
  });

  it("Prevents sending an invalid quantity", async () => {
    const msg = createMessage({
      Action: "Transfer",
      Quantity: "-1",
      Recipient: recipientWallet,
      From: testWallet,
      Owner: testWallet
    });

    // send transfer
    const queueRes = await handle(msg);

    expect(queueRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: env.Process.Owner,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Add-To-Queue"
            }),
            expect.objectContaining({
              name: "User",
              value: testWallet
            })
          ])
        })
      ])
    );

    const queueResTags = normalizeTags(
      getMessageByAction("Add-To-Queue", queueRes.Messages)?.Tags || []
    );

    // queue response
    const oracleRes = await handle(createMessage({
      "Queued-User": msg.From,
      "X-Reference": queueResTags["Reference"]
    }));

    expect(oracleRes.Messages).toEqual(
      expect.arrayContaining([
        expect.oracleRequest([tags["Collateral-Ticker"]])
      ])
    );

    const res = await handle(
      generateOracleResponse({ AR: 8.425 }, oracleRes)
    );

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: msg.From,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Invalid transfer quantity"
              )
            })
          ])
        }),
        expect.objectContaining({
          Target: env.Process.Owner,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Remove-From-Queue"
            }),
            expect.objectContaining({
              name: "User",
              value: testWallet
            })
          ])
        })
      ])
    );
  });

  it("Prevents transferring more than the wallet balance", async () => {
    const msg = createMessage({
      Action: "Transfer",
      Quantity: (BigInt(transferQty) + 1n).toString(),
      Recipient: testWallet
    });

    // send transfer
    const queueRes = await handle(msg);

    expect(queueRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: env.Process.Owner,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Add-To-Queue"
            }),
            expect.objectContaining({
              name: "User",
              value: msg.From
            })
          ])
        })
      ])
    );

    const queueResTags = normalizeTags(
      getMessageByAction("Add-To-Queue", queueRes.Messages)?.Tags || []
    );

    // queue response
    const oracleRes = await handle(createMessage({
      "Queued-User": msg.From,
      "X-Reference": queueResTags["Reference"]
    }));

    expect(oracleRes.Messages).toEqual(
      expect.arrayContaining([
        expect.oracleRequest([tags["Collateral-Ticker"]])
      ])
    );

    const res = await handle(
      generateOracleResponse({ AR: 8.425 }, oracleRes)
    );

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: msg.From,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Insufficient balance"
              )
            })
          ])
        }),
        expect.objectContaining({
          Target: env.Process.Owner,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Remove-From-Queue"
            }),
            expect.objectContaining({
              name: "User",
              value: msg.From
            })
          ])
        })
      ])
    );
  });

  it("Prevents transferring when no data is returned from the oracle", async () => {
    const msg = createMessage({
      Action: "Transfer",
      Quantity: "1",
      Recipient: recipientWallet,
      From: testWallet,
      Owner: testWallet
    });

    // send transfer
    const queueRes = await handle(msg);

    expect(queueRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: env.Process.Owner,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Add-To-Queue"
            }),
            expect.objectContaining({
              name: "User",
              value: testWallet
            })
          ])
        })
      ])
    );

    const queueResTags = normalizeTags(
      getMessageByAction("Add-To-Queue", queueRes.Messages)?.Tags || []
    );

    // queue response
    const oracleRes = await handle(createMessage({
      "Queued-User": msg.From,
      "X-Reference": queueResTags["Reference"]
    }));

    expect(oracleRes.Messages).toEqual(
      expect.arrayContaining([
        expect.oracleRequest([tags["Collateral-Ticker"]])
      ])
    );

    const res = await handle(
      generateOracleResponse({ BTC: 85325.425 }, oracleRes)
    );
    
    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: testWallet,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "AR price has not been received from the oracle"
              )
            })
          ])
        }),
        expect.objectContaining({
          Target: env.Process.Owner,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Remove-From-Queue"
            }),
            expect.objectContaining({
              name: "User",
              value: testWallet
            })
          ])
        })
      ])
    );
  });

  it("Prevents transferring on outdated oracle data", async () => {
    const msg = createMessage({
      Action: "Transfer",
      Quantity: "1",
      Recipient: recipientWallet,
      From: testWallet,
      Owner: testWallet
    });

    // send transfer
    const queueRes = await handle(msg);

    expect(queueRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: env.Process.Owner,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Add-To-Queue"
            }),
            expect.objectContaining({
              name: "User",
              value: testWallet
            })
          ])
        })
      ])
    );

    const queueResTags = normalizeTags(
      getMessageByAction("Add-To-Queue", queueRes.Messages)?.Tags || []
    );

    // queue response
    const res = await handle(createMessage({
      "Queued-User": testWallet,
      "X-Reference": queueResTags["Reference"]
    }));

    // expect collateralization check oracle request
    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.oracleRequest([tags["Collateral-Ticker"]])
      ])
    );

    // send dummy oracle data (outdated)
    const oracleInputRes = await handle(
      generateOracleResponse({
        AR: {
          v: 17.96991872,
          // make sure the timestamp is older than the message timestamp minus the oracle delay tolerance
          t: parseInt(defaultTimestamp) - parseInt(tags["Oracle-Delay-Tolerance"]) - 1
        }
      }, res)
    );

    expect(oracleInputRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: msg.From,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "AR price is outdated"
              )
            })
          ])
        }),
        expect.objectContaining({
          Target: env.Process.Owner,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Remove-From-Queue"
            }),
            expect.objectContaining({
              name: "User",
              value: testWallet
            })
          ])
        })
      ])
    );
  });

  it("Transfers assets", async () => {
    // this will fail if the previous tests failed (they drain the balance)
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
    const queueRes = await handle(msg);

    expect(queueRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: env.Process.Owner,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Add-To-Queue"
            }),
            expect.objectContaining({
              name: "User",
              value: testWallet
            })
          ])
        })
      ])
    );

    const queueResTags = normalizeTags(
      getMessageByAction("Add-To-Queue", queueRes.Messages)?.Tags || []
    );

    // queue response
    const oracleRes = await handle(createMessage({
      "Queued-User": msg.From,
      "X-Reference": queueResTags["Reference"]
    }));

    expect(oracleRes.Messages).toEqual(
      expect.arrayContaining([
        expect.oracleRequest([tags["Collateral-Ticker"]])
      ])
    );

    const res = await handle(
      generateOracleResponse({ AR: 8.425 }, oracleRes)
    );

    // expect successful transfer
    expect(res.Messages).toEqual(
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
        }),
        expect.objectContaining({
          Target: env.Process.Owner,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Remove-From-Queue"
            }),
            expect.objectContaining({
              name: "User",
              value: testWallet
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

  it("Prevents transferring when the transfer would require higher collateralization (loan is on friend process)", async () => {
    // setup env
    const friend = {
      id: generateArweaveAddress(),
      oToken: generateArweaveAddress(),
      ticker: "TST",
      denomination: "12"
    };
    const friendTicker = "TST";
    const envWithFriend = {
      Process: {
        ...env.Process,
        Tags: env.Process.Tags.map((t) => {
          if (t.name !== "Friends") return t;
          return { name: t.name, value: JSON.stringify([friend]) }
        })
      }
    };

    // setup process
    const handle = await setupProcess(envWithFriend);

    // check if friend has been added
    const friendsListRes = await handle(createMessage({
      Action: "List-Friends"
    }));

    expect(friendsListRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Friend-List"
            })
          ]),
          Data: expect.toBeJsonEncoded(
            expect.arrayContaining([friend])
          )
        })
      ])
    );

    // mint tokens
    const mintRes = await handle(createMessage({
      Action: "Credit-Notice",
      "X-Action": "Mint",
      Owner: tags["Collateral-Id"],
      From: tags["Collateral-Id"],
      "From-Process": tags["Collateral-Id"],
      Quantity: testQty,
      Recipient: env.Process.Id,
      Sender: testWallet
    }));
    await handle(createMessage({
      "Queued-User": testWallet,
      "X-Reference": normalizeTags(
        getMessageByAction("Add-To-Queue", mintRes.Messages)?.Tags || []
      )["Reference"]
    }));

    // initiate transfer
    const transferMsg = createMessage({
      Action: "Transfer",
      Quantity: testQty,
      Recipient: recipientWallet,
      From: testWallet,
      Owner: testWallet
    });

    const queueRes = await handle(transferMsg);

    expect(queueRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: env.Process.Owner,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Add-To-Queue"
            }),
            expect.objectContaining({
              name: "User",
              value: testWallet
            })
          ])
        })
      ])
    );

    const queueResTags = normalizeTags(
      getMessageByAction("Add-To-Queue", queueRes.Messages)?.Tags || []
    );

    // queue response
    const oracleRes = await handle(createMessage({
      "Queued-User": testWallet,
      "X-Reference": queueResTags["Reference"]
    }));

    expect(oracleRes.Messages).toEqual(
      expect.arrayContaining([
        expect.oracleRequest([tags["Collateral-Ticker"]])
      ])
    );

    // here we use a very large price in order to simulate
    // an environment, where the transfer would cause
    // the loan in the friend process to be undercollateralized.
    // in reality, this would make the loan available for liquidation
    const res = await handle(
      generateOracleResponse({ AR: 8.425, TST: 22.55 }, oracleRes)
    );

    // expect request to the friend process for position info
    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: friend.oToken,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Position"
            }),
            expect.objectContaining({
              name: "Recipient",
              value: testWallet
            })
          ])
        })
      ])
    );

    const capacitiesOracleInputResTags = normalizeTags(
      res.Messages
        .find((msg) => normalizeTags(msg.Tags)["Action"] === "Position")
        ?.Tags || []
    );

    // dummy position response
    const positionMsg = createMessage({
      Owner: friend.oToken,
      From: friend.oToken,
      "X-Reference": capacitiesOracleInputResTags["Reference"],
      Action: "Collateralization-Response",
      Collateralization: "0",
      Capacity: "0",
      "Borrow-Balance": "1000000000000",
      "Liquidation-Limit": "0",
      "Collateral-Ticker": friendTicker,
      "Collateral-Denomination": "12"
    });
    const positionRes = await handle(positionMsg);

    // collateral price is already cached, so the process
    // will not ask for prices anymore
    // expect error
    expect(positionRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: testWallet,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Transfer value is too high and requires higher collateralization"
              )
            })
          ])
        }),
        expect.objectContaining({
          Target: env.Process.Owner,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Remove-From-Queue"
            }),
            expect.objectContaining({
              name: "User",
              value: testWallet
            })
          ])
        })
      ])
    );

    // expect balances to not change
    const balancesRes = await handle(createMessage({
      Action: "Balances",
      From: testWallet,
      Owner: testWallet
    }));

    expect(balancesRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: testWallet,
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
    );
  });
});
