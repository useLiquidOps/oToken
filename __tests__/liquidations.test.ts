import { expect } from "@jest/globals";
import {
  setupProcess,
  HandleFunction,
  env,
  createMessage,
  generateArweaveAddress,
  normalizeTags,
  getMessageByAction,
  generateOracleResponse
} from "./utils"

describe("Loan liquidation", () => {
  const ref = "exampleref";
  let handle: HandleFunction;
  let controller: string;
  let tags: Record<string, string>;
  let liquidator: string;
  let target: string;
  let rewardMarket: string;
  const loanQty = 100n;
  const rewardQty = 1000n;

  beforeAll(() => {
    controller = env.Process.Owner;
    tags = normalizeTags(env.Process.Tags);
    liquidator = generateArweaveAddress();
    target = generateArweaveAddress();
    rewardMarket = generateArweaveAddress();
  });

  beforeEach(async () => {
    handle = await setupProcess(env);

    // make a borrow
    const mintRes = await handle(createMessage({
      Action: "Credit-Notice",
      "X-Action": "Mint",
      Owner: tags["Collateral-Id"],
      From: tags["Collateral-Id"],
      "From-Process": tags["Collateral-Id"],
      Quantity: (loanQty * 2n).toString(),
      Recipient: env.Process.Id,
      Sender: target
    }));
    await handle(createMessage({
      "Queued-User": target,
      "X-Reference": normalizeTags(
        getMessageByAction("Add-To-Queue", mintRes.Messages)?.Tags || []
      )["Reference"]
    }));
    const queueRes = await handle(createMessage({
      Owner: target,
      From: target,
      "From-Process": target,
      Action: "Borrow",
      Quantity: loanQty.toString()
    }));
    const oracleRes = await handle(createMessage({
      "Queued-User": target,
      "X-Reference": normalizeTags(
        getMessageByAction("Add-To-Queue", queueRes.Messages)?.Tags || []
      )["Reference"]
    }));
    const oracleInputRes = await handle(
      generateOracleResponse({ AR: 1 }, oracleRes)
    );
    await handle(createMessage({
      Owner: controller,
      From: controller,
      "From-Process": target,
      "X-Reference": normalizeTags(
        getMessageByAction("Remove-From-Queue", oracleInputRes.Messages)?.Tags || []
      )["Reference"],
      "Unqueued-User": target
    }));
  });

  it("Only handles loan liquidation from the controller", async () => {
    const otherAddr = generateArweaveAddress();
    const res = await handle(createMessage({
      Owner: tags["Collateral-Id"],
      From: tags["Collateral-Id"],
      "From-Process": tags["Collateral-Id"],
      Action: "Credit-Notice",
      Sender: otherAddr,
      Quantity: loanQty.toString(),
      "X-Action": "Liquidate-Borrow",
      "X-Liquidator": liquidator,
      "X-Liquidation-Target": target,
      "X-Reward-Market": rewardMarket,
      "X-Reward-Quantity": rewardQty.toString(),
      "X-Liquidation-Reference": ref
    }));

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: tags["Collateral-Id"],
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: "The request could not be handled"
            })
          ])
        })
      ])
    );
  });

  it("It does not handle invalid token quantities", async () => {
    const res = await handle(createMessage({
      Owner: tags["Collateral-Id"],
      From: tags["Collateral-Id"],
      "From-Process": tags["Collateral-Id"],
      Action: "Credit-Notice",
      Sender: controller,
      Quantity: "-1",
      "X-Action": "Liquidate-Borrow",
      "X-Liquidator": liquidator,
      "X-Liquidation-Target": target,
      "X-Reward-Market": rewardMarket,
      "X-Reward-Quantity": rewardQty.toString(),
      "X-Liquidation-Reference": ref
    }));

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Liquidate-Borrow-Error"
            }),
            expect.objectContaining({
              name: "Liquidation-Reference",
              value: ref
            }),
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Invalid incoming transfer quantity"
              )
            })
          ])
        })
      ])
    );
  });

  it("Rejects liquidation for a user that does not have an active loan", async () => {
    const qty = "10";
    const res = await handle(createMessage({
      Owner: tags["Collateral-Id"],
      From: tags["Collateral-Id"],
      "From-Process": tags["Collateral-Id"],
      Action: "Credit-Notice",
      Sender: controller,
      Quantity: qty,
      "X-Action": "Liquidate-Borrow",
      "X-Liquidator": liquidator,
      "X-Liquidation-Target": generateArweaveAddress(),
      "X-Reward-Market": rewardMarket,
      "X-Reward-Quantity": rewardQty.toString(),
      "X-Liquidation-Reference": ref
    }));

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Liquidate-Borrow-Error"
            }),
            expect.objectContaining({
              name: "Liquidation-Reference",
              value: ref
            }),
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Cannot liquidate a loan for this user"
              )
            })
          ])
        }),
        expect.objectContaining({
          Target: tags["Collateral-Id"],
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Transfer"
            }),
            expect.objectContaining({
              name: "Quantity",
              value: qty
            }),
            expect.objectContaining({
              name: "Recipient",
              value: liquidator
            })
          ])
        })
      ])
    );
  });

  it("Rejects liquidation with a higher quantity than the loan", async () => {
    const higherQty = loanQty + 1n;
    const res = await handle(createMessage({
      Owner: tags["Collateral-Id"],
      From: tags["Collateral-Id"],
      "From-Process": tags["Collateral-Id"],
      Action: "Credit-Notice",
      Sender: controller,
      Quantity: higherQty.toString(),
      "X-Action": "Liquidate-Borrow",
      "X-Liquidator": liquidator,
      "X-Liquidation-Target": target,
      "X-Reward-Market": rewardMarket,
      "X-Reward-Quantity": rewardQty.toString(),
      "X-Liquidation-Reference": ref
    }));

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Liquidate-Borrow-Error"
            }),
            expect.objectContaining({
              name: "Liquidation-Reference",
              value: ref
            }),
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "The user has less tokens loaned than repaid"
              )
            })
          ])
        }),
        expect.objectContaining({
          Target: tags["Collateral-Id"],
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Transfer"
            }),
            expect.objectContaining({
              name: "Quantity",
              value: higherQty.toString()
            }),
            expect.objectContaining({
              name: "Recipient",
              value: liquidator
            })
          ])
        })
      ])
    );
  });

  it("Rejects liquidation if the position liquidation fails", async () => {
    const liquidateReq = await handle(createMessage({
      Owner: tags["Collateral-Id"],
      From: tags["Collateral-Id"],
      "From-Process": tags["Collateral-Id"],
      Action: "Credit-Notice",
      Sender: controller,
      Quantity: loanQty.toString(),
      "X-Action": "Liquidate-Borrow",
      "X-Liquidator": liquidator,
      "X-Liquidation-Target": target,
      "X-Reward-Market": rewardMarket,
      "X-Reward-Quantity": rewardQty.toString(),
      "X-Liquidation-Reference": ref
    }));

    expect(liquidateReq.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: rewardMarket,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Liquidate-Position"
            }),
            expect.objectContaining({
              name: "Quantity",
              value: rewardQty.toString()
            }),
            expect.objectContaining({
              name: "Liquidator",
              value: liquidator
            }),
            expect.objectContaining({
              name: "Liquidation-Target",
              value: target
            })
          ])
        })
      ])
    );

    const errorMsg = "Some error"
    const res = await handle(createMessage({
      Owner: rewardMarket,
      From: rewardMarket,
      "From-Process": rewardMarket,
      Action: "Liquidate-Position-Error",
      Error: errorMsg,
      "X-Reference": normalizeTags(
        getMessageByAction("Liquidate-Position", liquidateReq.Messages)?.Tags || []
      )["Reference"]
    }));

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Liquidate-Borrow-Error"
            }),
            expect.objectContaining({
              name: "Liquidation-Reference",
              value: ref
            }),
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(errorMsg)
            })
          ])
        }),
        expect.objectContaining({
          Target: tags["Collateral-Id"],
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Transfer"
            }),
            expect.objectContaining({
              name: "Quantity",
              value: loanQty.toString()
            }),
            expect.objectContaining({
              name: "Recipient",
              value: liquidator
            })
          ])
        })
      ])
    );
  });

  it("Partially liquidates the loan", async () => {
    const halfQty = loanQty / 2n;
    const liquidateReq = await handle(createMessage({
      Owner: tags["Collateral-Id"],
      From: tags["Collateral-Id"],
      "From-Process": tags["Collateral-Id"],
      Action: "Credit-Notice",
      Sender: controller,
      Quantity: halfQty.toString(),
      "X-Action": "Liquidate-Borrow",
      "X-Liquidator": liquidator,
      "X-Liquidation-Target": target,
      "X-Reward-Market": rewardMarket,
      "X-Reward-Quantity": rewardQty.toString(),
      "X-Liquidation-Reference": ref
    }));

    expect(liquidateReq.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: rewardMarket,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Liquidate-Position"
            }),
            expect.objectContaining({
              name: "Quantity",
              value: rewardQty.toString()
            }),
            expect.objectContaining({
              name: "Liquidator",
              value: liquidator
            }),
            expect.objectContaining({
              name: "Liquidation-Target",
              value: target
            })
          ])
        })
      ])
    );

    const res = await handle(createMessage({
      Owner: rewardMarket,
      From: rewardMarket,
      "From-Process": rewardMarket,
      Action: "Liquidate-Position-Confirmation",
      "Liquidated-Position-Quantity": "1000", // this value does not matter here
      "X-Reference": normalizeTags(
        getMessageByAction("Liquidate-Position", liquidateReq.Messages)?.Tags || []
      )["Reference"]
    }));

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Liquidate-Borrow-Confirmation"
            }),
            expect.objectContaining({
              name: "Liquidated-Quantity",
              value: halfQty.toString()
            }),
            expect.objectContaining({
              name: "Liquidator",
              value: liquidator
            }),
            expect.objectContaining({
              name: "Liquidation-Target",
              value: target
            }),
            expect.objectContaining({
              name: "Liquidation-Reference",
              value: ref
            })
          ])
        })
      ])
    );

    // make sure that the other half of the loan is still there (active)
    const positionRes = await handle(createMessage({
      Action: "Position",
      Recipient: target
    }));

    expect(positionRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Borrow-Balance",
              value: halfQty.toString()
            })
          ])
        })
      ])
    );
  });

  it("Liquidates the full loan", async () => {
    const liquidateReq = await handle(createMessage({
      Owner: tags["Collateral-Id"],
      From: tags["Collateral-Id"],
      "From-Process": tags["Collateral-Id"],
      Action: "Credit-Notice",
      Sender: controller,
      Quantity: loanQty.toString(),
      "X-Action": "Liquidate-Borrow",
      "X-Liquidator": liquidator,
      "X-Liquidation-Target": target,
      "X-Reward-Market": rewardMarket,
      "X-Reward-Quantity": rewardQty.toString(),
      "X-Liquidation-Reference": ref
    }));

    expect(liquidateReq.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: rewardMarket,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Liquidate-Position"
            }),
            expect.objectContaining({
              name: "Quantity",
              value: rewardQty.toString()
            }),
            expect.objectContaining({
              name: "Liquidator",
              value: liquidator
            }),
            expect.objectContaining({
              name: "Liquidation-Target",
              value: target
            })
          ])
        })
      ])
    );

    const res = await handle(createMessage({
      Owner: rewardMarket,
      From: rewardMarket,
      "From-Process": rewardMarket,
      Action: "Liquidate-Position-Confirmation",
      "Liquidated-Position-Quantity": "1000", // this value does not matter here
      "X-Reference": normalizeTags(
        getMessageByAction("Liquidate-Position", liquidateReq.Messages)?.Tags || []
      )["Reference"]
    }));

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Liquidate-Borrow-Confirmation"
            }),
            expect.objectContaining({
              name: "Liquidated-Quantity",
              value: loanQty.toString()
            }),
            expect.objectContaining({
              name: "Liquidator",
              value: liquidator
            }),
            expect.objectContaining({
              name: "Liquidation-Target",
              value: target
            }),
            expect.objectContaining({
              name: "Liquidation-Reference",
              value: ref
            })
          ])
        })
      ])
    );
  });
});

describe("Position liquidation", () => {
  let handle: HandleFunction;
  let tags: Record<string, string>;
  let liquidator: string;
  let target: string;
  let friend: {
    id: string;
    oToken: string;
    ticker: string;
    denomination: string;
  };
  const positionQty = 2000n;

  beforeAll(() => {
    tags = normalizeTags(env.Process.Tags);
    liquidator = generateArweaveAddress();
    target = generateArweaveAddress();
    friend = {
      id: generateArweaveAddress(),
      oToken: generateArweaveAddress(),
      ticker: "TST",
      denomination: "12"
    };
  });

  beforeEach(async () => {
    const envWithFriend = {
      Process: {
        ...env.Process,
        Tags: env.Process.Tags.map((t) => {
          if (t.name !== "Friends") return t;
          return { name: t.name, value: JSON.stringify([friend]) }
        })
      }
    };
    handle = await setupProcess(envWithFriend);

    // make borrows
    const mintRes = await handle(createMessage({
      Action: "Credit-Notice",
      "X-Action": "Mint",
      Owner: tags["Collateral-Id"],
      From: tags["Collateral-Id"],
      "From-Process": tags["Collateral-Id"],
      Quantity: positionQty.toString(),
      Recipient: env.Process.Id,
      Sender: target
    }));
    await handle(createMessage({
      "Queued-User": target,
      "X-Reference": normalizeTags(
        getMessageByAction("Add-To-Queue", mintRes.Messages)?.Tags || []
      )["Reference"]
    }));

    const otherLender = generateArweaveAddress();
    const otherMintRes = await handle(createMessage({
      Action: "Credit-Notice",
      "X-Action": "Mint",
      Owner: tags["Collateral-Id"],
      From: tags["Collateral-Id"],
      "From-Process": tags["Collateral-Id"],
      Quantity: positionQty.toString(),
      Recipient: env.Process.Id,
      Sender: otherLender
    }))
    await handle(createMessage({
      "Queued-User": otherLender,
      "X-Reference": normalizeTags(
        getMessageByAction("Add-To-Queue", otherMintRes.Messages)?.Tags || []
      )["Reference"]
    }));
  });

  it("Only handles position liquidation from a friend process", async () => {
    const foreignProcess = generateArweaveAddress();
    const res = await handle(createMessage({
      Owner: foreignProcess,
      From: foreignProcess,
      "From-Process": foreignProcess,
      Action: "Liquidate-Position",
      Quantity: positionQty.toString(),
      Liquidator: liquidator,
      ["Liquidation-Target"]: target
    }));

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: foreignProcess,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Only a friend process is authorized to call this function"
              )
            })
          ])
        })
      ])
    );
  });

  it("Does not handle invalid quantities", async () => {
    const res = await handle(createMessage({
      Owner: friend.oToken,
      From: friend.oToken,
      "From-Process": friend.oToken,
      Action: "Liquidate-Position",
      Quantity: "-1",
      Liquidator: liquidator,
      ["Liquidation-Target"]: target
    }));

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: friend.oToken,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Invalid quantity"
              )
            })
          ])
        })
      ])
    );
  });

  it("Rejects an invalid address for the liquidator", async () => {
    const res = await handle(createMessage({
      Owner: friend.oToken,
      From: friend.oToken,
      "From-Process": friend.oToken,
      Action: "Liquidate-Position",
      Quantity: positionQty.toString(),
      Liquidator: "invalid",
      ["Liquidation-Target"]: target
    }));

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: friend.oToken,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Invalid liquidator address"
              )
            })
          ])
        })
      ])
    );
  });

  it("Rejects a liquidation if the user has no collateral", async () => {
    const res = await handle(createMessage({
      Owner: friend.oToken,
      From: friend.oToken,
      "From-Process": friend.oToken,
      Action: "Liquidate-Position",
      Quantity: "1",
      Liquidator: liquidator,
      ["Liquidation-Target"]: "NWVJeVHA30A08sd9XgyVJaVCQAyQ9SYtu09Jg3JcweX"
    }));

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: friend.oToken,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "The liquidation target does not have collateral in this token"
              )
            })
          ])
        })
      ])
    );
  });

  it("Rejects a liquidation without checking the user position, if the liquidation quantity is higher than the total available tokens", async () => {
    const res = await handle(createMessage({
      Owner: friend.oToken,
      From: friend.oToken,
      "From-Process": friend.oToken,
      Action: "Liquidate-Position",
      Quantity: (positionQty * 2n + 1n).toString(),
      Liquidator: liquidator,
      ["Liquidation-Target"]: target
    }));

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: friend.oToken,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Not enough tokens available to liquidate"
              )
            })
          ])
        })
      ])
    );
  });

  it("Rejects a liquidation if the user does not have the expected collateral", async () => {
    const res = await handle(createMessage({
      Owner: friend.oToken,
      From: friend.oToken,
      "From-Process": friend.oToken,
      Action: "Liquidate-Position",
      Quantity: (positionQty + 1n).toString(),
      Liquidator: liquidator,
      ["Liquidation-Target"]: target
    }));

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: friend.oToken,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "The liquidation target owns less oTokens than the supplied quantity's worth"
              )
            })
          ])
        })
      ])
    );
  });

  it("Partially liquidates a position", async () => {
    const qty = positionQty / 2n;
    const res = await handle(createMessage({
      Owner: friend.oToken,
      From: friend.oToken,
      "From-Process": friend.oToken,
      Action: "Liquidate-Position",
      Quantity: qty.toString(),
      Liquidator: liquidator,
      ["Liquidation-Target"]: target
    }));

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: friend.oToken,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Liquidate-Position-Confirmation"
            }),
            expect.objectContaining({
              name: "Liquidated-Position-Quantity",
              // the oToken value should be the same, since
              // no borrows have occured yet
              value: qty.toString()
            })
          ])
        })
      ])
    );
  });

  it("Fully liquidates a position", async () => {
    const res = await handle(createMessage({
      Owner: friend.oToken,
      From: friend.oToken,
      "From-Process": friend.oToken,
      Action: "Liquidate-Position",
      Quantity: positionQty.toString(),
      Liquidator: liquidator,
      ["Liquidation-Target"]: target
    }));

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: friend.oToken,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Liquidate-Position-Confirmation"
            }),
            expect.objectContaining({
              name: "Liquidated-Position-Quantity",
              // the oToken value should be the same, since
              // no borrows have occured yet
              value: positionQty.toString()
            })
          ])
        })
      ])
    );
  });
});
