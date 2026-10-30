import js from "@eslint/js";
import globals from "globals";
import tseslint from "typescript-eslint";
import reactHooks from "eslint-plugin-react-hooks";
import reactRefresh from "eslint-plugin-react-refresh";
export default tseslint.config(
  { ignores: ["dist", "node_modules"] },
  { files: ["**/*.{ts,tsx}"], extends: [js.configs.recommended, ...tseslint.configs.recommended], languageOptions: { ecmaVersion: 2022, globals: globals.browser }, plugins: { "react-hooks": reactHooks, "react-refresh": reactRefresh }, rules: { ...reactHooks.configs.recommended.rules, "react-refresh/only-export-components": ["warn", { allowConstantExport: true }],
      // This app uses effects to subscribe to auth and load remote data; state writes happen in their async callbacks.
      "react-hooks/set-state-in-effect": "off" } }
);