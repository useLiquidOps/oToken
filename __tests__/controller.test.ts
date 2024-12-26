import { expect } from "@jest/globals";
import {
  setupProcess,
  HandleFunction,
  env,
  createMessage,
  generateArweaveAddress,
  normalizeTags
} from "./utils"

describe("Friend tests", () => {
  let handle: HandleFunction;
  let controller: string;
  let friend: string;

  beforeAll(async () => {
    handle = await setupProcess(env);
    controller = env.Process.Owner;
    friend = generateArweaveAddress();
  });

  test("Does not allow friend interaction from anyone other than the controller", async () => {
    const invalidOwner = generateArweaveAddress();

    // expect error when trying to add a friend not from the controller
    const friendAddRes = await handle(createMessage({
      Action: "Add-Friend",
      Friend: generateArweaveAddress(),
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
              value: expect.any(String)
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
              value: expect.any(String)
            })
          ])
        })
      ])
    );
  });

  test("Does not add a friend with an invalid address", async () => {
    const friendAddRes = await handle(createMessage({
      Action: "Add-Friend",
      Friend: "invalid"
    }));

    expect(friendAddRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
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

  test("Adds a new friend", async () => {
    const friendAddRes = await handle(createMessage({
      Action: "Add-Friend",
      Friend: friend
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
              value: friend
            })
          ])
        })
      ])
    );
  });

  test("Lists friends correctly", async () => {
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
            expect.arrayContaining([friend])
          )
        })
      ])
    );
  });

  test("Errors on trying to remove an address from friends, that is not a friend", async () => {
    const friendRemoveRes = await handle(createMessage({
      Action: "Remove-Friend",
      Friend: generateArweaveAddress()
    }));

    expect(friendRemoveRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
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

  test("Removes friend", async () => {
    const friendRemoveRes = await handle(createMessage({
      Action: "Remove-Friend",
      Friend: friend
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
              name: "Friend",
              value: friend
            })
          ])
        })
      ])
    );
  });

  test("Lists empty friends list correctly", async () => {
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

  test("Does not allow config interaction from anyone other than the controller", async () => {
    const invalidOwner = generateArweaveAddress();

    // expect error when trying to set the oracle not from the controller
    const oracleSetRes = await handle(createMessage({
      Action: "Set-Oracle",
      Oracle: generateArweaveAddress(),
      Owner: invalidOwner,
      From: invalidOwner
    }));

    expect(oracleSetRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: invalidOwner,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.any(String)
            })
          ])
        })
      ])
    );

    // expect error when trying to set the collateral factor not from the controller
    const collateralRatioRes = await handle(createMessage({
      Action: "Set-Collateral-Factor",
      ["Collateral-Factor"]: "1.25",
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
              value: expect.any(String)
            })
          ])
        })
      ])
    );

    // expect error when trying to set the collateral factor not from the controller
    const liquidationThresholdSet = await handle(createMessage({
      Action: "Set-Liquidation-Threshold",
      ["Liquidation-Threshold"]: "1.05",
      Owner: invalidOwner,
      From: invalidOwner
    }));

    expect(liquidationThresholdSet.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: invalidOwner,
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

  test("Does not update oracle with an invalid address", async () => {
    const res = await handle(createMessage({
      Action: "Set-Oracle",
      Oracle: "invalid"
    }));

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
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

  test("Updates the oracle", async () => {
    const res = await handle(createMessage({
      Action: "Set-Oracle",
      Oracle: newOracle
    }));

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Oracle-Set"
            }),
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

  test("Does not update collateral factor with an invalid value", async () => {
    const res = await handle(createMessage({
      Action: "Set-Collateral-Factor",
      "Collateral-Factor": "invalid"
    }));

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
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

  test("Updates the collateral factor", async () => {
    const newFactor = "3.5";
    const res = await handle(createMessage({
      Action: "Set-Collateral-Factor",
      "Collateral-Factor": newFactor
    }));

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Collateral-Factor-Set"
            }),
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

  test("Does not update liquidation threshold with an invalid value", async () => {
    const res = await handle(createMessage({
      Action: "Set-Liquidation-Threshold",
      "Liquidation-Threshold": "invalid"
    }));

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
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

  test("Updates the liquidation threshold ratio", async () => {
    const newFactor = "3.5";
    const res = await handle(createMessage({
      Action: "Set-Liquidation-Threshold",
      "Liquidation-Threshold": newFactor
    }));

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Liquidation-Threshold-Set"
            }),
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

  test("Rejects interaction while cooldown is not over", async () => {
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

  test("Allows interaction when cooldown is over", async () => {
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
  });
});