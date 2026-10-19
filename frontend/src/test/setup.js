// setup.js: runs before every test file (vite.config.js -> test.setupFiles).
//
// Adds DOM matchers such as toBeInTheDocument() and toBeDisabled() to
// Vitest's expect, and unmounts rendered components after each test so
// tests don't see each other's DOM.

import "@testing-library/jest-dom/vitest";
import { cleanup } from "@testing-library/react";
import { afterEach } from "vitest";

afterEach(() => {
  cleanup();
});
