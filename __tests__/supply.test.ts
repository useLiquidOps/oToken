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

  it("Does not handle invalid token quantities", async () => {
    const msg = createMessage({
      Action: "Redeem",
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
              value: expect.any(String)
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

  it.todo("Rejects redeeming when there aren't enough available tokens");

  it.todo("Rejects redeeming when there is no price data returned");

  it.todo("Rejects redeeming when the redeem value is too high compared to the free borrow capacity");

  it.todo("Redeems the correct quantity");

  it.todo("Redeems the correct quantity after interests");
});

describe("Price and underlying asset value, reserves (empty)", () => {
  let handle: HandleFunction;

  const testQty = "4";

  beforeAll(async () => {
    handle = await setupProcess(env);
  });

  it("Reserves are empty on init", async () => {
    const msg = createMessage({ Action: "Get-Reserves" });
    const res = await handle(msg);

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: msg.From,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Available",
              value: "0"
            }),
            expect.objectContaining({
              name: "Lent",
              value: "0"
            })
          ])
        })
      ])
    );
  });

  it("Price does not allow invalid quantities", async () => {
    const msg = createMessage({
      Action: "Get-Price",
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
              value: expect.any(String)
            })
          ])
        })
      ])
    );
  });

  it("Price is 1 when the reserves are empty", async () => {
    const msg = createMessage({
      Action: "Get-Price",
      Quantity: testQty
    });
    const res = await handle(msg);

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: msg.From,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Price",
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

describe("Price and underlying asset value, reserves after initial provide", () => {
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

  it("Reserves return the correct quantities", async () => {
    const msg = createMessage({ Action: "Get-Reserves" });
    const res = await handle(msg);

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: msg.From,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Available",
              value: testQty
            }),
            expect.objectContaining({
              name: "Lent",
              value: "0"
            })
          ])
        })
      ])
    );
  });

  it.todo("Reserves return the correct quantities when there is an active borrow");

  it.todo("Returns the correct price after the oToken:collateral ratio is not 1:1");

  it.todo("Price input quantity is 1 by default when there is no quantity provided");
});
