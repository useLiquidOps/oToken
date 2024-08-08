import { createMessage, env, setupProcess } from "./utils";
import AoLoader from "@permaweb/ao-loader";

describe("Token standard functionalities", () => {
  let handle: AoLoader.handleFunction;
  let memory: ArrayBuffer | null = null;

  beforeAll(async () => {
    handle = await setupProcess();
  });

  it("Returns token info", async () => {
    const message = createMessage({ Action: "Info" });
    const res = handle(memory, message, env);

    throw new Error(JSON.stringify(res))
    /*
    expect(res.Messages).toEqual(
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
              value: expect.any(String)
            }),
            expect.objectContaining({
              name: "Denomination",
              value: expect.any(String)
            })
          ])
        })
      ])
    )*/

    //memory = res.Memory;
  });
});
