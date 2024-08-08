import AoLoader, { type Environment, type Message, type Tag } from "@permaweb/ao-loader";
import fs from "fs/promises";
import path from "path";

const environment = {
  Process: {
    Id: "0000000000000000000000000000000000000000000",
    Owner: "0000000000000000000000000000000000000000001",
    Tags: [
      { name: "Name", value: "loToken" },
      { name: "Ticker", value: "TST" },
      { name: "Logo", value: "0000000000000000000000000000000000000000002" }
    ]
  }
};

// for types
export const env = environment as unknown as Environment;

export async function setupProcess() {
  const wasmBinary = await fs.readFile(path.join(__dirname, "../src/process.wasm"));

  return await AoLoader(wasmBinary, {
    format: "wasm64-unknown-emscripten-draft_2024_02_15",
    // @ts-expect-error
    memoryLimit: "1-gb",
    computeLimit: 9_000_000_000
  });
}

export function createMessage(message: Partial<Omit<Message, "Tags">> & { [tagName: string]: string }): Message {
  const nonTags = ["Signature", "Owner", "Target", "Anchor", "Data", "From", "Forwarded-By", "Epoch", "Nonce", "Block-Height", "Timestamp", "Hash-Chain", "Cron"];
  const tags: Tag[] = [];
  const constructedMsg: Record<string, unknown> = {
    Target: environment.Process.Id,
    Owner: environment.Process.Owner,
    From: environment.Process.Owner,
    ["Block-Height"]: "1",
    Timestamp: "172302981",
    Cron: false
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

/*
export function expectMessage(expected: Partial<Message>) {
  return expect.objectContaining({
    Owner: expected.Owner || expect.any(String),
    Target: expected.Target || expect.any(String),
    Tags: expected.Tags ? expect.arrayContaining(expected.Tags) : undefined,
    Data: expected.Data || undefined,
    From: expected.From || expect.any(String)
  });
}
*/