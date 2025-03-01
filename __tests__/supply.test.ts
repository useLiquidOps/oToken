import { expect } from "@jest/globals";
import {
  env,
  setupProcess,
  HandleFunction,
  generateArweaveAddress,
  createMessage,
  normalizeTags,
  getMessageByAction
} from "./utils";

describe("Minting and providing", () => {
  let handle: HandleFunction;
  let testWallet: string;
  let tags: Record<string, string>;

  const testQty = "1000000000000000";

  beforeAll(() => {
    testWallet = generateArweaveAddress();
    tags = normalizeTags(env.Process.Tags);
  });

  beforeEach(async () => {
    handle = await setupProcess(env);
  });

  it("Refunds 3rd party tokens", async () => {
    const otherToken = generateArweaveAddress();

    const res = await handle(createMessage({
      Action: "Credit-Notice",
      "X-Action": "Mint",
      Owner: otherToken,
      From: otherToken,
      "From-Process": otherToken,
      Quantity: testQty,
      Recipient: env.Process.Id,
      Sender: testWallet
    }));

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: otherToken,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Transfer"
            }),
            expect.objectContaining({
              name: "Quantity",
              value: testQty
            }),
            expect.objectContaining({
              name: "Recipient",
              value: testWallet
            }),
            expect.objectContaining({
              name: "X-Action",
              value: "Refund"
            }),
            expect.objectContaining({
              name: "X-Refund-Reason",
              value: expect.stringContaining(
                "This process does not accept the transferred token"
              )
            })
          ])
        })
      ])
    );
  });

  it("Does not throw unhandled error for debit notices", async () => {
    const res = await handle(createMessage({
      Action: "Debit-Notice",
      Owner: tags["Collateral-Id"],
      From: tags["Collateral-Id"],
      "From-Process": tags["Collateral-Id"],
      Quantity: "15",
      Recipient: generateArweaveAddress()
    }));

    expect(res.Messages).toEqual([]);
    expect(res.Messages).toHaveLength(0);
  });

  it("Does not handle invalid token quantities", async () => {
    const invalidQty = "-10000000";
    const res = await handle(createMessage({
      Action: "Credit-Notice",
      "X-Action": "Mint",
      Owner: tags["Collateral-Id"],
      From: tags["Collateral-Id"],
      "From-Process": tags["Collateral-Id"],
      Quantity: invalidQty,
      Recipient: env.Process.Id,
      Sender: testWallet
    }));

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: tags["Collateral-Id"],
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Transfer"
            }),
            expect.objectContaining({
              name: "Recipient",
              value: testWallet
            }),
            expect.objectContaining({
              name: "Quantity",
              value: invalidQty
            })
          ])
        }),
        expect.objectContaining({
          Target: testWallet,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Mint-Error"
            }),
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Invalid incoming transfer quantity"
              )
            }),
            expect.objectContaining({
              name: "Refund-Quantity",
              value: invalidQty
            })
          ])
        })
      ])
    );
  });

  it("Does not handle mint quantity above the value limit", async () => {
    const depositQty = (BigInt(tags["Value-Limit"]) + 1n).toString();
    const res = await handle(createMessage({
      Action: "Credit-Notice",
      "X-Action": "Mint",
      Owner: tags["Collateral-Id"],
      From: tags["Collateral-Id"],
      "From-Process": tags["Collateral-Id"],
      Quantity: depositQty,
      Recipient: env.Process.Id,
      Sender: testWallet
    }));

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: tags["Collateral-Id"],
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Transfer"
            }),
            expect.objectContaining({
              name: "Recipient",
              value: testWallet
            }),
            expect.objectContaining({
              name: "Quantity",
              value: depositQty
            })
          ])
        }),
        expect.objectContaining({
          Target: testWallet,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Mint-Error"
            }),
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Mint quantity is above the allowed limit"
              )
            }),
            expect.objectContaining({
              name: "Refund-Quantity",
              value: depositQty
            })
          ])
        })
      ])
    );
  });

  it("Mints the correct quantity on initial supply", async () => {
    const res = await handle(createMessage({
      Action: "Credit-Notice",
      "X-Action": "Mint",
      Owner: tags["Collateral-Id"],
      From: tags["Collateral-Id"],
      "From-Process": tags["Collateral-Id"],
      Quantity: testQty,
      Recipient: env.Process.Id,
      Sender: testWallet
    }));

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: testWallet,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Mint-Confirmation"
            }),
            expect.objectContaining({
              name: "Mint-Quantity",
              value: testQty
            }),
            expect.objectContaining({
              name: "Supplied-Quantity",
              value: testQty
            })
          ])
        })
      ])
    );
  });

  // for this we need to prepare the following way:
  // 1) mint tokens
  // 2) borrow tokens
  // 3) pay some interest (don't forget to change the timestamp so the interest is charged)
  // this way, the oToken worth increases, so it'll mint less tokens than the qty supplied
  it.todo("Mints the correct quantity with existing loans");
});

describe("Redeeming and burning", () => {
  let handle: HandleFunction;
  let testWallet: string;
  let tags: Record<string, string>;

  const testQty = "733456";

  beforeAll(() => {
    testWallet = generateArweaveAddress();
    tags = normalizeTags(env.Process.Tags);
  });

  beforeEach(async () => {
    handle = await setupProcess(env);
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

  it("Rejects redeeming if the user is already queued in the controller", async () => {
    const msg = createMessage({
      Action: "Redeem",
      Quantity: "2",
      From: testWallet,
      Owner: testWallet
    });

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
              value: msg.From
            })
          ])
        })
      ])
    );
  });

  it("Does not handle invalid token quantities", async () => {
    const msg = createMessage({
      Action: "Redeem",
      Quantity: "-12"
    });
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
    const res = await handle(createMessage({
      "Queued-User": msg.From,
      "X-Reference": queueResTags["Reference"]
    }));

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: msg.From,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Invalid redeem quantity"
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

  it("Rejects redeeming more than the available balance", async () => {
    const msg = createMessage({
      Action: "Redeem",
      Quantity: (BigInt(testQty) + 1n).toString()
    });
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
    const res = await handle(createMessage({
      "Queued-User": msg.From,
      "X-Reference": queueResTags["Reference"]
    }));

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: msg.From,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Not enough tokens to burn for this wallet"
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

  it("Rejects redeeming more than the value limit", async () => {
    const valueLimit = BigInt(tags["Value-Limit"]);

    for (let i = 0; i < 2; i++) {
      await handle(createMessage({
        Action: "Credit-Notice",
        "X-Action": "Mint",
        Owner: tags["Collateral-Id"],
        From: tags["Collateral-Id"],
        "From-Process": tags["Collateral-Id"],
        Quantity: tags["Value-Limit"],
        Recipient: env.Process.Id,
        Sender: env.Process.Owner
      }));
    }

    expect((await handle(createMessage({ Action: "Cash" }))).Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Cash",
              value: (BigInt(testQty) + valueLimit * 2n).toString()
            })
          ])
        })
      ])
    );

    const msg = createMessage({
      Action: "Redeem",
      Quantity: (valueLimit + 1n).toString()
    });
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
    const res = await handle(createMessage({
      "Queued-User": msg.From,
      "X-Reference": queueResTags["Reference"]
    }));

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: msg.From,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Redeem return quantity is above the allowed limit"
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

  it.todo("Rejects redeeming when there aren't enough available tokens");

  it.todo("Rejects redeeming when there is no price data returned");

  it.todo("Rejects redeeming when the redeem value is too high compared to the free borrow capacity");

  it.todo("Redeems the correct quantity");

  it.todo("Redeems the correct quantity after interests");
});

describe("Price and underlying asset value, pooled (empty)", () => {
  let handle: HandleFunction;

  const testQty = "4";

  beforeAll(async () => {
    handle = await setupProcess(env);
  });

  it("Supplies are empty on init", async () => {
    const msg = createMessage({ Action: "Info" });
    const res = await handle(msg);

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: msg.From,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Cash",
              value: "0"
            }),
            expect.objectContaining({
              name: "Total-Borrows",
              value: "0"
            })
          ])
        })
      ])
    );
  });

  it("Exchange rate current does not allow invalid quantities", async () => {
    const msg = createMessage({
      Action: "Exchange-Rate-Current",
      Quantity: "-12"
    });
    const res = await handle(msg);

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: msg.From,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Invalid token quantity"
              )
            })
          ])
        })
      ])
    );
  });

  it("Price is 1 when the supplies are empty", async () => {
    const msg = createMessage({
      Action: "Exchange-Rate-Current",
      Quantity: testQty
    });
    const res = await handle(msg);

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: msg.From,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Value",
              value: testQty
            }),
            expect.objectContaining({
              name: "Quantity",
              value: testQty
            })
          ])
        })
      ])
    );
  });

  it.todo("Price is the same as the input quantity on initial provide");
});

describe("Price and underlying asset value, supplies after initial provide", () => {
  let handle: HandleFunction;
  let testWallet: string;
  let tags: Record<string, string>;

  const testQty = "7469";

  beforeAll(() => {
    testWallet = generateArweaveAddress();
    tags = normalizeTags(env.Process.Tags);
  });

  beforeEach(async () => {
    handle = await setupProcess(env);
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

  it("Supplies return the correct quantities", async () => {
    const msg = createMessage({ Action: "Info" });
    const res = await handle(msg);

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: msg.From,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Cash",
              value: testQty
            }),
            expect.objectContaining({
              name: "Total-Borrows",
              value: "0"
            })
          ])
        })
      ])
    );
  });

  it.todo("Supplies return the correct quantities when there is an active borrow");

  it.todo("Returns the correct price after the oToken:collateral ratio is not 1:1");

  it.todo("Price input quantity is 1 by default when there is no quantity provided");
});
