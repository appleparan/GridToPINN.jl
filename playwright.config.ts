import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests',
  fullyParallel: false,
  // 시스템 Chrome 사용 (Playwright 번들 Chromium 대신)
  // google-chrome-stable /usr/bin/google-chrome-stable
  projects: [
    {
      name: 'chromium',
      use: {
        ...devices['Desktop Chrome'],
        channel: 'chrome', // 시스템 Chrome 사용
        executablePath: '/usr/bin/google-chrome-stable',
      },
    },
  ],
  timeout: 60_000,
  use: {
    headless: true,
    trace: 'on-first-retry',
  },
});
