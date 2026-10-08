import { CAPTURED_MEDIA_MESSAGE, extractMedia, type CapturedMediaMessage } from "@/lib/x-media"

/**
 * Runs in the page's own JavaScript world so it can see the responses X's app
 * already fetches. It doesn't make any requests itself; it only reads media
 * details (real video files, original image sizes) that the DOM doesn't expose,
 * and hands them to the Stash content script.
 */
export default defineContentScript({
  matches: ["https://x.com/*", "https://twitter.com/*"],
  world: "MAIN",
  runAt: "document_start",
  main() {
    const publish = (json: unknown) => {
      const media = extractMedia(json)
      if (Object.keys(media).length === 0) return
      const message: CapturedMediaMessage = { source: CAPTURED_MEDIA_MESSAGE, media }
      window.postMessage(message, window.location.origin)
    }

    const isGraphQL = (url: string) => url.includes("/graphql/")

    const originalOpen = XMLHttpRequest.prototype.open
    XMLHttpRequest.prototype.open = function (this: XMLHttpRequest, ...args: Parameters<typeof originalOpen>) {
      const url = String(args[1])
      if (isGraphQL(url)) {
        this.addEventListener("load", () => {
          try {
            publish(this.responseType === "json" ? this.response : JSON.parse(this.responseText))
          } catch {
            // Not JSON; nothing to read.
          }
        })
      }
      return originalOpen.apply(this, args)
    } as typeof originalOpen

    const originalFetch = window.fetch
    window.fetch = async (...args) => {
      const response = await originalFetch(...args)
      const url = args[0] instanceof Request ? args[0].url : String(args[0])
      if (isGraphQL(url)) {
        response
          .clone()
          .json()
          .then(publish)
          .catch(() => {})
      }
      return response
    }
  },
})
