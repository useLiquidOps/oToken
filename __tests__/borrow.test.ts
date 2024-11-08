import { expect } from "@jest/globals";
import {
  createMessage,
  generateArweaveAddress,
  HandleFunction,
  normalizeTags,
  setupProcess,
  env
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
  
  it("Does not handle invalid token quantities", async () => {
    const msg = createMessage({
      Action: "Borrow",
      Quantity: "-104"
    });
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

  it("Rejects borrow if there aren't enough tokens available", async () => {
    const msg = createMessage({
      Action: "Borrow",
      Quantity: (BigInt(testQty) + 1n).toString()
    });
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
