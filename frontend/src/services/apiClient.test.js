// apiClient.test.js: post(), the one function that talks to the backend.
// fetch is replaced by a fake, so no server is needed.

import { afterEach, describe, expect, it, vi } from "vitest";
import { API_BASE_URL } from "../config/env";
import { post } from "./apiClient";

function fakeFetch(status, body) {
  const fetch = vi.fn().mockResolvedValue({
    ok: status >= 200 && status < 300,
    status,
    json: () => (body === undefined ? Promise.reject(new Error("no body")) : Promise.resolve(body)),
  });
  vi.stubGlobal("fetch", fetch);
  return fetch;
}

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("post", () => {
  it("sends JSON to the API and returns the parsed response", async () => {
    const fetch = fakeFetch(201, { id: 1, name: "Alice" });

    const data = await post("/auth/register", { name: "Alice" });

    expect(data).toEqual({ id: 1, name: "Alice" });
    expect(fetch).toHaveBeenCalledWith(`${API_BASE_URL}/auth/register`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name: "Alice" }),
    });
  });

  it("throws the server's message on an error", async () => {
    fakeFetch(400, { detail: "Email is already registered" });

    await expect(post("/auth/register", {})).rejects.toThrow("Email is already registered");
  });

  it("throws a generic message for validation errors (detail is a list)", async () => {
    fakeFetch(422, { detail: [{ msg: "field required" }] });

    await expect(post("/auth/register", {})).rejects.toThrow("Please check your details");
  });

  it("throws a generic message when the error has no JSON body", async () => {
    fakeFetch(502, undefined);

    await expect(post("/auth/register", {})).rejects.toThrow("Please check your details");
  });
});
