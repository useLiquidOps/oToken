import { expect } from "@jest/globals";
import {
  setupProcess,
  HandleFunction,
  env,
  createMessage,
  generateArweaveAddress
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

    // expect error when trying to set the collateral ratio not from the controller
    const collateralRatioRes = await handle(createMessage({
      Action: "Set-Collateral-Ratio",
      ["Collateral-Ratio"]: "1.25",
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

    // expect error when trying to set the collateral ratio not from the controller
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

  test("Does not update collateral ratio with an invalid value", async () => {
    const res = await handle(createMessage({
      Action: "Set-Collateral-Ratio",
      "Collateral-Ratio": "invalid"
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

  test("Updates the collateral ratio", async () => {
    const newRatio = "3.5";
    const res = await handle(createMessage({
      Action: "Set-Collateral-Ratio",
      "Collateral-Ratio": newRatio
    }));

    expect(res.Messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Target: controller,
          Tags: expect.arrayContaining([
            expect.objectContaining({
              name: "Action",
              value: "Collateral-Ratio-Set"
            }),
            expect.objectContaining({
              name: "Collateral-Ratio",
              value: newRatio
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
              name: "Collateral-Ratio",
              value: newRatio
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
    const newRatio = "3.5";
    const res = await handle(createMessage({
      Action: "Set-Liquidation-Threshold",
      "Liquidation-Threshold": newRatio
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
              value: newRatio
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
              value: newRatio
            })
          ])
        })
      ])
    );
  });
});
