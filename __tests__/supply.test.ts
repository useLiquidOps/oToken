import { expect } from "@jest/globals";
import {
  env,
  setupProcess,
  HandleFunction,
  generateArweaveAddress,
  createMessage,
  normalizeTags
} from "./utils";

describe("Minting and providing", () => {
  let handle: HandleFunction;
  let testWallet: string;
  let tags: Record<string, string>;

  const testQty = "1000000000000000";

  beforeAll(async () => {
    handle = await setupProcess(env);
    testWallet = generateArweaveAddress();
    tags = normalizeTags(env.Process.Tags);
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
              value: expect.any(String)
            })
          ])
        })
      ])
    );
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
              value: expect.any(String)
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

  it("Mints the correct quantity on not initial supply", async () => {

  });

  it.todo("Mints in proportion to the pooled tokens when there is an active borrow");
});

describe("Redeeming and burning", () => {
  let handle: HandleFunction;
  let testWallet: string;

  beforeAll(async () => {
    handle = await setupProcess(env);
    testWallet = generateArweaveAddress();
  });

  it.todo("Does not handle invalid token quantities");

  it.todo("Rejects redeeming more than the available balance");

  it.todo("Rejects redeeming when there aren't enough available tokens");

  it.todo("Rejects redeeming when there is no price data returned");

  it.todo("Rejects redeeming when the redeem value is too high compared to the free borrow capacity");

  it.todo("Redeems the correct quantity");
});

describe("Price and underlying asset value, reserves", () => {
  let handle: HandleFunction;
  let testWallet: string;

  beforeAll(async () => {
    handle = await setupProcess(env);
    testWallet = generateArweaveAddress();
  });

  it.todo("Reserves are empty on init");

  it.todo("Price is 1 when the reserves are empty");

  it.todo("Reserves return the correct quantities");

  it.todo("Price is the same as the input quantity on initial provide");

  it.todo("Returns the correct price after the oToken:collateral ratio is not 1:1");

  it.todo("Price input is 1 by default when there is no quantity provided");
});
