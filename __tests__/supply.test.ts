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

  const testWallet = generateArweaveAddress();
  const testQty = "1000000000000000";
  const tags = normalizeTags(env.Process.Tags);

  beforeAll(async () => {
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
});
