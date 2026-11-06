import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'node',
    fileParallelism: false,
    include: ['src/**/*.spec.ts', 'test/**/*.spec.ts', 'test/**/*.e2e-spec.ts'],
    coverage: {
      provider: 'v8',
      reportsDirectory: '../coverage/backend',
      include: ['src/auth/**/*.ts', 'src/authorization/**/*.ts'],
      thresholds: { lines: 80, statements: 80, functions: 80 },
    },
  },
});
