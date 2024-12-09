import type { Environment, HandleResponse, Message, Tag } from "@permaweb/ao-loader";
import AoLoader from "@permaweb/ao-loader";
import { expect } from "@jest/globals";
import fs from "fs/promises";
import path from "path";

export const env: Environment = {
  Process: {
    Id: "0000000000000000000000000000000000000000000",
    Owner: "000000000000000000000000000000000CONTROLLER",
    Tags: [
      { name: "Collateral-Name", value: "Arweave" },
      { name: "Collateral-Ticker", value: "AR" },
      { name: "Logo", value: "0000000000000000000000000000000000000000002" },
      { name: "Collateral-Id", value: "0000000000000000000000000000000000000000002" },
      { name: "Collateral-Denomination", value: "12" },
      { name: "Collateral-Factor", value: "2" },
      { name: "Liquidation-Threshold", value: "1.2" },
      { name: "Base-Rate", value: "0.5" },
      { name: "Friends", value: "[]" },
      { name: "Init-Rate", value: "1.5" },
      { name: "Oracle", value: "0000000000000000000000000000000000000ORACLE" },
      { name: "Oracle-Delay-Tolerance", value: "3600000" }
    ]
  }
};
export const defaultTimestamp = "172302981";
export const dummyEthAddr = "0x0000000000000000000000000000000000000000";

export type HandleFunction = (msg: Message, env?: Environment) => Promise<AoLoader.HandleResponse>;

export async function setupProcess(defaultEnvironment: Environment, keepMemory = true): Promise<HandleFunction> {
  const wasmBinary = await fs.readFile(path.join(__dirname, "../src/process.wasm"));

  // get handler function
  const defaultHandle = await AoLoader(wasmBinary, {
    format: "wasm64-unknown-emscripten-draft_2024_02_15",
    memoryLimit: "1-gb",
    computeLimit: 9_000_000_000
  });

  // current state of the process
  let currentMemory: ArrayBuffer | null = null;

  // handler function that automatically saves the state
  return async (msg, env) => {
    // call handle
    const res = await defaultHandle(currentMemory, msg, env || defaultEnvironment);

    // save memory
    if (keepMemory)
      currentMemory = res.Memory;

    return res;
  };
}

export function generateArweaveAddress() {
  let address = "";
  const allowedChars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

  while (address.length < 43) {
    address += allowedChars[Math.floor(Math.random() * allowedChars.length)];
  }

  return address;
}

export function createMessage(message: Partial<Omit<Message, "Tags">> & { [tagName: string]: string }): Message {
  const nonTags = ["Signature", "Owner", "Target", "Anchor", "Data", "From", "Forwarded-By", "Epoch", "Nonce", "Block-Height", "Timestamp", "Hash-Chain", "Cron"];
  const tags: Tag[] = [];
  const constructedMsg: Record<string, unknown> = {
    Id: "0000000000000000000000000000000000000000003",
    Target: env.Process.Id,
    Owner: env.Process.Owner,
    From: env.Process.Owner,
    ["Block-Height"]: 1,
    Timestamp: defaultTimestamp,
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

interface OracleData {
  [symbol: string]: number | {
    t?: number;
    a?: string;
    v: number;
  };
}

export function generateOracleResponse(data: OracleData, replyTo?: HandleResponse, oracle?: string): Message {
  if (!oracle) oracle = normalizeTags(env.Process.Tags)["Oracle"];

  // generate price data
  const fullOracleData: OracleData = {};

  for (const token in data) {
    let tokenData: OracleData[keyof OracleData] = { v: 0 };

    if (typeof data[token] === "number") tokenData.v = data[token];
    else tokenData = data[token];

    tokenData.a = tokenData.a || dummyEthAddr;
    tokenData.t = tokenData.t || parseInt(defaultTimestamp);

    fullOracleData[token] = tokenData;
  }

  // add reference for reply
  let replyReference: string | undefined = undefined;

  if (replyTo) {
    const priceReqMsg = replyTo.Messages.find((msg) => {
      const tags = normalizeTags(msg.Tags);

      return tags["Action"] === "v2.Request-Latest-Data";
    });

    if (priceReqMsg) {
      replyReference = normalizeTags(priceReqMsg.Tags)["Reference"];
    }
  }

  return createMessage({
    Owner: oracle,
    From: oracle,
    ...(replyReference && { ["X-Reference"]: replyReference }),
    Data: JSON.stringify(fullOracleData)
  })
}

export function normalizeTags(tags: Tag[]) {
  const normalized: Record<string, string> = {};

  for (const tag of tags) {
    normalized[tag.name] = tag.value;
  }

  return normalized;
}

expect.extend({
  toBeIntegerStringEncoded(actual: unknown) {
    const pass = typeof actual === "string" && actual.match(/^-?\d+$/) !== null;

    return {
      pass,
      message: () => `expected ${this.utils.printReceived(actual)} to be a ${this.utils.printExpected("string encoded integer")}`
    }
  },
  toBeFloatStringEncoded(actual: unknown) {
    const pass = typeof actual === "string" && actual.match(/^-?\d+(\.\d+)?$/) !== null;
    
    return {
      pass,
      message: () => `expected ${this.utils.printReceived(actual)} to be a ${this.utils.printExpected("string encoded float")}`
    }
  },
  toBeArweaveAddress(actual: unknown) {
    const pass = typeof actual === "string" && /^[a-z0-9_-]{43}$/i.test(actual);

    return {
      pass,
      message: () => `expected ${this.utils.printReceived(actual)} to be an ${this.utils.printExpected("Arweave address")}`
    }
  },
  toBeJsonEncoded(actual: string, matcher: jest.AsymmetricMatcher) {
    let parsed: unknown;
    
    try {
      parsed = JSON.parse(actual);
    } catch (error: any) {
      return {
        message: () => `expected "${actual}" to be a valid JSON string, but got a parsing error: ${error?.message || error}`,
        pass: false,
      };
    }

    const pass = matcher.asymmetricMatch(parsed);

    return {
      pass,
      message: () => "expected decoded JSON to match, but it didn't"
    }
  }
});

declare module "expect" {
  interface AsymmetricMatchers {
    toBeIntegerStringEncoded(): void;
    toBeFloatStringEncoded(): void;
    toBeArweaveAddress(): void;
    toBeJsonEncoded(matcher: jest.AsymmetricMatcher): void;
  }
  interface Matchers<R> {
    toBeIntegerStringEncoded(): R;
    toBeFloatStringEncoded(): R;
    toBeArweaveAddress(): R;
    toBeJsonEncoded(matcher: jest.AsymmetricMatcher): R;
  }
}
