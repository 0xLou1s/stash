// All storage goes through here so the content script never needs to know
// where bookmarks live. For now that's chrome.storage.local; once the server
// exists, these handlers become fetch() calls to it.

const STORAGE_KEY = "bookmarks";

async function readAll() {
  const { [STORAGE_KEY]: all = {} } = await chrome.storage.local.get(STORAGE_KEY);
  return all;
}

async function writeAll(all) {
  await chrome.storage.local.set({ [STORAGE_KEY]: all });
}

const handlers = {
  async save({ bookmark }) {
    const all = await readAll();
    all[bookmark.id] = { ...bookmark, savedAt: new Date().toISOString() };
    await writeAll(all);
    return { saved: true };
  },

  async remove({ id }) {
    const all = await readAll();
    delete all[id];
    await writeAll(all);
    return { saved: false };
  },

  async savedIds() {
    return { ids: Object.keys(await readAll()) };
  },
};

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  const handler = handlers[message?.type];
  if (!handler) return false;

  handler(message).then(sendResponse, (error) => sendResponse({ error: String(error) }));
  return true; // keep the channel open for the async response
});
