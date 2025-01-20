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

  beforeAll(async () => {
    handle = await setupProcess(env);
    controller = env.Process.Owner;
    tags = normalizeTags(env.Process.Tags);
    liquidator = generateArweaveAddress();
    target = generateArweaveAddress();
    rewardMarket = generateArweaveAddress();

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
    const res = await handle(createMessage({
      Owner: tags["Collateral-Id"],
      From: tags["Collateral-Id"],
      "From-Process": tags["Collateral-Id"],
      Action: "Credit-Notice",
      Sender: controller,
      Quantity: "10",
      "X-Action": "Liquidate-Borrow",
      "X-Liquidator": liquidator,
      "X-Liquidation-Target": generateArweaveAddress(),
      "X-Reward-Market": rewardMarket,
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
        })
      ])
    );
  });

  it("Rejects liquidation with a higher quantity than the loan", async () => {

  });

  it("Rejects liquidation if the position liquidation fails", async () => {

  });

  it("Liquidates the loan", async () => {

  });
});

describe("Position liquidation", () => {

});
