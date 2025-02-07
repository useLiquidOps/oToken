import { expect } from "@jest/globals";
import {
  setupProcess,
  HandleFunction,
  env,
  createMessage,
  generateArweaveAddress,
  normalizeTags,
  getMessageByAction
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

  it("Does not allow friend interaction from anyone other than the controller", async () => {
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

  it("Does not add a friend with an invalid address", async () => {
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
              value: expect.stringContaining(
                "Invalid friend address"
              )
            })
          ])
        })
      ])
    );
  });

  it("Does not add itself as a friend", async () => {
    const friendAddRes = await handle(createMessage({
      Action: "Add-Friend",
      Friend: env.Process.Id
    }));

    expect(friendAddRes.Messages).toEqual(
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

  it("Does not add a friend that is already added", async () => {
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
            expect.arrayContaining([friend])
          )
        })
      ])
    );
  });

  it("Errors on trying to remove an address from friends, that is not a friend", async () => {
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
              value: expect.stringContaining(
                "Address is not a friend yet"
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
              value: expect.stringContaining(
                "The request could not be handled"
              )
            })
          ])
        })
      ])
    );

    // expect error when trying to set the collateral factor not from the controller
    const collateralRatioRes = await handle(createMessage({
      Action: "Set-Collateral-Factor",
      ["Collateral-Factor"]: "80",
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

    // expect error when trying to set the liquidation factor not from the controller
    const liquidationThresholdSet = await handle(createMessage({
      Action: "Set-Liquidation-Threshold",
      ["Liquidation-Threshold"]: "60",
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

  it("Does not update collateral factor with an invalid value", async () => {
    expect((await handle(createMessage({
      Action: "Set-Collateral-Factor",
      "Collateral-Factor": "invalid"
    }))).Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Invalid ratio provided"
              )
            })
          ])
        })
      ])
    );

    expect((await handle(createMessage({
      Action: "Set-Collateral-Factor",
      "Collateral-Factor": "1.2"
    }))).Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Collateral factor has to be a whole percentage between 0 and 100"
              )
            })
          ])
        })
      ])
    );
    expect((await handle(createMessage({
      Action: "Set-Collateral-Factor",
      "Collateral-Factor": "-1"
    }))).Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Collateral factor has to be a whole percentage between 0 and 100"
              )
            })
          ])
        })
      ])
    );
    expect((await handle(createMessage({
      Action: "Set-Collateral-Factor",
      "Collateral-Factor": "101"
    }))).Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Collateral factor has to be a whole percentage between 0 and 100"
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

  it("Does not update liquidation threshold with an invalid value", async () => {
    expect((await handle(createMessage({
      Action: "Set-Liquidation-Threshold",
      "Liquidation-Threshold": "invalid"
    }))).Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Invalid threshold provided"
              )
            })
          ])
        })
      ])
    );

    expect((await handle(createMessage({
      Action: "Set-Liquidation-Threshold",
      "Liquidation-Threshold": "34.9"
    }))).Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Liquidation threshold has to be a whole percentage between 0 and 100"
              )
            })
          ])
        })
      ])
    );
    expect((await handle(createMessage({
      Action: "Set-Liquidation-Threshold",
      "Liquidation-Threshold": "-9"
    }))).Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Liquidation threshold has to be a whole percentage between 0 and 100"
              )
            })
          ])
        })
      ])
    );
    expect((await handle(createMessage({
      Action: "Set-Liquidation-Threshold",
      "Liquidation-Threshold": "124"
    }))).Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Liquidation threshold has to be a whole percentage between 0 and 100"
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

  it("Does not update the value limit with an invalid value", async () => {
    const invalidVal = "invalid";
    const invalidQtyRes = await handle(createMessage({
      Action: "Set-Value-Limit",
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
                invalidVal + " cannot be represented by a bint"
              )
            })
          ])
        })
      ])
    );

    const zeroQtyRes = await handle(createMessage({
      Action: "Set-Value-Limit",
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
                "Value limit must be higher than zero"
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
      Action: "Set-Value-Limit",
      "Value-Limit": newValueLimit
    }));

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Value-Limit-Set"
            }),
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
      Action: "Set-Oracle-Delay-Tolerance",
      "Oracle-Delay-Tolerance": "invalid"
    }));

    expect(invalidValueRes.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Error",
              value: expect.stringContaining(
                "Invalid or no delay tolerance provided"
              )
            })
          ])
        })
      ])
    );

    const nonZeroRes = await handle(createMessage({
      Action: "Set-Oracle-Delay-Tolerance",
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
                "Delay tolerance has to be >= 0"
              )
            })
          ])
        })
      ])
    );

    const nonIntegerTest = await handle(createMessage({
      Action: "Set-Oracle-Delay-Tolerance",
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
                "Delay tolerance has to be a whole number"
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
      Action: "Set-Oracle-Delay-Tolerance",
      "Oracle-Delay-Tolerance": newDelayTolerance
    }));

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Oracle-Delay-Tolerance-Set"
            }),
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