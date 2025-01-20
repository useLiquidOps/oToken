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
    await handle(createMessage({
      Action: "Credit-Notice",
      "X-Action": "Mint",
      Owner: tags["Collateral-Id"],
      From: tags["Collateral-Id"],
      "From-Process": tags["Collateral-Id"],
      Quantity: (loanQty * 2n).toString(),
      Recipient: env.Process.Id,
      Sender: target
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
              name: "Used-Capacity",
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

});
