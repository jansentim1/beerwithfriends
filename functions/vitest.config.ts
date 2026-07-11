import { defineConfig } from "vitest/config";
// fileParallelism: false — emulator tests share one Firestore emulator and each
// file's beforeEach calls clearDb(), so concurrent files wipe each other's seeds.
export default defineConfig({ test: { testTimeout: 20000, hookTimeout: 30000, fileParallelism: false } });
