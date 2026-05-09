import fs from 'node:fs';
import path from 'node:path';
import readline from 'node:readline/promises';
import process from 'node:process';

let chromium;
try {
  ({ chromium } = await import('playwright'));
} catch (error) {
  console.error('Missing dependency: playwright. Run: bash share-private-yt.sh install-automation');
  process.exit(1);
}

const reportPath = process.argv[2];
if (!reportPath) {
  console.error('Usage: node scripts/share_private_videos.mjs <report.json>');
  process.exit(1);
}

const report = JSON.parse(fs.readFileSync(reportPath, 'utf8'));
const privateVideos = report.videos.filter((video) => video.privacyStatus === 'private');
if (privateVideos.length === 0) {
  console.log('No private videos found in the report.');
  process.exit(0);
}

const projectDir = path.resolve(path.dirname(reportPath), '..');
const authDir = path.join(projectDir, '.auth', 'chromium');
const logPath = path.join(path.dirname(reportPath), 'share-log.json');
fs.mkdirSync(authDir, { recursive: true });

const context = await chromium.launchPersistentContext(authDir, {
  headless: false,
  viewport: { width: 1440, height: 960 },
});

const page = context.pages()[0] ?? await context.newPage();
await page.goto('https://studio.youtube.com/', { waitUntil: 'domcontentloaded' });

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout,
});

await rl.question('Sign in to YouTube Studio in the opened browser, then press Enter here to continue.');

const log = [];

for (const video of privateVideos) {
  try {
    const result = await processVideo(page, video, report.emails);
    log.push(result);
    console.log(`${video.videoId}: ${result.status} (${result.added.length} added, ${result.skipped.length} skipped)`);
  } catch (error) {
    log.push({
      videoId: video.videoId,
      title: video.title,
      status: 'error',
      added: [],
      skipped: [],
      error: error instanceof Error ? error.message : String(error),
    });
    console.error(`${video.videoId}: error`);
  }
}

fs.writeFileSync(logPath, JSON.stringify(log, null, 2));
console.log(`Share log written: ${logPath}`);

await rl.close();
await context.close();

async function processVideo(page, video, targetEmails) {
  await page.goto(video.studioUrl, { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle', { timeout: 30000 }).catch(() => {});

  const shareButton = page.getByRole('button', { name: /share privately/i }).first();
  await shareButton.waitFor({ timeout: 30000 });
  await shareButton.click();

  const dialog = page.getByRole('dialog').last();
  await dialog.waitFor({ timeout: 15000 });

  const existingEmails = await collectEmails(dialog);
  const normalizedExisting = new Set(existingEmails.map(normalizeEmail));
  const missingEmails = targetEmails.filter((email) => !normalizedExisting.has(normalizeEmail(email)));

  if (missingEmails.length > 0) {
    const input = dialog.locator('input[type="text"], textarea').last();
    await input.waitFor({ timeout: 15000 });
    for (const email of missingEmails) {
      await input.fill(email);
      await input.press('Enter');
      await page.waitForTimeout(300);
    }

    const saveButton = dialog.getByRole('button', { name: /save/i }).last();
    await saveButton.click();
    await dialog.waitFor({ state: 'hidden', timeout: 15000 }).catch(() => {});
  } else {
    const cancelButton = dialog.getByRole('button', { name: /cancel|close/i }).first();
    if (await cancelButton.count()) {
      await cancelButton.click().catch(() => {});
    } else {
      await page.keyboard.press('Escape').catch(() => {});
    }
  }

  return {
    videoId: video.videoId,
    title: video.title,
    status: missingEmails.length > 0 ? 'updated' : 'skipped',
    added: missingEmails,
    skipped: targetEmails.filter((email) => normalizedExisting.has(normalizeEmail(email))),
    existingEmails,
  };
}

async function collectEmails(dialog) {
  const text = await dialog.innerText();
  const matches = text.match(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi) || [];
  return [...new Set(matches.map(normalizeEmail))];
}

function normalizeEmail(email) {
  return email.trim().toLowerCase();
}
