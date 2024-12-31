import { expect } from "@jest/globals";
import {
  createMessage,
  generateArweaveAddress,
  HandleFunction,
  normalizeTags,
  setupProcess,
  env,
  getMessageByAction
} from "./utils";

describe("Borrowing", () => {
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

  it("Rejects borrow if the user is already in the queue in the controller", async () => {
    const msg = createMessage({
      Action: "Borrow",
      Quantity: "1",
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
              value: msg.From
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
      Action: "Borrow",
      Quantity: "-104"
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
                "Invalid borrow quantity"
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

  it("Rejects borrow if there aren't enough tokens available", async () => {
    const msg = createMessage({
      Action: "Borrow",
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
                "Not enough tokens available to be lent"
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

  it("Rejects borrow if the quantity is above the allowed limit", async () => {
    // we need to setup a new process for this, because the value
    // limit should be lower than the tokens available
    const handle = await setupProcess(env);

    // deposit two times (to not trigger the allowed limit error on minting)
    for (let i = 0; i < 2; i++) {
      await handle(createMessage({
        Action: "Credit-Notice",
        "X-Action": "Mint",
        Owner: tags["Collateral-Id"],
        From: tags["Collateral-Id"],
        "From-Process": tags["Collateral-Id"],
        Quantity: tags["Value-Limit"],
        Recipient: env.Process.Id,
        Sender: testWallet
      }));
    }

    expect((await handle(createMessage({ Action: "Get-Reserves" }))).Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Available",
              value: (BigInt(tags["Value-Limit"]) * 2n).toString()
            })
          ])
        })
      ])
    );

    const msg = createMessage({
      Action: "Borrow",
      Quantity: (BigInt(tags["Value-Limit"]) + 1n).toString()
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

    // expect borrow quantity error
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

  it.todo("Rejects borrow if the oracle does not return a valid/up to date price");

  it.todo("Rejects borrow if it would damage the collateralization factor");

  it.todo("Rejects borrow if it wouldn't be collateralized");

  it.todo("Borrows the correct quantity");
});

describe("Interests", () => {
  it.todo("Returns the correct interest rate without any borrows");

  it.todo("Returns the correct interest rate with borrows");

  it.todo("Syncs interest for a user");
});

describe("Position", () => {
  it.todo("Returns 0 capacity for an address that hasn't minted yet");

  it.todo("Returns 0 borrow balance for an address that has no active loans");

  it.todo("Returns an empty position for an address that hasn't minted yet");

  it.todo("Returns no positions when there are none for an all-positions request");

  it.todo("Returns the correct non-zero borrow capacity");

  it.todo("Returns the correct non-zero borrow balance");

  it.todo("Returns the correct non-zero position");

  it.todo("Returns the correct global position");

  it.todo("Returns all positions correctly");
});

describe("Repaying", () => {
  it.todo("Does not handle invalid token quantities (refund)");

  it.todo("Refunds in case of an invalid target address");

  it.todo("Refunds in case there are no active loans for the target");

  it.todo("Fully repays the loan and removes it");

  it.todo("Partially repays the loan and does not remove it");

  it.todo("Repays the loan on behalf of someone else");
});
