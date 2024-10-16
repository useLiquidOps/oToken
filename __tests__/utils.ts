import type { Environment, Message, Tag } from "@permaweb/ao-loader";
import AoLoader from "@permaweb/ao-loader";
import { expect } from "@jest/globals";
import fs from "fs/promises";
import path from "path";

export const env: Environment = {
  Process: {
    Id: "0000000000000000000000000000000000000000000",
    Owner: "0000000000000000000000000000000000000000001",
    Tags: [
      { name: "Collateral-Name", value: "Arweave" },
      { name: "Collateral-Ticker", value: "AR" },
      { name: "Logo", value: "0000000000000000000000000000000000000000002" },
      { name: "Collateral-Id", value: "0000000000000000000000000000000000000000002" },
      { name: "Collateral-Denomination", value: "12" },
      { name: "Collateral-Ratio", value: "2" },
      { name: "Liquidation-Treshold", value: "1.2" },
      { name: "Base-Rate", value: "0.5" },
      { name: "Friends", value: "[]" },
      { name: "Init-Rate", value: "1.5" },
      { name: "Oracle", value: "0000000000000000000000000000000000000000002" },
      { name: "Oracle-Delay-Tolerance", value: "3600000" }
    ]
  }
};

export async function setupProcess() {
  const wasmBinary = await fs.readFile(path.join(__dirname, "../src/process.wasm"));

  return await AoLoader(wasmBinary, {
    format: "wasm64-unknown-emscripten-draft_2024_02_15",
    memoryLimit: "1-gb",
    computeLimit: 9_000_000_000
  });
}

export function createMessage(message: Partial<Omit<Message, "Tags">> & { [tagName: string]: string }): Message {
  const nonTags = ["Signature", "Owner", "Target", "Anchor", "Data", "From", "Forwarded-By", "Epoch", "Nonce", "Block-Height", "Timestamp", "Hash-Chain", "Cron"];
  const tags: Tag[] = [];
  const constructedMsg: Record<string, unknown> = {
    Id: "0000000000000000000000000000000000000000003",
    Target: env.Process.Id,
    Owner: env.Process.Owner,
    From: env.Process.Owner,
    ["Block-Height"]: "1",
    Timestamp: "172302981",
    Module: "examplemodule",
    Cron: false,
    Data: ""
  };

  for (const field in message) {
    if (nonTags.includes(field)) {
      constructedMsg[field] = message[field];
      continue;
    }

    tags.push({ name: field, value: message[field] });
  }

  return {
    ...(constructedMsg as unknown) as Message,
    Tags: tags
  };
}

expect.extend({
  toBeIntegerStringEncoded(actual: unknown) {
    const pass = typeof actual === "string" && actual.match(/^-?\d+$/) !== null;

    return {
      pass,
      message: () => `expected ${this.utils.printReceived(actual)} to be a ${this.utils.printExpected("string encoded integer")}`
    }
  },
  toBeArweaveAddress(actual: unknown) {
    const pass = typeof actual === "string" && /^[a-z0-9_-]{43}$/i.test(actual);

    return {
      pass,
      message: () => `expected ${this.utils.printReceived(actual)} to be an ${this.utils.printExpected("Arweave address")}`
    }
  }
});

declare module "expect" {
  interface AsymmetricMatchers {
    toBeIntegerStringEncoded(): void;
    toBeArweaveAddress(): void;
  }
  interface Matchers<R> {
    toBeIntegerStringEncoded(): R;
    toBeArweaveAddress(): R;
  }
}
