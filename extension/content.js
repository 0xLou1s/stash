// Adds a Stash button next to X's own bookmark button on every post.
// X's class names are generated, so everything here keys off data-testid.

const BUTTON_CLASS = "stash-button";

const ICON_OUTLINE = `
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"
       stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
    <rect x="3" y="4" width="18" height="4" rx="1"/>
    <path d="M5 8v10a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8"/>
    <path d="M10 12h4"/>
  </svg>`;

const ICON_SAVED = `
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"
       stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
    <rect x="3" y="4" width="18" height="4" rx="1" fill="currentColor"/>
    <path d="M5 8v10a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8"/>
    <path d="M9.5 13.5l2 2 3.5-3.5"/>
  </svg>`;

const savedIds = new Set();

// Quoted posts sit inside a div[role="link"] within the outer article.
// Skip anything in there so we only read the outer post.
function outsideQuote(elements) {
  return [...elements].filter((el) => !el.closest('article div[role="link"]'));
}

function parsePost(article) {
  const time = article.querySelector("time");
  const link = time?.closest('a[href*="/status/"]');
  const match = link?.getAttribute("href").match(/^\/([^/]+)\/status\/(\d+)/);
  if (!match) return null;

  const [, handle, id] = match;
  const nameBlock = article.querySelector('[data-testid="User-Name"]');
  const textBlock = outsideQuote(article.querySelectorAll('[data-testid="tweetText"]'))[0];
  const photos = outsideQuote(article.querySelectorAll('[data-testid="tweetPhoto"] img'));
  const videos = outsideQuote(article.querySelectorAll('[data-testid="videoPlayer"] video[poster]'));

  return {
    id,
    url: `https://x.com/${handle}/status/${id}`,
    author: {
      name: nameBlock?.querySelector("span")?.textContent.trim() || handle,
      handle,
      avatarURL: article.querySelector('[data-testid="Tweet-User-Avatar"] img')?.src ?? null,
    },
    text: textBlock?.innerText ?? "",
    // Width and height let the Mac app lay out the gallery before images load.
    media: [
      ...photos.map((img) => ({
        url: img.src.replace(/name=\w+/, "name=large"),
        width: img.naturalWidth || null,
        height: img.naturalHeight || null,
      })),
      ...videos.map((video) => ({
        url: video.poster,
        width: video.videoWidth || null,
        height: video.videoHeight || null,
      })),
    ],
    postedAt: time.getAttribute("datetime"),
  };
}

function postId(article) {
  const href = article.querySelector("time")?.closest('a[href*="/status/"]')?.getAttribute("href");
  return href?.match(/\/status\/(\d+)/)?.[1] ?? null;
}

function render(button) {
  const saved = savedIds.has(button.dataset.postId);
  button.setAttribute("aria-pressed", String(saved));
  button.setAttribute("aria-label", saved ? "Remove from Stash" : "Save to Stash");
  button.title = saved ? "Remove from Stash" : "Save to Stash";
  button.innerHTML = saved ? ICON_SAVED : ICON_OUTLINE;
}

function showToast(message) {
  document.querySelector(".stash-toast")?.remove();
  const toast = document.createElement("div");
  toast.className = "stash-toast";
  toast.setAttribute("role", "status");
  toast.textContent = message;
  document.body.append(toast);
  setTimeout(() => toast.remove(), 2000);
}

async function toggle(button) {
  const article = button.closest("article");
  const wasSaved = savedIds.has(button.dataset.postId);

  let response;
  try {
    if (wasSaved) {
      response = await chrome.runtime.sendMessage({ type: "remove", id: button.dataset.postId });
    } else {
      // Read the post at click time: X recycles DOM nodes as you scroll.
      const bookmark = parsePost(article);
      if (!bookmark) throw new Error("Couldn't read this post");
      response = await chrome.runtime.sendMessage({ type: "save", bookmark });
    }
  } catch (error) {
    response = { error: String(error) };
  }

  if (response?.error) {
    showToast("Couldn't update Stash. Reload the page and try again.");
    console.error("[Stash]", response.error);
    return;
  }

  if (response.saved) savedIds.add(button.dataset.postId);
  else savedIds.delete(button.dataset.postId);
  document.querySelectorAll(`.${BUTTON_CLASS}[data-post-id="${button.dataset.postId}"]`).forEach(render);
  showToast(response.saved ? "Saved to Stash" : "Removed from Stash");
}

function enhance(article) {
  const id = postId(article);
  if (!id) return;

  const existing = article.querySelector(`.${BUTTON_CLASS}`);
  if (existing) {
    if (existing.dataset.postId !== id) {
      existing.dataset.postId = id;
      render(existing);
    }
    return;
  }

  const bookmarkButton = article.querySelector('[data-testid="bookmark"], [data-testid="removeBookmark"]');
  const actionBar = bookmarkButton?.closest('[role="group"]');
  if (!actionBar) return;

  // Climb to the bookmark button's direct child of the action bar,
  // so our button becomes a sibling slot right after it.
  let slot = bookmarkButton;
  while (slot.parentElement !== actionBar) slot = slot.parentElement;

  const button = document.createElement("button");
  button.type = "button";
  button.className = BUTTON_CLASS;
  button.dataset.postId = id;
  button.addEventListener("click", (event) => {
    // The whole article is clickable; don't let X open the post.
    event.preventDefault();
    event.stopPropagation();
    toggle(button);
  });
  render(button);

  const wrapper = document.createElement("div");
  wrapper.className = "stash-slot";
  wrapper.append(button);
  slot.after(wrapper);
}

let scheduled = false;
function scan() {
  if (scheduled) return;
  scheduled = true;
  requestAnimationFrame(() => {
    scheduled = false;
    document.querySelectorAll('article[data-testid="tweet"]').forEach(enhance);
  });
}

async function start() {
  try {
    const { ids = [] } = await chrome.runtime.sendMessage({ type: "savedIds" });
    ids.forEach((id) => savedIds.add(id));
  } catch (error) {
    console.error("[Stash]", error);
  }
  scan();
  new MutationObserver(scan).observe(document.body, { childList: true, subtree: true });
}

start();
