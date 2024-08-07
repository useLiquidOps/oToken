import type { Environment, Message } from "@permaweb/ao-loader";
import { expect } from "bun:test";

export const env = {
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

export function expectMessage(expected: Partial<Message>) {
  return expect.objectContaining({
    Owner: expected.Owner || expect.any(String),
    Target: expected.Target || expect.any(String),
    Tags: expected.Tags ? expect.arrayContaining(expected.Tags) : undefined,
    Data: expected.Data || undefined,
    From: expected.From || expect.any(String)
  });
}
