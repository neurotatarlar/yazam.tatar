const { test, expect } = require("@playwright/test");

function streamBody(correctedText) {
  return [
    "event: meta",
    'data: {"request_id":"pw-smoke-1"}',
    "",
    "event: delta",
    `data: ${JSON.stringify({ text: correctedText })}`,
    "",
    "event: done",
    'data: {"latency_ms":12}',
    "",
  ].join("\n");
}

test("streaming correction updates output and history", async ({ page }) => {
  await page.route("**/api/v1/correct/stream", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "text/event-stream",
      body: streamBody("Бу төзәтелгән текст."),
    });
  });

  await page.goto("/");

  const streamingState = page.locator("#streaming-state");
  const originalInput = page.locator("#original-input");
  const correctedOutput = page.locator("#corrected-output");

  await expect(streamingState).toBeHidden();
  await originalInput.fill("Бу хата текст.");
  await page.locator("#btn-correct").click();

  await expect(correctedOutput).toHaveText("Бу төзәтелгән текст.");
  await expect(streamingState).toBeHidden();

  await page.locator("#nav-history").click();
  await expect(page.locator("#history-list")).toContainText("Бу хата текст.");
  await expect(page.locator("#history-list")).toContainText(
    "Бу төзәтелгән текст.",
  );
});

test("clear button resets source and correction panels", async ({ page }) => {
  await page.route("**/api/v1/correct/stream", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "text/event-stream",
      body: streamBody("Текст төзәтелде."),
    });
  });

  await page.goto("/");

  const originalInput = page.locator("#original-input");
  const correctedOutput = page.locator("#corrected-output");

  await originalInput.fill("Башлангыч вариант.");
  await page.locator("#btn-correct").click();
  await expect(correctedOutput).toHaveText("Текст төзәтелде.");

  await page.locator("#btn-clear").click();
  await expect(originalInput).toHaveValue("");
  await expect(correctedOutput).toHaveText("Төзәтелгән текст монда булыр");
});
