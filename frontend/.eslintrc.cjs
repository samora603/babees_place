/* ESLint (v8 legacy config) — added in Phase 1 to restore the quality gate. */
module.exports = {
  root: true,
  env: {
    browser: true,
    es2022: true,
    node: true,
  },
  parserOptions: {
    ecmaVersion: 'latest',
    sourceType: 'module',
    ecmaFeatures: { jsx: true },
  },
  settings: {
    react: { version: 'detect' },
  },
  extends: [
    'eslint:recommended',
    'plugin:react/recommended',
    'plugin:react/jsx-runtime',
    'plugin:react-hooks/recommended',
  ],
  plugins: ['react', 'react-hooks'],
  rules: {
    // React 17+ JSX transform — no need to import React in scope.
    'react/react-in-jsx-scope': 'off',
    'react/prop-types': 'off',
    // Keep signal high without blocking the build on style-level issues.
    'no-unused-vars': ['warn', { argsIgnorePattern: '^_', varsIgnorePattern: '^_' }],
    'react-hooks/exhaustive-deps': 'warn',
    'no-empty': ['warn', { allowEmptyCatch: true }],
  },
  ignorePatterns: ['dist/', 'node_modules/', '*.config.js', '*.cjs'],
};
