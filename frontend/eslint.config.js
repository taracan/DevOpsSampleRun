// eslint.config.js: ESLint settings for the React app (`npm run lint`).
//
// ESLint reads the source and flags likely bugs: unused variables, missing
// hook dependencies, components that break fast refresh, and so on.
// This is ESLint 9's "flat config": a list of rule sets, applied in order.
//
//   @eslint/js             JavaScript's recommended rules
//   eslint-plugin-react    React rules (JSX, keys, ...)
//   react-hooks            the Rules of Hooks
//   react-refresh          keeps Vite's hot reload working per component
//
// Test files (*.test.jsx) also get Vitest's globals.

import js from "@eslint/js";
import react from "eslint-plugin-react";
import reactHooks from "eslint-plugin-react-hooks";
import reactRefresh from "eslint-plugin-react-refresh";
import globals from "globals";

export default [
  { ignores: ["dist/"] },
  js.configs.recommended,
  react.configs.flat.recommended,
  react.configs.flat["jsx-runtime"], // React 17+: no `import React` needed for JSX
  reactHooks.configs.flat.recommended,
  reactRefresh.configs.vite,
  {
    files: ["**/*.{js,jsx}"],
    languageOptions: {
      ecmaVersion: "latest",
      sourceType: "module",
      globals: globals.browser,
    },
    settings: { react: { version: "detect" } },
    rules: {
      "react/prop-types": "off", // plain JS project, no PropTypes
    },
  },
  {
    files: ["**/*.test.{js,jsx}", "src/test/**"],
    languageOptions: { globals: { ...globals.node, ...globals.vitest } },
  },
];
