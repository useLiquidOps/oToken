import { expect } from "@jest/globals";
import {
  setupProcess,
  HandleFunction,
  env,
  createMessage,
  generateArweaveAddress,
  normalizeTags
} from "./utils"

describe("Loan liquidation", () => {
  let handle: HandleFunction;
  let controller: string;
  let friend: string;
  let tags: Record<string, string>;
  let liquidator: string;
  let target: string;
  let rewardMarket: string;

  beforeAll(async () => {
    handle = await setupProcess(env);
    controller = env.Process.Owner;
    friend = generateArweaveAddress();
    tags = normalizeTags(env.Process.Tags);
    liquidator = generateArweaveAddress();
    target = generateArweaveAddress();
    rewardMarket = generateArweaveAddress();
  });

  it("It does not handle invalid token quantities", async () => {
    const ref = "exampleref";
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
