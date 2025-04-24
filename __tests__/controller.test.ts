import { expect } from "@jest/globals";
import {
  setupProcess,
  HandleFunction,
  env,
  createMessage,
  generateArweaveAddress,
  normalizeTags,
  getMessageByAction,
  generateOracleResponse,
  defaultTimestamp
} from "./utils"

describe("Friend tests", () => {
  let handle: HandleFunction;
  let controller: string;
  let friend: {
    collateral: string;
    oToken: string;
    ticker: string;
    denomination: string;
  };
  let tags: Record<string, string>;

  beforeAll(async () => {
    tags = normalizeTags(env.Process.Tags);
    handle = await setupProcess(env);
    controller = env.Process.Owner;
    friend = {
      collateral: generateArweaveAddress(),
      oToken: generateArweaveAddress(),
      ticker: "TST",
      denomination: "12"
    };
  });

  it("Does not allow friend interaction from anyone other than the controller", async () => {
    const invalidOwner = generateArweaveAddress();

    // expect error when trying to add a friend not from the controller
    const friendAddRes = await handle(createMessage({
      Action: "Add-Friend",
      Friend: friend.oToken,
      Token: friend.collateral,
      Ticker: friend.ticker,
      Denomination: friend.denomination,
      Owner: invalidOwner,
      From: invalidOwner
    }));

    expect(friendAddRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: invalidOwner,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "The request could not be handled"
              )
            })
          ])
        })
      ])
    );

    // expect error when trying to remove a friend not from the controller
    const friendRemoveRes = await handle(createMessage({
      Action: "Remove-Friend",
      Friend: generateArweaveAddress(),
      Owner: invalidOwner,
      From: invalidOwner
    }));

    expect(friendRemoveRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: invalidOwner,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "The request could not be handled"
              )
            })
          ])
        })
      ])
    );
  });

  it("Does not add a friend with an invalid oToken address", async () => {
    const friendAddRes = await handle(createMessage({
      Action: "Add-Friend",
      Friend: "invalid",
      Token: friend.collateral,
      Ticker: friend.ticker,
      Denomination: friend.denomination,
    }));

    expect(friendAddRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Invalid friend address"
              )
            })
          ])
        })
      ])
    );
  });

  it("Does not add a friend with an invalid collateral address", async () => {
    const friendAddRes = await handle(createMessage({
      Action: "Add-Friend",
      Friend: friend.oToken,
      Token: "abc",
      Ticker: friend.ticker,
      Denomination: friend.denomination,
    }));

    expect(friendAddRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Invalid token address"
              )
            })
          ])
        })
      ])
    );
  });

  it("Does not add a friend without a collateral ticker", async () => {
    const friendAddRes = await handle(createMessage({
      Action: "Add-Friend",
      Friend: friend.oToken,
      Token: friend.collateral,
      Denomination: friend.denomination,
    }));

    expect(friendAddRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "No ticker supplied for friend collateral"
              )
            })
          ])
        })
      ])
    );
  });

  it("Does not add itself as a friend", async () => {
    const sameFriend = await handle(createMessage({
      Action: "Add-Friend",
      Friend: env.Process.Id,
      Token: friend.collateral,
      Denomination: friend.denomination,
      Ticker: friend.ticker
    }));

    expect(sameFriend.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Cannot add itself as a friend"
              )
            })
          ])
        })
      ])
    );

    const sameToken = await handle(createMessage({
      Action: "Add-Friend",
      Friend: friend.oToken,
      Token: tags["Collateral-Id"],
      Denomination: friend.denomination,
      Ticker: friend.ticker
    }));

    expect(sameToken.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Cannot add itself as a friend"
              )
            })
          ])
        })
      ])
    );

    const sameTicker = await handle(createMessage({
      Action: "Add-Friend",
      Friend: friend.oToken,
      Token: friend.collateral,
      Denomination: friend.denomination,
      Ticker: tags["Collateral-Ticker"]
    }));

    expect(sameTicker.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Cannot add itself as a friend"
              )
            })
          ])
        })
      ])
    );
  });

  it("Adds a new friend", async () => {
    const friendAddRes = await handle(createMessage({
      Action: "Add-Friend",
      Friend: friend.oToken,
      Token: friend.collateral,
      Denomination: friend.denomination,
      Ticker: friend.ticker
    }));

    expect(friendAddRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Friend-Added"
            }),
            expect.objectContaining({
              name: "Friend",
              value: friend.oToken
            })
          ])
        })
      ])
    );
  });

  it("Does not add a friend that is already added", async () => {
    const friendAddRes = await handle(createMessage({
      Action: "Add-Friend",
      Friend: friend.oToken,
      Token: friend.collateral,
      Denomination: friend.denomination,
      Ticker: friend.ticker
    }));

    expect(friendAddRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Friend already added"
              )
            })
          ])
        })
      ])
    );
  });

  it("Lists friends correctly", async () => {
    const friendsListRes = await handle(createMessage({
      Action: "List-Friends"
    }));

    expect(friendsListRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Friend-List"
            })
          ]),
          Data: expect.toBeJsonEncoded(
            expect.arrayContaining([
              expect.objectContaining({
                id: friend.collateral,
                ticker: friend.ticker,
                oToken: friend.oToken,
                denomination: parseInt(friend.denomination)
              })
            ])
          )
        })
      ])
    );
  });

  it("Errors on trying to remove an address from friends, that is not a friend", async () => {
    const toRemove = generateArweaveAddress();
    const friendRemoveRes = await handle(createMessage({
      Action: "Remove-Friend",
      Friend: toRemove
    }));

    expect(friendRemoveRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Friend " + toRemove + " not yet added"
              )
            })
          ])
        })
      ])
    );
  });

  it("Removes friend", async () => {
    const friendRemoveRes = await handle(createMessage({
      Action: "Remove-Friend",
      Friend: friend.oToken
    }));

    expect(friendRemoveRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Friend-Removed"
            }),
            expect.objectContaining({
              name: "Removed",
              value: friend.oToken
            })
          ]),
          Data: expect.toBeJsonEncoded(
            expect.arrayContaining([
              expect.objectContaining({
                id: friend.collateral,
                ticker: friend.ticker,
                oToken: friend.oToken,
                denomination: parseInt(friend.denomination)
              })
            ])
          )
        })
      ])
    );
  });

  it("Lists empty friends list correctly", async () => {
    const friendsListRes = await handle(createMessage({
      Action: "List-Friends"
    }));

    expect(friendsListRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Friend-List"
            })
          ]),
          Data: "[]"
        })
      ])
    );
  });
});

describe("Config tests", () => {
  let handle: HandleFunction;
  let controller: string;
  let newOracle: string;

  beforeAll(async () => {
    handle = await setupProcess(env);
    controller = env.Process.Owner;
    newOracle = generateArweaveAddress();
  });

  it("Does not allow config interaction from anyone other than the controller", async () => {
    const invalidOwner = generateArweaveAddress();

    // expect error when trying to set the collateral factor not from the controller
    const collateralRatioRes = await handle(createMessage({
      Action: "Update-Config",
      ["Collateral-Factor"]: "80",
      Oracle: generateArweaveAddress(),
      Owner: invalidOwner,
      From: invalidOwner
    }));

    expect(collateralRatioRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: invalidOwner,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "The request could not be handled"
              )
            })
          ])
        })
      ])
    );
  });

  it("Does not update oracle with an invalid address", async () => {
    const res = await handle(createMessage({
      Action: "Update-Config",
      Oracle: "invalid"
    }));

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Invalid oracle ID"
              )
            })
          ])
        })
      ])
    );
  });

  it("Updates the oracle", async () => {
    const res = await handle(createMessage({
      Action: "Update-Config",
      Oracle: newOracle
    }));

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Oracle",
              value: newOracle
            })
          ])
        })
      ])
    );

    // expect updated info
    const infoRes = await handle(createMessage({ Action: "Info" }));

    expect(infoRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Oracle",
              value: newOracle
            })
          ])
        })
      ])
    );
  });

  it("Does not update collateral factor with an invalid value", async () => {
    expect((await handle(createMessage({
      Action: "Update-Config",
      "Collateral-Factor": "invalid"
    }))).Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Collateral-Factor",
              value: expect.not.stringContaining("invalid")
            })
          ])
        })
      ])
    );

    expect((await handle(createMessage({
      Action: "Update-Config",
      "Collateral-Factor": "1.2"
    }))).Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Invalid collateral factor"
              )
            })
          ])
        })
      ])
    );
    expect((await handle(createMessage({
      Action: "Update-Config",
      "Collateral-Factor": "-1"
    }))).Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Invalid collateral factor"
              )
            })
          ])
        })
      ])
    );
    expect((await handle(createMessage({
      Action: "Update-Config",
      "Collateral-Factor": "101"
    }))).Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Invalid collateral factor"
              )
            })
          ])
        })
      ])
    );
  });

  it("Updates the collateral factor", async () => {
    const newFactor = "28";
    const res = await handle(createMessage({
      Action: "Update-Config",
      "Collateral-Factor": newFactor
    }));

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Collateral-Factor",
              value: newFactor
            })
          ])
        })
      ])
    );

    // expect updated info
    const infoRes = await handle(createMessage({ Action: "Info" }));

    expect(infoRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Collateral-Factor",
              value: newFactor
            })
          ])
        })
      ])
    );
  });

  it("Does not update liquidation threshold with an invalid value", async () => {
    expect((await handle(createMessage({
      Action: "Update-Config",
      "Liquidation-Threshold": "invalid"
    }))).Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Liquidation-Threshold",
              value: expect.not.stringContaining("invalid")
            })
          ])
        })
      ])
    );

    expect((await handle(createMessage({
      Action: "Update-Config",
      "Liquidation-Threshold": "34.9"
    }))).Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Invalid liquidation threshold"
              )
            })
          ])
        })
      ])
    );
    expect((await handle(createMessage({
      Action: "Update-Config",
      "Liquidation-Threshold": "-9"
    }))).Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Invalid liquidation threshold"
              )
            })
          ])
        })
      ])
    );
    expect((await handle(createMessage({
      Action: "Update-Config",
      "Liquidation-Threshold": "124"
    }))).Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Invalid liquidation threshold"
              )
            })
          ])
        })
      ])
    );
  });

  it("Updates the liquidation threshold", async () => {
    const newFactor = "75";
    const res = await handle(createMessage({
      Action: "Update-Config",
      "Liquidation-Threshold": newFactor
    }));

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Liquidation-Threshold",
              value: newFactor
            })
          ])
        })
      ])
    );

    // expect updated info
    const infoRes = await handle(createMessage({ Action: "Info" }));

    expect(infoRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Liquidation-Threshold",
              value: newFactor
            })
          ])
        })
      ])
    );
  });

  it("Does not update the value limit with an invalid value", async () => {
    const invalidVal = "invalid";
    const invalidQtyRes = await handle(createMessage({
      Action: "Update-Config",
      "Value-Limit": invalidVal
    }));

    expect(invalidQtyRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Invalid value limit"
              )
            })
          ])
        })
      ])
    );

    const zeroQtyRes = await handle(createMessage({
      Action: "Update-Config",
      "Value-Limit": "0"
    }));

    expect(zeroQtyRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Invalid value limit"
              )
            })
          ])
        })
      ])
    );
  });

  it("Updates the value limit", async () => {
    const newValueLimit = "457385";
    const res = await handle(createMessage({
      Action: "Update-Config",
      "Value-Limit": newValueLimit
    }));

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Value-Limit",
              value: newValueLimit
            })
          ])
        })
      ])
    );

    // expect updated info
    const infoRes = await handle(createMessage({ Action: "Info" }));

    expect(infoRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Value-Limit",
              value: newValueLimit
            })
          ])
        })
      ])
    );
  });

  it("Does not update the oracle delay tolerance with an invalid value", async () => {
    const invalidValueRes = await handle(createMessage({
      Action: "Update-Config",
      "Oracle-Delay-Tolerance": "invalid"
    }));

    expect(invalidValueRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Oracle-Delay-Tolerance",
              value: expect.not.stringContaining("invalid")
            })
          ])
        })
      ])
    );

    const nonZeroRes = await handle(createMessage({
      Action: "Update-Config",
      "Oracle-Delay-Tolerance": "-1"
    }));

    expect(nonZeroRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Oracle delay tolerance has to be >= 0"
              )
            })
          ])
        })
      ])
    );

    const nonIntegerTest = await handle(createMessage({
      Action: "Update-Config",
      "Oracle-Delay-Tolerance": "1.2"
    }));

    expect(nonIntegerTest.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Oracle delay tolerance has to be a whole number"
              )
            })
          ])
        })
      ])
    );
  });

  it("Updates the oracle delay tolerance", async () => {
    const newDelayTolerance = "435875"
    const res = await handle(createMessage({
      Action: "Update-Config",
      "Oracle-Delay-Tolerance": newDelayTolerance
    }));

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Oracle-Delay-Tolerance",
              value: newDelayTolerance
            })
          ])
        })
      ])
    );

    // expect updated info
    const infoRes = await handle(createMessage({ Action: "Info" }));

    expect(infoRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Oracle-Delay-Tolerance",
              value: newDelayTolerance
            })
          ])
        })
      ])
    );
  });
});

describe("Cooldown tests", () => {
  let handle: HandleFunction;
  let tags: Record<string, string>;
  let testWallet: string;
  let block = 10;

  // test cooldown in blocks
  const cooldown = 5;
  const testQty = "168";

  beforeAll(async () => {
    const envWithCooldown = env;

    // update cooldown
    const cd = envWithCooldown.Process.Tags.find(
      (tag) => tag.name === "Cooldown-Period"
    );
    if (cd) cd.value = cooldown.toString();

    handle = await setupProcess(envWithCooldown);
    tags = normalizeTags(env.Process.Tags);
    testWallet = generateArweaveAddress();
  });

  afterEach(() => block += cooldown + 1);

  it.skip("Rejects interaction while cooldown is not over", async () => {
    // send initial mint, expect it to succeed
    const initialBlock = block;
    const initialMint = await handle(createMessage({
      Action: "Credit-Notice",
      "X-Action": "Mint",
      Owner: tags["Collateral-Id"],
      From: tags["Collateral-Id"],
      "From-Process": tags["Collateral-Id"],
      Quantity: testQty,
      Recipient: env.Process.Id,
      Sender: testWallet,
      // @ts-expect-error
      ["Block-Height"]: initialBlock
    }));

    expect(initialMint.Messages).toEqual(
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

    // this should fail, because the cooldown is 5 blocks
    const nextBlock = ++block;
    const withinCooldownRedeem = await handle(createMessage({
      Action: "Redeem",
      Owner: testWallet,
      From: testWallet,
      Quantity: testQty,
      // @ts-expect-error
      ["Block-Height"]: nextBlock
    }));

    expect(withinCooldownRedeem.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: testWallet,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Redeem-Error"
            }),
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Sender is on cooldown for " + (initialBlock + cooldown - nextBlock) + " more block(s)"
              )
            })
          ])
        })
      ])
    );
  });

  it.skip("Allows interaction when cooldown is over", async () => {
    // send initial mint, expect it to succeed
    const initialMint = await handle(createMessage({
      Action: "Credit-Notice",
      "X-Action": "Mint",
      Owner: tags["Collateral-Id"],
      From: tags["Collateral-Id"],
      "From-Process": tags["Collateral-Id"],
      Quantity: testQty,
      Recipient: env.Process.Id,
      Sender: testWallet,
      // @ts-expect-error
      ["Block-Height"]: block
    }));

    expect(initialMint.Messages).toEqual(
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

    block += cooldown;

    const afterCooldownRedeem = await handle(createMessage({
      Action: "Redeem",
      Owner: testWallet,
      From: testWallet,
      Quantity: testQty,
      // @ts-expect-error
      ["Block-Height"]: block
    }));

    // expect a request to queue in the controller
    // (the request would already fail before the queue
    // message, if it was within the cooldown period)
    expect(afterCooldownRedeem.Messages).toEqual(
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
      getMessageByAction("Add-To-Queue", afterCooldownRedeem.Messages)?.Tags || []
    );

    // queue response
    const res = await handle(createMessage({
      Error: "Could not queue user",
      "X-Reference": queueResTags["Reference"]
    }));

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          //Target: testWallet,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: "The sender is already queued for an operation"
            })
          ])
        })
      ])
    );
  });

  it("Returns empty cooldown list initially", async () => {
    const msg = createMessage({
      Action: "Cooldowns",
      // @ts-expect-error
      ["Block-Height"]: block
    });
    const res = await handle(msg);

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: msg.From,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Cooldown-Period",
              value: cooldown.toString()
            }),
            expect.objectContaining({
              name: "Request-Block-Height",
              value: expect.toBeIntegerStringEncoded()
            })
          ]),
          Data: "{}"
        })
      ])
    );
  });

  it.skip("Returns cooldown list with the user on cooldown", async () => {
    const mint = await handle(createMessage({
      Action: "Credit-Notice",
      "X-Action": "Mint",
      Owner: tags["Collateral-Id"],
      From: tags["Collateral-Id"],
      "From-Process": tags["Collateral-Id"],
      Quantity: testQty,
      Recipient: env.Process.Id,
      Sender: testWallet,
      // @ts-expect-error
      ["Block-Height"]: block
    }));

    expect(mint.Messages).toEqual(
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

    block++;

    const msg = createMessage({
      Action: "Cooldowns",
      // @ts-expect-error
      ["Block-Height"]: block
    });
    const res = await handle(msg);

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: msg.From,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Cooldown-Period",
              value: cooldown.toString()
            }),
            expect.objectContaining({
              name: "Request-Block-Height",
              value: expect.toBeIntegerStringEncoded()
            })
          ]),
          Data: expect.toBeJsonEncoded(expect.objectContaining({
            [testWallet]: expect.any(Number)
          }))
        })
      ])
    );
  });

  it("Returns no user cooldown if the user is not on a cooldown", async () => {
    const res = await handle(createMessage({
      Action: "Is-Cooldown",
      From: testWallet,
      Owner: testWallet,
      // @ts-expect-error
      ["Block-Height"]: block
    }));

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: testWallet,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "On-Cooldown",
              value: "false"
            }),
            expect.objectContaining({
              name: "Cooldown-Period",
              value: cooldown.toString()
            }),
            expect.objectContaining({
              name: "Request-Block-Height",
              value: expect.toBeIntegerStringEncoded()
            })
          ])
        })
      ])
    );
    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: testWallet,
          Tags: expect.not.arrayContaining([
            expect.objectContaining({
              name: "Cooldown-Expires",
              value: expect.toBeIntegerStringEncoded()
            })
          ])
        })
      ])
    );
  });

  it.skip("Returns the user cooldown correctly", async () => {
    const expiryBlock = block + cooldown;
    const mint = await handle(createMessage({
      Action: "Credit-Notice",
      "X-Action": "Mint",
      Owner: tags["Collateral-Id"],
      From: tags["Collateral-Id"],
      "From-Process": tags["Collateral-Id"],
      Quantity: testQty,
      Recipient: env.Process.Id,
      Sender: testWallet,
      // @ts-expect-error
      ["Block-Height"]: block
    }));

    expect(mint.Messages).toEqual(
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

    block++;

    const res = await handle(createMessage({
      Action: "Is-Cooldown",
      From: testWallet,
      Owner: testWallet,
      // @ts-expect-error
      ["Block-Height"]: block
    }));

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: testWallet,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "On-Cooldown",
              value: "true"
            }),
            expect.objectContaining({
              name: "Cooldown-Period",
              value: cooldown.toString()
            }),
            expect.objectContaining({
              name: "Request-Block-Height",
              value: expect.toBeIntegerStringEncoded()
            }),
            expect.objectContaining({
              name: "Cooldown-Expires",
              value: expiryBlock.toString()
            })
          ])
        })
      ])
    );
  });
});

describe("Updater tests", () => {
  let handle: HandleFunction;
  let controller: string;

  beforeAll(async () => {
    handle = await setupProcess(env);
    controller = env.Process.Owner;
  });

  it("Rejects updating if the caller is not the controller", async () => {
    const otherAddr = generateArweaveAddress();
    const res = await handle(createMessage({
      From: otherAddr,
      Owner: otherAddr,
      Action: "Update",
      Data: "Handlers.add('test', { Action = 'Test' }, function (msg) msg.reply({ Hi = 'test' }) end)"
    }));

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: otherAddr,
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

  it("Does not load invalid update code", async () => {
    const res = await handle(createMessage({
      From: controller,
      Owner: controller,
      Action: "Update",
      Data: "}) end)"
    }));

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error"
            })
          ])
        })
      ])
    );
  });

  it("Throws an error if the update script errors", async () => {
    const res = await handle(createMessage({
      From: controller,
      Owner: controller,
      Action: "Update",
      Data: "error('test')"
    }));

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: "test"
            })
          ])
        })
      ])
    );
  });

  it("Updates successfully", async () => {
    const updateRes = await handle(createMessage({
      From: controller,
      Owner: controller,
      Action: "Update",
      Data: "Handlers.add('test', { Action = 'Test' }, function (msg) msg.reply({ Hi = 'test' }) end)"
    }));

    expect(updateRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Updated",
              value: "true"
            })
          ])
        })
      ])
    );

    // test the added handler
    const handlerRes = await handle(createMessage({ Action: "Test" }));

    expect(handlerRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Hi",
              value: "test"
            })
          ])
        })
      ])
    );

    // test if previous handlers are still working
    const infoRes = await handle(createMessage({ Action: "Info" }));

    expect(infoRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Name",
              value: expect.any(String)
            }),
            expect.objectContaining({
              name: "Ticker",
              value: expect.any(String)
            }),
            expect.objectContaining({
              name: "Logo",
              value: expect.toBeArweaveAddress()
            })
          ])
        })
      ])
    );
  });
});

describe("Reserves tests", () => {
  let handle: HandleFunction;
  let controller: string;
  let tags: Record<string, string>;

  // in percentage
  const reserveFactor = 50;

  beforeAll(async () => {
    const envWithReserves = {
      Process: {
        ...env.Process,
        Tags: [
          ...env.Process.Tags,
          { name: "Reserve-Factor", value: reserveFactor.toString() }
        ]
      }
    };

    handle = await setupProcess(envWithReserves);
    controller = envWithReserves.Process.Owner;
    tags = normalizeTags(envWithReserves.Process.Tags);
  });

  it("Does not let anyone withdraw/deploy apart from the controller", async () => {
    const otherAddr = generateArweaveAddress();
    const withdrawRes = await handle(createMessage({
      Action: "Withdraw-From-Reserves",
      Quantity: "15",
      From: otherAddr,
      Owner: otherAddr
    }));

    expect(withdrawRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: otherAddr,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "The request could not be handled"
              )
            })
          ])
        })
      ])
    );

    const deployRes = await handle(createMessage({
      Action: "Deploy-From-Reserves",
      Quantity: "34",
      From: otherAddr,
      Owner: otherAddr
    }));

    expect(deployRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: otherAddr,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "The request could not be handled"
              )
            })
          ])
        })
      ])
    );
  });

  it("Does not let an invalid quantity to be withdrawn", async () => {
    const withdrawRes = await handle(createMessage({
      Action: "Withdraw-From-Reserves",
      Quantity: "-1",
      From: controller,
      Owner: controller
    }));

    expect(withdrawRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Invalid withdraw quantity"
              )
            })
          ])
        })
      ])
    );
  });

  it("Does not let an invalid quantity to be deployed", async () => {
    const deployRes = await handle(createMessage({
      Action: "Deploy-From-Reserves",
      Quantity: "-845",
      From: controller,
      Owner: controller
    }));

    expect(deployRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Invalid deploy quantity"
              )
            })
          ])
        })
      ])
    );
  });

  it("Does not let withdrawing a quantity that is higher than the reserves", async () => {
    const withdrawRes = await handle(createMessage({
      Action: "Withdraw-From-Reserves",
      Quantity: "25",
      From: controller,
      Owner: controller
    }));

    expect(withdrawRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Not enough tokens available to withdraw"
              )
            })
          ])
        })
      ])
    );
  });

  it("Does not let an invalid quantity to be deployed", async () => {
    const deployRes = await handle(createMessage({
      Action: "Deploy-From-Reserves",
      Quantity: "42857",
      From: controller,
      Owner: controller
    }));

    expect(deployRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Not enough tokens available to deploy"
              )
            })
          ])
        })
      ])
    );
  });

  it("Applies the reserve factor to interests", async () => {
    const wallet = generateArweaveAddress();
    const supplyQty = 4255279295n;

    // mint first
    const mintRes = await handle(createMessage({
      Action: "Credit-Notice",
      "X-Action": "Mint",
      Owner: tags["Collateral-Id"],
      From: tags["Collateral-Id"],
      "From-Process": tags["Collateral-Id"],
      Quantity: supplyQty.toString(),
      Recipient: env.Process.Id,
      Sender: wallet
    }));
    await handle(createMessage({
      "Queued-User": wallet,
      "X-Reference": normalizeTags(
        getMessageByAction("Add-To-Queue", mintRes.Messages)?.Tags || []
      )["Reference"]
    }));

    // now borrow
    const borrowQty = 40000n;
    const queueRes = await handle(createMessage({
      Action: "Borrow",
      Quantity: borrowQty.toString(),
      From: wallet,
      Owner: wallet
    }));

    // oracle request
    const oracleRes = await handle(createMessage({
      "Queued-User": wallet,
      "X-Reference": normalizeTags(
        getMessageByAction("Add-To-Queue", queueRes.Messages)?.Tags || []
      )["Reference"]
    }));

    // give a price, finish borrow
    const oracleInputRes = await handle(
      generateOracleResponse({ AR: 1 }, oracleRes)
    );

    // a timestamp, where the user already owns some interest
    const later = (parseInt(defaultTimestamp) + 10000000000).toString()

    // get how much we owe
    const position = await handle(createMessage({
      Action: "Position",
      From: wallet,
      Owner: wallet,
      Timestamp: later
    }));
    const owned = BigInt(position.Messages.find(
      (msg) => !!msg.Tags.find((tag) => tag.name === "Borrow-Balance")
    )?.Tags?.find((tag) => tag.name === "Borrow-Balance")?.value || "0");

    expect(owned).toBeGreaterThan(borrowQty);

    const interest = owned - borrowQty;

    // repay the loan
    const repayRes = await handle(createMessage({
      Action: "Credit-Notice",
      "X-Action": "Repay",
      Owner: tags["Collateral-Id"],
      From: tags["Collateral-Id"],
      "From-Process": tags["Collateral-Id"],
      Quantity: owned.toString(),
      Recipient: env.Process.Id,
      Sender: wallet
    }));

    await handle(createMessage({
      "Queued-User": wallet,
      "X-Reference": normalizeTags(
        getMessageByAction("Add-To-Queue", repayRes.Messages)?.Tags || []
      )["Reference"]
    }));

    // expect the reserves to contain some the amount the reserve factor dictates
    const reservesRes = await handle(createMessage({ Action: "Total-Reserves" }));

    expect(reservesRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Total-Reserves",
              value: ((interest * BigInt(reserveFactor)) / 100n).toString()
            })
          ])
        })
      ])
    );

    // expect the pool to include the provided amount + the interest - the amount in the reserves
    const cashRes = await handle(createMessage({ Action: "Cash" }));

    expect(cashRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Cash",
              value: ((interest * BigInt(100 - reserveFactor)) / 100n + supplyQty).toString()
            })
          ])
        })
      ])
    );
  });

  it("Withdraws the correct quantity", async () => {
    // get current reserves
    const reservesRes = await handle(createMessage({ Action: "Total-Reserves" }));
    const reserves = BigInt(reservesRes.Messages[0]?.Tags?.find((t) => t.name == "Total-Reserves")?.value || 0);

    // withdraw
    const qty = "15";
    const withdrawRes = await handle(createMessage({
      Action: "Withdraw-From-Reserves",
      Quantity: qty,
      From: controller,
      Owner: controller
    }));

    expect(withdrawRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: tags["Collateral-Id"],
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Transfer"
            }),
            expect.objectContaining({
              name: "Quantity",
              value: qty,
            }),
            expect.objectContaining({
              name: "Recipient",
              value: controller
            })
          ])
        }),
        expect.objectContaining({
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Total-Reserves",
              value: (reserves - BigInt(qty)).toString()
            })
          ])
        })
      ])
    );
  });

  it("Deploys the correct quantity", async () => {
    // get current reserves
    const infoRes = await handle(createMessage({ Action: "Info" }));
    const resp = infoRes.Messages.find((msg) => !!msg.Tags.find(t => t.name === "Name"));
    const respTags = normalizeTags(resp?.Tags || []);

    // deploy
    const qty = 20n;
    const deployRes = await handle(createMessage({
      Action: "Deploy-From-Reserves",
      Quantity: qty.toString(),
      From: controller,
      Owner: controller
    }));

    expect(deployRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Total-Reserves",
              value: (BigInt(respTags["Total-Reserves"]) - qty).toString()
            }),
            expect.objectContaining({
              name: "Cash",
              value: (BigInt(respTags["Cash"]) + qty).toString()
            })
          ])
        })
      ])
    );
  });
});
